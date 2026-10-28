#!/usr/bin/env bash
# VM helpers for scripts/*.sh: the VM layout, the access mode, SSH and compose on the VM, and the data manifest.
# Sources common.sh. Must stay compatible with macOS bash 3.2.
#   access_mode -> tailscale or ssh (BM_ACCESS); dies on any other value
#   web_mode -> on or off (BM_WEB, the claude.ai web connector); dies on any other value
#   access_hint -> what to check when SSH to the VM fails, for the current access mode
#   require_vm [CMD...] -> dies unless the access mode, the web mode, ssh, every CMD and the VM settings are there
#   require_web_host -> with BM_WEB=on, dies unless BM_WEB_HOST is a bare host name (names the variable, never its value)
#   require_web_env_matches_env_file -> dies when a web setting differs from its raw line in SB_ENV_FILE (make changed it)
#   require_web_settings -> with BM_WEB=on, dies unless the host, the GitHub user id and client id and the three secrets are well formed
#   local_port_open PORT -> exit 0 when something listens on 127.0.0.1:PORT
#   require_free_port NAME PORT [HINT] -> dies unless PORT is a free unprivileged port on 127.0.0.1
#   forward_spec LOCAL_PORT REMOTE_PORT -> an ssh -L argument bound to 127.0.0.1 on both ends
#   tunnel_args MCP_LOCAL_PORT WEB_LOCAL_PORT [SSH_OPTION...] -> set TUNNEL_ARGS to the ssh arguments of a tunnel
#   remote CMD -> run CMD on the VM over SSH (after require_vm)
#   remote_compose [--if-deployed] ARGS -> docker compose ARGS in the VM app dir
#   exists_cmd PATH -> a sh command that prints present or absent for PATH
#   remote_exists PATH -> present or absent for PATH on the VM; fails when the VM does not answer
#   vm_tailscale_logged_in -> exit 0 when Tailscale on the VM is logged in, 1 when it is not
#   vm_env -> the .env content for the VM (with BM_WEB=on also the web connector settings and the gateway code hash)
#   gateway_code_sha256 DIR -> one sha256 over the GATEWAY_RUNTIME_FILES in DIR, in their listed order
#   upload_gateway_files -> with BM_WEB=on, upload the gateway runtime files under temporary names and mv -f them into place (deploy and restore)
#   backup_gateway_files DIR -> with BM_WEB=on, copy the live gateway files into DIR on the VM and set GATEWAY_BACKUP_DIR (restore)
#   gateway_rollback_cmd DIR -> a command for `remote` that puts the files backed up in DIR back (restore's rollback)
#   manifest_cmd DIR -> a command printing "<sha256>  ./<path>" for every data file under DIR
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
# The gateway files the VM needs next to compose.yaml, relative to gateway/ here and to the app dir there.
readonly GATEWAY_RUNTIME_FILES="boot.py gateway.py requirements.txt"
# What a .env value may hold: make and docker compose read the file literally (# starts a comment, $ expands).
readonly WEB_ENV_VALUE_PATTERN='^[A-Za-z0-9._~+/=-]+$'
readonly WEB_HOST_PATTERN='^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$'
readonly WEB_USER_ID_PATTERN='^[0-9]+$'
# The shortest BM_WEB_JWT_KEY: the same value as MIN_JWT_KEY_LENGTH in gateway/gateway.py, which refuses a shorter key
# at start, so deploy and restore stop on it before they touch the VM.
readonly MIN_WEB_JWT_KEY_LENGTH=32

# access_mode -> tailscale or ssh: BM_ACCESS, or tailscale when it is unset (.env files from before the ssh mode).
# Any other value, another case included, stops here so no script falls back to the wrong path.
# Call it as mode="$(access_mode)" || exit 1.
access_mode() {
  local mode="${BM_ACCESS:-tailscale}"
  case "$mode" in
    tailscale | ssh) printf '%s\n' "$mode" ;;
    *) die "BM_ACCESS must be tailscale or ssh (got '$mode'): set it in .env in the main checkout (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)" ;;
  esac
}

