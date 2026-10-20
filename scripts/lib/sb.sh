#!/usr/bin/env bash
# SilverBullet helpers for scripts/*.sh: the space in the Basic Memory notes folder, locally or on the VM, and the
# SilverBullet login. Sources common.sh and vm.sh. Must stay compatible with macOS bash 3.2.
#   require_sb_user -> dies unless SB_USER is set and looks like <user>:<password>
#   require_sb_user_matches_env_file -> dies when make changed SB_USER while it read .env
#   notes_dir_arg [--local] -> the local notes folder for --local, nothing (the VM) without an argument
#   in_notes_dir LOCAL_DIR CMD -> run CMD inside the notes folder, locally or on the VM as the container user
#   write_notes_file LOCAL_DIR PATH -> replace PATH in the notes folder with stdin
#   notes_file_state LOCAL_DIR PATH -> present or absent for PATH in the notes folder
#   sb_space_apply WHERE RERUN [RECREATE_CMD...] -> write the space files, recreating Basic Memory when needed
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_SB:-}" ] && return 0
readonly _BM_LIB_SB=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=vm.sh
. "${BASH_SOURCE[0]%/*}/vm.sh"

# SilverBullet space = the Basic Memory notes folder of project main. The local path is overridable only for tests.
readonly SB_LOCAL_NOTES_DIR="${SB_LOCAL_NOTES_DIR:-$REPO_DIR/.local-data/knowledge/basic-memory}"
readonly SB_REMOTE_NOTES_DIR="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
# Where the managed library page (silverbullet/agent-hub.md) loads the WOFF2 fonts from.
readonly SB_FONTS_REL_DIR="Library/agent-hub/fonts"
# Marker in the notes folder: Basic Memory has not loaded the current .gitignore yet (it reads it only at start).
# sb-space.sh creates it before changing .gitignore and writes no pages while it exists; callers remove it only after
# recreating Basic Memory. Basic Memory skips dotfiles (default pattern .*) and SilverBullet cannot read them.
readonly SB_GITIGNORE_PENDING=".gitignore.pending"

# Characters that make (it includes .env literally), docker compose .env files and form encoding all keep as they are.
readonly SB_USER_PATTERN='^[A-Za-z0-9._-]+:[A-Za-z0-9._~+/=-]+$'

# require_sb_user -> dies unless SB_USER is set and looks like <user>:<password>. Never prints the value.
require_sb_user() {
  require_sb_user_matches_env_file
  require_env SB_USER
  [[ "$SB_USER" =~ $SB_USER_PATTERN ]] \
    || die "SB_USER must be <user>:<password> made of letters, digits and ._~+/=- (make and docker compose change other characters): fix it in .env in the main checkout"
}

# require_sb_user_matches_env_file -> when SB_ENV_FILE names an existing file, dies unless SB_USER equals the value of its
# last SB_USER= line (without a trailing CR). make reads .env as makefile text: # starts a comment and $x expands, so a
# value it cut short can still match SB_USER_PATTERN. The Make targets that pass SB_USER on also export SB_ENV_FILE (a
# path only); direct script runs leave it unset and skip this check. Never prints either value.
require_sb_user_matches_env_file() {
  local line raw=""
  [[ -n "${SB_ENV_FILE:-}" && -f "$SB_ENV_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      SB_USER=*) raw="${line#SB_USER=}" ;;
    esac
  done <"$SB_ENV_FILE" || die "could not read $SB_ENV_FILE: check that you can read it"
  raw="${raw%$'\r'}"
  [[ "$raw" == "${SB_USER:-}" ]] \
    || die "SB_USER in $SB_ENV_FILE holds characters that make changes when it reads .env (#, \$, spaces or quotes), so the scripts got a different value: write it as SB_USER=<user>:<password> with only letters, digits and ._~+/=- in the password"
}

# notes_dir_arg [--local] -> the local notes folder for --local; nothing (meaning the VM) without an argument, after
# checking the VM settings. Any other argument dies with the usage. Use: local_dir="$(notes_dir_arg "$@")" || exit 1
notes_dir_arg() {
  case "${1:-}" in
    "") require_vm ;;
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

# notes_file_state LOCAL_DIR PATH -> present or absent for PATH (relative to the notes folder, without spaces) through
# in_notes_dir. Fails when the folder cannot be read.
notes_file_state() {
  in_notes_dir "$1" "$(exists_cmd "$2")" </dev/null
}

# sb_space_apply WHERE RERUN [RECREATE_CMD...] -> write the SilverBullet space files with sb-space.sh, in the local
# notes folder (WHERE local) or on the VM (WHERE vm). sb-space.sh writes only .gitignore while it reports "changed":
# Basic Memory reads .gitignore only at start, so RECREATE_CMD runs then (omit it while Basic Memory is stopped), the
# marker is removed only after it succeeded (a failed run asks again), and sb-space.sh writes the pages. Every failure
# dies with RERUN, the user's next step, for example "run 'make deploy' again".
sb_space_apply() {
  local mode="$1" rerun="$2" local_dir="" where state
  shift 2
  case "$mode" in
    local) local_dir="$SB_LOCAL_NOTES_DIR" where="$SB_LOCAL_NOTES_DIR" ;;
    vm) where="$BM_VM_HOST:$SB_REMOTE_NOTES_DIR" ;;
    *) die "sb_space_apply: WHERE must be local or vm (got '$mode')" ;;
  esac
  state="$("$REPO_DIR/scripts/sb-space.sh" ${local_dir:+--local})" \
    || die "could not write the SilverBullet space files in $where: fix the error above, then $rerun"
  [[ "$state" == changed ]] || return 0
  if (($#)); then
    "$@" || die "could not recreate Basic Memory to load the new notes .gitignore: $rerun"
  fi
  in_notes_dir "$local_dir" "rm -f $SB_GITIGNORE_PENDING" </dev/null \
    || die "could not remove $SB_GITIGNORE_PENDING in $where: $rerun"
  state="$("$REPO_DIR/scripts/sb-space.sh" ${local_dir:+--local})" \
    || die "could not write the SilverBullet pages in $where: fix the error above, then $rerun"
  [[ "$state" == unchanged ]] \
    || die "the notes .gitignore changed again while the pages waited, so they were not written: $rerun"
}
