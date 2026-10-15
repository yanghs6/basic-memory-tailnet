#!/usr/bin/env bash
# Shared helpers for scripts/*.sh. Source it; callers already run with set -euo pipefail:
#   . "$SCRIPT_DIR/lib/common.sh"
# Must stay compatible with macOS bash 3.2.
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

# Directory of this file. A script in a linked worktree sources its own copy, so this finds the right repo.
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
readonly COMMON_LIB_DIR

# VM layout. Overridable only so tests can point at a temp dir.
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_CONTAINER_UID=1000
# Path under the data root of the FastEmbed model cache: re-downloadable and full of symlinks, so backups skip it.
readonly BM_MODEL_CACHE_REL_PATH="config/fastembed_cache"
readonly SSH_CONNECT_TIMEOUT_SECONDS=10
# Longer than the compose healthcheck start_period (300s) so `up --wait` can use the whole grace period.
readonly HEALTH_TIMEOUT_SECONDS=360

# SilverBullet space = the Basic Memory notes folder of project main. The local path is overridable only for tests.
SB_LOCAL_NOTES_DIR="${SB_LOCAL_NOTES_DIR:-$(dirname "$(dirname "$COMMON_LIB_DIR")")/.local-data/knowledge/basic-memory}"
readonly SB_LOCAL_NOTES_DIR
readonly SB_REMOTE_NOTES_DIR="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
# Where the managed library page (silverbullet/agent-hub.md) loads the WOFF2 fonts from.
readonly SB_FONTS_REL_DIR="Library/agent-hub/fonts"
# Marker in the notes folder: Basic Memory has not loaded the current .gitignore yet (it reads it only at start).
# sb-space.sh creates it before changing .gitignore and writes no pages while it exists; callers remove it only after
# recreating Basic Memory. Basic Memory skips dotfiles (default pattern .*) and SilverBullet cannot read them.
readonly SB_GITIGNORE_PENDING=".gitignore.pending"

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
    [[ -n "${!name:-}" ]] || die "missing env $name: set it in .env in the main checkout (copy .env.example there; see docs/runbooks/accounts.md)"
  done
}

# Characters that make (it includes .env literally), docker compose .env files and form encoding all keep as they are.
readonly SB_USER_PATTERN='^[A-Za-z0-9._-]+:[A-Za-z0-9._~+/=-]+$'

# require_sb_user -> dies unless SB_USER is set and looks like <user>:<password>. Never prints the value.
require_sb_user() {
  require_env SB_USER
  [[ "$SB_USER" =~ $SB_USER_PATTERN ]] \
    || die "SB_USER must be <user>:<password> made of letters, digits and ._~+/=- (make and docker compose change other characters): fix it in .env in the main checkout"
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

# notes_dir_arg [--local] -> the local notes folder for --local; nothing (meaning the VM) without an argument, after
# checking the VM settings. Any other argument dies with the usage. Use: local_dir="$(notes_dir_arg "$@")" || exit 1
notes_dir_arg() {
  case "${1:-}" in
    "")
      require_cmd ssh
      require_env BM_VM_HOST BM_VM_USER
      ;;
    --local) printf '%s' "$SB_LOCAL_NOTES_DIR" ;;
    *) die "usage: $(basename "$0") [--local]" ;;
  esac
}

# in_notes_dir LOCAL_DIR CMD -> run the sh command CMD inside the notes folder, creating it first: LOCAL_DIR when set,
# else the VM folder as the container user, so Basic Memory and SilverBullet can rewrite the files. stdin reaches CMD.
# CMD must not contain single quotes.
in_notes_dir() {
  if [[ -n "$1" ]]; then
    mkdir -p "$1" && (cd "$1" && sh -c "$2")
  else
    remote "sudo -n -u '#$BM_CONTAINER_UID' sh -c 'mkdir -p $SB_REMOTE_NOTES_DIR && cd $SB_REMOTE_NOTES_DIR && $2'"
  fi
}

# write_notes_file LOCAL_DIR PATH -> replace PATH (relative to the notes folder, without spaces) with stdin.
write_notes_file() {
  in_notes_dir "$1" "mkdir -p $(dirname "$2") && cat > $2"
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

# main_checkout_root [DIR] -> absolute path of the main checkout that DIR (default: the repo holding these
# scripts) belongs to. Linked worktrees share the main checkout's .git, so its parent is the main root.
# .env and backups/ are git-ignored, so each checkout has its own; this is the one that keeps them.
main_checkout_root() {
  local common
  common="$(git -C "${1:-$COMMON_LIB_DIR}" rev-parse --path-format=absolute --git-common-dir)" || return 1
  dirname "$common"
}