# web_mode -> on or off: BM_WEB, or off when it is unset or empty (.env files from before the web connector).
# Any other value, another case included, stops here so no target half-enables the gateway.
# Call it as web="$(web_mode)" || exit 1.
web_mode() {
  local mode="${BM_WEB:-off}"
  case "$mode" in
    on | off) printf '%s\n' "$mode" ;;
    *) die "BM_WEB must be on or off (got '$mode'): set it in .env in the main checkout" ;;
  esac
}

# access_hint -> what to check when SSH to the VM fails, for the current access mode.
access_hint() {
  local mode
  mode="$(access_mode)" || return 1
  if [[ "$mode" == ssh ]]; then
    printf 'check the ProxyCommand for %s in ~/.ssh/config and its login (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md)\n' "$BM_VM_HOST"
  else
    printf 'is %s reachable over Tailscale SSH? (ssh %s@%s true)\n' "$BM_VM_HOST" "$BM_VM_USER" "$BM_VM_HOST"
  fi
}

# require_vm [CMD...] -> dies unless BM_ACCESS is a known mode, ssh and every CMD are installed, and BM_VM_HOST and
# BM_VM_USER are set. Every script that reaches the VM calls it first, so a typo in BM_ACCESS stops it before any
# ssh, also when the script never reads the mode.
# shellcheck disable=SC2120  # CMD... is optional: most callers need only ssh
require_vm() {
  access_mode >/dev/null
  web_mode >/dev/null
  require_cmd ssh "$@"
  require_env BM_VM_HOST BM_VM_USER
}

# require_web_host -> with BM_WEB=on, dies unless BM_WEB_HOST is set and a bare host name (no scheme, path or port).
# Names the variable only: the host name is not printed.
require_web_host() {
  local web
  web="$(web_mode)" || return 1
  [[ "$web" == on ]] || return 0
  require_env BM_WEB_HOST
  [[ "$BM_WEB_HOST" =~ $WEB_HOST_PATTERN ]] \
    || die "BM_WEB_HOST must be a host name like mcp.<domain>, without https://, a path or a port: fix it in .env in the main checkout"
}

# Every web setting that comes from the main checkout .env, compared with its raw line by require_web_env_matches_env_file.
readonly WEB_ENV_FILE_VARIABLES="BM_WEB_HOST BM_WEB_GITHUB_USER_ID BM_WEB_GITHUB_CLIENT_ID BM_WEB_GITHUB_CLIENT_SECRET BM_WEB_JWT_KEY BM_WEB_TUNNEL_TOKEN"

# require_web_env_matches_env_file -> when SB_ENV_FILE names an existing file, dies unless each web setting that has a
# line in it equals the value of its last NAME= line (without a trailing CR). make reads .env as makefile text: # starts
# a comment and $x expands, so a secret it cut short can still pass the pattern checks. Same idea as
# require_sb_user_matches_env_file; a variable without a line in the file is not compared. Names the variable only,
# never a value.
require_web_env_matches_env_file() {
  local name line raw found
  [[ -n "${SB_ENV_FILE:-}" && -f "$SB_ENV_FILE" ]] || return 0
  for name in $WEB_ENV_FILE_VARIABLES; do
    found="" raw=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        "$name="*)
          raw="${line#"$name="}"
          found=1
          ;;
      esac
    done <"$SB_ENV_FILE" || die "could not read $SB_ENV_FILE: check that you can read it"
    [[ -n "$found" ]] || continue
    raw="${raw%$'\r'}"
    [[ "$raw" == "${!name:-}" ]] \
      || die "$name in $SB_ENV_FILE holds characters that make changes when it reads .env (#, \$, spaces or quotes), so the scripts got a different value: write it as $name=<value> with only letters, digits and ._~+/=- in the value"
  done
}

