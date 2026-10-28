#!/usr/bin/env bash
# Print the newest bm-*.tgz in the main checkout's backups/ and whether its .sha256 matches and its .manifest exists.
# Reads only the checksum file's first field and the archive bytes to hash them; never prints archive or manifest
# content and changes nothing. A sandboxed worktree session runs this instead of listing the main checkout's backups/.
# Usage: make backup-latest   (BACKUP_DIR=<dir> reads another directory)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

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

main() {
  local dir archive checksum manifest
  dir="$(resolve_backup_dir)" || exit 1
  archive="$(newest_archive "$dir")" \
    || die "no bm-*.tgz in $dir: run 'make backup' (ask the user first) or restore from another copy"
  checksum="$(checksum_state "$archive")" || exit 1
  manifest="missing"
  [[ ! -f "$archive.manifest" ]] || manifest="present"
  printf 'archive: %s\n' "$archive"
  printf 'checksum: %s\n' "$checksum"
  printf 'manifest: %s\n' "$manifest"
  if [[ "$checksum" == "match" && "$manifest" == "present" ]]; then
    printf 'restorable: yes (make restore BACKUP=%s)\n' "$archive"
  else
    printf 'not restorable: make restore refuses an archive without a matching checksum and a manifest\n'
  fi
}

main "$@"
