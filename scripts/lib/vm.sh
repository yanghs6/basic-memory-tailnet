#!/usr/bin/env bash
# VM helpers for scripts/*.sh: the VM layout, the access mode, SSH and compose on the VM, and the data manifest.
# Sources common.sh. Must stay compatible with macOS bash 3.2.
#   access_mode -> tailscale or ssh (BM_ACCESS); dies on any other value
#   access_hint -> what to check when SSH to the VM fails, for the current access mode
#   require_free_port NAME PORT [HINT] -> dies unless PORT is a free unprivileged port on 127.0.0.1
#   forward_spec LOCAL_PORT REMOTE_PORT -> an ssh -L argument bound to 127.0.0.1 on both ends
#   remote CMD -> run CMD on the VM over SSH
#   remote_compose ARGS -> docker compose ARGS in the VM app dir
#   vm_tailscale_logged_in -> exit 0 when Tailscale on the VM is logged in, 1 when it is not
#   vm_env -> the .env content for the VM
#   manifest_cmd DIR -> a command printing "<sha256>  ./<path>" for every data file under DIR
#   sha256_of FILE -> hex digest of a local file
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_VM:-}" ] && return 0
readonly _BM_LIB_VM=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

# VM layout. Overridable only so tests can point at a temp dir.
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_CONTAINER_UID=1000
# Path under the data root of the FastEmbed model cache: re-downloadable and full of symlinks, so backups skip it.
readonly BM_MODEL_CACHE_REL_PATH="config/fastembed_cache"
readonly SSH_CONNECT_TIMEOUT_SECONDS=10
# Longer than the compose healthcheck start_period (300s) so `up --wait` can use the whole grace period.
readonly HEALTH_TIMEOUT_SECONDS=360

# access_mode -> tailscale or ssh: BM_ACCESS, or tailscale when it is unset (.env files from before the ssh mode).
# Any other value, another case included, stops here so no script falls back to the wrong path.
# Call it as mode="$(access_mode)" || exit 1.
access_mode() {
  local mode="${BM_ACCESS:-tailscale}"
  case "$mode" in
    tailscale | ssh) printf '%s\n' "$mode" ;;
    *) die "BM_ACCESS must be tailscale or ssh (got '$mode'): set it in .env in the main checkout (docs/runbooks/rbk-2026-10-12-bootstrap.md)" ;;
  esac
}

# access_hint -> what to check when SSH to the VM fails, for the current access mode.
access_hint() {
  if [[ "${BM_ACCESS:-tailscale}" == ssh ]]; then
    printf 'check the ProxyCommand for %s in ~/.ssh/config and its login (docs/runbooks/rbk-2026-10-12-gcp-vm.md)\n' "$BM_VM_HOST"
  else
    printf 'is %s reachable over Tailscale SSH? (ssh %s@%s true)\n' "$BM_VM_HOST" "$BM_VM_USER" "$BM_VM_HOST"
  fi
}

readonly MIN_LOCAL_PORT=1024
readonly MAX_LOCAL_PORT=65535

# require_free_port NAME PORT [HINT] -> dies unless PORT is an unprivileged port number that nothing on 127.0.0.1
# listens on. HINT (default: another 'make tunnel'? or set NAME in .env) says what to do about a port in use.
require_free_port() {
  local name="$1" port="$2" hint="${3:-another 'make tunnel'? or set $1 in .env}"
  if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || ((port < MIN_LOCAL_PORT || port > MAX_LOCAL_PORT)); then
    die "$name must be a port number from $MIN_LOCAL_PORT to $MAX_LOCAL_PORT (got '$port')"
  fi
  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    die "port $port is in use on 127.0.0.1: $hint"
  fi
}

# forward_spec LOCAL_PORT REMOTE_PORT -> an ssh -L argument that binds LOCAL_PORT on 127.0.0.1 only and forwards it to
# REMOTE_PORT on the VM's loopback. Every -L goes through here, so no tunnel listens beyond this machine.
forward_spec() {
  printf '127.0.0.1:%s:127.0.0.1:%s\n' "$1" "$2"
}

# remote CMD -> run CMD on the VM over SSH: Tailscale SSH, or the ssh access mode's host alias. It checks BM_ACCESS
# first, so a typo there stops every VM target before it reaches the VM, also the ones that never read the mode.
remote() {
  access_mode >/dev/null
  ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "${BM_VM_USER}@${BM_VM_HOST}" "$@"
}

# remote_compose ARGS -> docker compose ARGS inside the VM app dir.
remote_compose() {
  remote "cd $BM_REMOTE_APP_DIR && docker compose $*"
}

# vm_tailscale_logged_in -> exit 0 when Tailscale on the VM is logged in (BackendState Running), 1 when it is not
# installed or its BackendState is NeedsLogin, NeedsMachineAuth, Stopped or NoState. Dies when the state cannot be
# read (no SSH, no passwordless sudo, tailscaled down) or is unknown, so the ssh mode's checks never pass on an error.
vm_tailscale_logged_in() {
  local out state
  out="$(remote "if command -v tailscale >/dev/null 2>&1; then sudo -n tailscale status --json; else echo missing; fi")" \
    || die "could not read the Tailscale state on $BM_VM_HOST: $(access_hint); on the VM 'sudo -n tailscale status --json' must work"
  [[ "$out" != missing ]] || return 1
  state="$(jq -r '.BackendState // empty' <<<"$out" 2>/dev/null)" || state=""
  case "$state" in
    Running) return 0 ;;
    NeedsLogin | NeedsMachineAuth | Stopped | NoState) return 1 ;;
    *) die "unexpected Tailscale state on $BM_VM_HOST: '$state' (expected Running, NeedsLogin, NeedsMachineAuth, Stopped or NoState)" ;;
  esac
}

# vm_env -> the .env content for the VM: loopback ports, absolute data paths and the SilverBullet login (shared by
# deploy and restore; both run require_sb_user first).
vm_env() {
  printf 'BM_PORT=%s\n' "${BM_PORT:-8737}"
  printf 'BM_KNOWLEDGE_DIR=%s/knowledge\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_CONFIG_DIR=%s/config\n' "$BM_REMOTE_DATA_ROOT"
  printf 'SB_PORT=%s\n' "${SB_PORT:-3000}"
  printf 'SB_USER=%s\n' "$SB_USER"
}

# manifest_cmd DIR -> a shell command (run it with `remote`) that prints "<sha256>  ./<path>" for every file
# under DIR except the model cache, sorted by path. The one definition backup.sh, restore.sh and the tests share, so their
# manifests cannot drift apart. pipefail makes a failing find fail the command instead of printing a short list.
manifest_cmd() {
  printf 'set -o pipefail; cd %s && sudo -n find . -path ./%s -prune -o -type f -exec sha256sum {} + | LC_ALL=C sort -k2' "$1" "$BM_MODEL_CACHE_REL_PATH"
}

# sha256_of FILE -> hex digest (sha256sum on Linux, shasum on macOS).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