# require_web_settings -> with BM_WEB=on, dies unless BM_WEB_HOST, BM_WEB_GITHUB_USER_ID (digits), BM_WEB_GITHUB_CLIENT_ID
# and the three secrets (BM_WEB_GITHUB_CLIENT_SECRET, BM_WEB_JWT_KEY, BM_WEB_TUNNEL_TOKEN) are set and well formed, and
# equal to their raw lines in SB_ENV_FILE when it is set (require_web_env_matches_env_file). The secrets and the client
# id may hold only the characters of WEB_ENV_VALUE_PATTERN, because .env is read literally, and BM_WEB_JWT_KEY needs at
# least MIN_WEB_JWT_KEY_LENGTH characters. Names the variable only, never a value. Deploy and restore call it before
# any ssh.
require_web_settings() {
  local web name
  web="$(web_mode)" || return 1
  [[ "$web" == on ]] || return 0
  require_web_env_matches_env_file
  require_web_host
  require_env BM_WEB_GITHUB_USER_ID
  [[ "$BM_WEB_GITHUB_USER_ID" =~ $WEB_USER_ID_PATTERN ]] \
    || die "BM_WEB_GITHUB_USER_ID must be the numeric GitHub user id (digits only): fix it in .env in the main checkout"
  for name in BM_WEB_GITHUB_CLIENT_ID BM_WEB_GITHUB_CLIENT_SECRET BM_WEB_JWT_KEY BM_WEB_TUNNEL_TOKEN; do
    require_env "$name"
    [[ "${!name}" =~ $WEB_ENV_VALUE_PATTERN ]] \
      || die "$name must be made of letters, digits and ._~+/=- (make and docker compose change other characters such as #, \$ and spaces): fix it in .env in the main checkout"
  done
  ((${#BM_WEB_JWT_KEY} >= MIN_WEB_JWT_KEY_LENGTH)) \
    || die "BM_WEB_JWT_KEY must be at least $MIN_WEB_JWT_KEY_LENGTH characters (make one with 'openssl rand -hex 32'): fix it in .env in the main checkout"
}

readonly MIN_LOCAL_PORT=1024
readonly MAX_LOCAL_PORT=65535

# local_port_open PORT -> exit 0 when something listens on 127.0.0.1:PORT.
local_port_open() {
  nc -z 127.0.0.1 "$1" >/dev/null 2>&1
}

# require_free_port NAME PORT [HINT] -> dies unless PORT is an unprivileged port number that nothing on 127.0.0.1
# listens on. HINT (default: another 'make tunnel'? or set NAME in .env) says what to do about a port in use.
require_free_port() {
  local name="$1" port="$2" hint="${3:-another 'make tunnel'? or set $1 in .env}"
  if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || ((port < MIN_LOCAL_PORT || port > MAX_LOCAL_PORT)); then
    die "$name must be a port number from $MIN_LOCAL_PORT to $MAX_LOCAL_PORT (got '$port')"
  fi
  if local_port_open "$port"; then
    die "port $port is in use on 127.0.0.1: $hint"
  fi
}

# forward_spec LOCAL_PORT REMOTE_PORT -> an ssh -L argument that binds LOCAL_PORT on 127.0.0.1 only and forwards it to
# REMOTE_PORT on the VM's loopback. Every -L goes through here, so no tunnel listens beyond this machine.
forward_spec() {
  printf '127.0.0.1:%s:127.0.0.1:%s\n' "$1" "$2"
}

# tunnel_args MCP_LOCAL_PORT WEB_LOCAL_PORT [SSH_OPTION...] -> set the array TUNNEL_ARGS to the ssh arguments of a
# tunnel that forwards MCP_LOCAL_PORT and WEB_LOCAL_PORT on 127.0.0.1 (forward_spec) to Basic Memory and SilverBullet
# on the VM's loopback, with SSH_OPTION... after ExitOnForwardFailure (ssh exits at once when a forward cannot bind).
# It does not run ssh: the caller does, so `ssh "${TUNNEL_ARGS[@]}" &` leaves the pid of ssh itself in $!.
tunnel_args() {
  local mcp_port="$1" web_port="$2"
  shift 2
  TUNNEL_ARGS=(-N -o ExitOnForwardFailure=yes "$@"
    -L "$(forward_spec "$mcp_port" "${BM_PORT:-$DEFAULT_BM_PORT}")"
    -L "$(forward_spec "$web_port" "${SB_PORT:-$DEFAULT_SB_PORT}")"
    "$BM_VM_USER@$BM_VM_HOST")
}

# remote CMD -> run CMD on the VM over SSH: Tailscale SSH, or the ssh access mode's host alias. Callers run require_vm
# first, which checks BM_ACCESS and the VM settings.
remote() {
  ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "${BM_VM_USER}@${BM_VM_HOST}" "$@"
}

# remote_compose [--if-deployed] ARGS -> docker compose ARGS inside the VM app dir. With --if-deployed it does nothing,
# and succeeds, while the app dir has no compose.yaml yet (a recreated VM). No bare `return` here: restore's rollback
# trap calls it, and in a trap a bare return gives the status from before the trap.
remote_compose() {
  if [[ "${1:-}" == --if-deployed ]]; then
    shift
    remote "if [ -e $BM_REMOTE_APP_DIR/compose.yaml ]; then cd $BM_REMOTE_APP_DIR && docker compose $*; fi"
  else
    remote "cd $BM_REMOTE_APP_DIR && docker compose $*"
  fi
}

# exists_cmd PATH -> a sh command that prints present or absent for PATH (no spaces or quotes in PATH).
exists_cmd() {
  printf 'if [ -e %s ]; then echo present; else echo absent; fi' "$1"
}

# remote_exists PATH -> present or absent for PATH on the VM. Fails when the VM does not answer, so a lost connection
# never reads as absent. Use: state="$(remote_exists PATH)" || <handle the failure>
remote_exists() {
  remote "$(exists_cmd "$1")"
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
# deploy and restore; both run require_sb_user and require_web_settings first). With BM_WEB=on it adds the profiles of
# the gateway and the tunnel, the gateway port, data dir and public base URL, the web connector settings, and
# BM_WEB_CODE_SHA256 (gateway_code_sha256): compose.yaml passes it to the gateway, so a change of the bind-mounted gateway
# code or its pinned dependencies changes the service and `up -d` recreates the container.
vm_env() {
  local web code_sha256
  web="$(web_mode)" || return 1
  printf 'BM_PORT=%s\n' "${BM_PORT:-$DEFAULT_BM_PORT}"
  printf 'BM_KNOWLEDGE_DIR=%s/knowledge\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_CONFIG_DIR=%s/config\n' "$BM_REMOTE_DATA_ROOT"
  printf 'SB_PORT=%s\n' "${SB_PORT:-$DEFAULT_SB_PORT}"
  printf 'SB_USER=%s\n' "$SB_USER"
  [[ "$web" == on ]] || return 0
  code_sha256="$(gateway_code_sha256 "$REPO_DIR/gateway")" || return 1
  printf 'COMPOSE_PROFILES=web,tunnel\n'
  printf 'BM_WEB_PORT=%s\n' "${BM_WEB_PORT:-$DEFAULT_BM_WEB_PORT}"
  printf 'BM_WEB_DATA_DIR=%s/gateway\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_WEB_BASE_URL=https://%s\n' "$BM_WEB_HOST"
  printf 'BM_WEB_GITHUB_USER_ID=%s\n' "$BM_WEB_GITHUB_USER_ID"
  printf 'BM_WEB_GITHUB_CLIENT_ID=%s\n' "$BM_WEB_GITHUB_CLIENT_ID"
  printf 'BM_WEB_GITHUB_CLIENT_SECRET=%s\n' "$BM_WEB_GITHUB_CLIENT_SECRET"
  printf 'BM_WEB_JWT_KEY=%s\n' "$BM_WEB_JWT_KEY"
  printf 'BM_WEB_TUNNEL_TOKEN=%s\n' "$BM_WEB_TUNNEL_TOKEN"
  printf 'BM_WEB_CODE_SHA256=%s\n' "$code_sha256"
}

# gateway_code_sha256 DIR -> one sha256 over the GATEWAY_RUNTIME_FILES in DIR, in their listed order: the digest of the
# "<sha256>  <name>" lines of the files, so a change in any one of them, or bytes moved between them, changes it.
gateway_code_sha256() {
  local dir="$1" file digest lines=""
  for file in $GATEWAY_RUNTIME_FILES; do
    digest="$(sha256_of "$dir/$file")" || return 1
    lines="$lines$digest  $file"$'\n'
  done
  printf '%s' "$lines" | sha256_of /dev/stdin
}

# Set by backup_gateway_files to the backup directory once the live runtime files are copied there; empty means a
# rollback has nothing to put back (BM_WEB off, or no backup made).
GATEWAY_BACKUP_DIR=""

# upload_gateway_files -> with BM_WEB=on, uploads each of GATEWAY_RUNTIME_FILES into $BM_REMOTE_APP_DIR/gateway under a
# temporary name (.<name>.new), and only when every file arrived moves them onto their names with one `mv -f` command.
# The folder itself is never renamed: compose bind-mounts it into the gateway container, and a renamed folder would
# leave a running container on the old one. Each file is replaced atomically, and a failed upload leaves the live files
# untouched (a leftover temporary file is overwritten by the next upload). Does nothing, and prints nothing, while
# BM_WEB is off.
upload_gateway_files() {
  local web file live moves=""
  web="$(web_mode)" || return 1
  [[ "$web" == on ]] || return 0
  live="$BM_REMOTE_APP_DIR/gateway"
  step "upload the gateway runtime files to $BM_VM_HOST:$live (temporary names, then moved onto the real ones)"
  remote "mkdir -p $live" || die "could not create $live on the VM: $(access_hint)"
  for file in $GATEWAY_RUNTIME_FILES; do
    remote "cat > $live/.$file.new" <"$REPO_DIR/gateway/$file" \
      || die "upload of gateway/$file failed; the live gateway files were not touched: $(access_hint)"
    moves="${moves:+$moves && }mv -f $live/.$file.new $live/$file"
  done
  remote "$moves" || die "could not move the uploaded gateway files into place in $live on the VM: $(access_hint)"
}

# backup_gateway_files DIR -> with BM_WEB=on, copies the live runtime files that exist into DIR on the VM (created even
# when there are none, which means "the VM had no gateway files") and only then sets GATEWAY_BACKUP_DIR to DIR, so a
# rollback never reads a half-made backup. Does nothing, and prints nothing, while BM_WEB is off.
backup_gateway_files() {
  local dir="$1" web file live cmd="mkdir -p $1"
  web="$(web_mode)" || return 1
  [[ "$web" == on ]] || return 0
  live="$BM_REMOTE_APP_DIR/gateway"
  for file in $GATEWAY_RUNTIME_FILES; do
    cmd="$cmd && { [ ! -e $live/$file ] || cp -p $live/$file $dir/$file; }"
  done
  step "back up the live gateway files to $dir"
  remote "$cmd" || die "could not back up the gateway files on the VM; nothing was changed: $(access_hint)"
  GATEWAY_BACKUP_DIR="$dir"
}

# gateway_rollback_cmd DIR -> a shell command (run it with `remote`) that puts the files backed up in DIR back, each
# through a temporary name and `mv -f` like the upload, removes the runtime files DIR does not hold (this run added
# them), and removes DIR only when all of that worked.
gateway_rollback_cmd() {
  local dir="$1" live="$BM_REMOTE_APP_DIR/gateway"
  # shellcheck disable=SC2016  # $f, $ok are for the shell on the VM
  printf 'ok=1; for f in %s; do if [ -e %s/$f ]; then cp -p %s/$f %s/.$f.new && mv -f %s/.$f.new %s/$f || ok=0; else rm -f %s/$f || ok=0; fi; done; [ $ok = 1 ] && rm -rf %s' \
    "$GATEWAY_RUNTIME_FILES" "$dir" "$dir" "$live" "$live" "$live" "$live" "$dir"
}

# manifest_cmd DIR -> a shell command (run it with `remote`) that prints "<sha256>  ./<path>" for every file
# under DIR except the model cache, sorted by path. The one definition backup-notes.sh, restore-notes.sh and the tests share, so their
# manifests cannot drift apart. pipefail makes a failing find fail the command instead of printing a short list.
manifest_cmd() {
  printf 'set -o pipefail; cd %s && sudo -n find . -path ./%s -prune -o -type f -exec sha256sum {} + | LC_ALL=C sort -k2' "$1" "$BM_MODEL_CACHE_REL_PATH"
}
