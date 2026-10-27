#!/usr/bin/env bash
# Core helpers for scripts/*.sh and the other scripts/lib/ libraries, which source this file. Source it; callers
# already run with set -euo pipefail:
#   . "$SCRIPT_DIR/lib/common.sh"
# Must stay compatible with macOS bash 3.2.
#   log MESSAGE -> a timestamped line on stderr
#   step MESSAGE -> log with a ==> marker
#   die MESSAGE -> ERROR line on stderr, exit 1
#   require_cmd CMD... -> dies unless every command is installed
#   require_env NAME... -> dies unless every variable is set and not empty
#   mask VALUE -> first 4 characters + ****, for printing secrets and ids
#   utc_stamp -> the current UTC time as YYYYMMDDTHHMMSSZ
#   main_checkout_root [DIR] -> the main checkout that DIR belongs to
#   sha256_of FILE -> hex digest of a local file
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_COMMON:-}" ] && return 0
readonly _BM_LIB_COMMON=1

# Directory of this file. A script in a linked worktree sources its own copy, so this finds the right repo.
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
readonly COMMON_LIB_DIR
# Root of the repo holding these scripts. Never read from the environment: the tests export their own REPO_DIR.
REPO_DIR="$(dirname "$(dirname "$COMMON_LIB_DIR")")" || exit 1
readonly REPO_DIR
# Loopback ports of Basic Memory, SilverBullet and the web gateway when .env sets none (the Makefile repeats them for
# make).
readonly DEFAULT_BM_PORT=8737
readonly DEFAULT_SB_PORT=3000
readonly DEFAULT_BM_WEB_PORT=8738
# ssh access mode: local ends of make tunnel (Basic Memory, web UI) when .env sets no BM_TUNNEL_*_PORT.
readonly DEFAULT_TUNNEL_MCP_PORT=18737
readonly DEFAULT_TUNNEL_WEB_PORT=13000
# Suffix of a file still being written; it gets its final name only when complete.
readonly PARTIAL_SUFFIX=".partial"

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
    [[ -n "${!name:-}" ]] || die "missing env $name: set it in .env in the main checkout (copy .env.example there; see docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md)"
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

# utc_stamp -> the current UTC time as YYYYMMDDTHHMMSSZ, the stamp in backup and restore names and verify notes.
utc_stamp() { date -u +%Y%m%dT%H%M%SZ; }

# main_checkout_root [DIR] -> absolute path of the main checkout that DIR (default: the repo holding these
# scripts) belongs to. Linked worktrees share the main checkout's .git, so its parent is the main root.
# .env and backups/ are git-ignored, so each checkout has its own; this is the one that keeps them.
main_checkout_root() {
  local common
  common="$(git -C "${1:-$COMMON_LIB_DIR}" rev-parse --path-format=absolute --git-common-dir)" || return 1
  dirname "$common"
}

# sha256_of FILE -> hex digest (sha256sum on Linux, shasum on macOS).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
