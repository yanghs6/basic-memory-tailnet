#!/usr/bin/env bash
# Print the newest bm-*.tgz in the main checkout's backups/, whether its .sha256 matches, its .manifest exists and its
# entries are only regular files and directories with relative paths (archive_entry_problem), and whether
# 'make restore' would take it. Reads only the checksum file's first field, the archive bytes to hash them and the
# archive's entry list, but never prints an entry name (they hold note titles) or archive or manifest content, and
# changes nothing. A sandboxed worktree session runs this instead of listing the main checkout's backups/.
# Usage: make backup-latest   (BACKUP_DIR=<dir> reads another directory)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly BACKUPS_DIRNAME="backups"

# resolve_backup_dir -> the backup directory: BACKUP_DIR from the environment, else backups/ in the MAIN checkout.
resolve_backup_dir() {
  local root
  if [[ -n "${BACKUP_DIR:-}" ]]; then
    printf '%s\n' "$BACKUP_DIR"
    return 0
  fi
  root="$(main_checkout_root)" \
    || die "cannot find the main checkout (is this a git checkout?): set BACKUP_DIR=<dir> and run 'make backup-latest' again"
  printf '%s/%s\n' "$root" "$BACKUPS_DIRNAME"
}

# newest_archive DIR -> path of the newest bm-*.tgz in DIR by its UTC stamp (the name sorts in time order; mtime does not survive a copy); fails when there is none.
newest_archive() {
  local file newest=""
  for file in "$1"/bm-*.tgz; do
    [[ -f "$file" ]] || continue
    if [[ -z "$newest" || "$file" > "$newest" ]]; then
      newest="$file"
    fi
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

# checksum_state ARCHIVE -> match, MISMATCH or missing, comparing ARCHIVE.sha256's first field with the archive's digest.
checksum_state() {
  local expected
  if [[ ! -f "$1.sha256" ]]; then
    printf 'missing\n'
    return 0
  fi
  expected="$(awk 'NR == 1 { print $1 }' "$1.sha256")" || exit 1
  if [[ "$expected" == "$(sha256_of "$1")" ]]; then
    printf 'match\n'
  else
    printf 'MISMATCH\n'
  fi
}

# entries_state ARCHIVE -> safe, UNSAFE (<reason>) or unreadable (archive_entry_problem); never an entry name.
entries_state() {
  local problem
  if ! problem="$(archive_entry_problem "$1")"; then
    printf 'unreadable\n'
  elif [[ -z "$problem" ]]; then
    printf 'safe\n'
  else
    printf 'UNSAFE (%s)\n' "$problem"
  fi
}

main() {
  local dir archive checksum manifest entries
  dir="$(resolve_backup_dir)" || exit 1
  archive="$(newest_archive "$dir")" \
    || die "no bm-*.tgz in $dir: run 'make backup' (ask the user first) or restore from another copy"
  checksum="$(checksum_state "$archive")" || exit 1
  manifest="missing"
  [[ ! -f "$archive.manifest" ]] || manifest="present"
  entries="$(entries_state "$archive")" || exit 1
  printf 'archive: %s\n' "$archive"
  printf 'checksum: %s\n' "$checksum"
  printf 'manifest: %s\n' "$manifest"
  printf 'entries: %s\n' "$entries"
  if [[ "$checksum" == "match" && "$manifest" == "present" && "$entries" == "safe" ]]; then
    printf 'restorable: yes (make restore BACKUP=%s)\n' "$archive"
  else
    printf 'not restorable: make restore refuses an archive without a matching checksum and a manifest, or with entries other than regular files and directories with relative paths\n'
  fi
}

main "$@"
