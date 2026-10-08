#!/usr/bin/env bash
# Shared helpers for scripts/*.sh. Source it; callers already run with set -euo pipefail:
#   . "$SCRIPT_DIR/lib/common.sh"
# Must stay compatible with macOS bash 3.2.
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

# VM layout. Overridable only so tests can point at a temp dir.
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_CONTAINER_UID=1000
readonly SSH_CONNECT_TIMEOUT_SECONDS=10
readonly HEALTH_TIMEOUT_SECONDS=180

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

step() { log "==> $*"; }

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing command '$cmd': install it (see README.md, Prerequisites)"
  done
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || die "missing env $name: copy .env.example to .env and set it"
  done
}

# mask VALUE -> first 4 characters + ****, or **** for short values. Use before printing secrets or ids.
mask() {
  local value="$1"
  if ((${#value} <= 8)); then
    printf '****'
  else
    printf '%s****' "${value:0:4}"
  fi
}

# remote CMD -> run CMD on the VM over Tailscale SSH.
remote() {
  ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "${BM_VM_USER}@${BM_VM_HOST}" "$@"
}

# remote_compose ARGS -> docker compose ARGS inside the VM app dir.
remote_compose() {
  remote "cd $BM_REMOTE_APP_DIR && docker compose $*"
}

# vm_env -> the .env content for the VM: loopback port plus absolute data paths (shared by deploy and restore).
vm_env() {
  printf 'BM_PORT=%s\n' "${BM_PORT:-8737}"
  printf 'BM_KNOWLEDGE_DIR=%s/knowledge\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_CONFIG_DIR=%s/config\n' "$BM_REMOTE_DATA_ROOT"
}

# manifest_cmd DIR -> a shell command (run it with `remote`) that prints "<sha256>  ./<path>" for every file
# under DIR, sorted by path. The one definition backup.sh, restore.sh and the tests share, so their
# manifests cannot drift apart. pipefail makes a failing find fail the command instead of printing a short list.
manifest_cmd() {
  printf 'set -o pipefail; cd %s && sudo -n find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2' "$1"
}

# sha256_of FILE -> hex digest (sha256sum on Linux, shasum on macOS).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
