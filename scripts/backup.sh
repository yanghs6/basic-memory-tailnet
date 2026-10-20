#!/usr/bin/env bash
# Download a consistent backup of the VM data root into the main checkout's backups/: archive, .sha256 and a .manifest of every
# data file. The container is stopped briefly so SQLite files are not copied mid-write; the restart is
# registered before the stop, so it runs even if the stop's reply is lost.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly BACKUPS_DIRNAME="backups"
ARCHIVE=""
IS_RESERVED=0
IS_FINALIZED=0
# How many of this run's files (in finalize order) were renamed into place; cleanup removes only those.
RENAMED_COUNT=0

# resolve_backup_dir -> absolute backup directory (created). BACKUP_DIR from the environment wins; otherwise
# backups/ in the MAIN checkout, so an archive made in a worktree survives 'git worktree remove'.
resolve_backup_dir() {
  local dir="${BACKUP_DIR:-}" root
  if [[ -z "$dir" ]]; then
    root="$(main_checkout_root)" \
      || die "cannot find the main checkout (is this a git checkout?): set BACKUP_DIR=<dir> and run 'make backup' again"
    dir="$root/$BACKUPS_DIRNAME"
  fi
  mkdir -p "$dir" || die "could not create the backup directory $dir"
  (cd "$dir" && pwd)
}

# reserve_archive -> claim $ARCHIVE for this run before anything can clean up; dies if the name is taken.
reserve_archive() {
  local file
  # noclobber makes the create exclusive, so two runs in the same second cannot both own this name.
  (set -C && : >"$ARCHIVE$PARTIAL_SUFFIX") 2>/dev/null \
    || die "another backup is writing $(basename "$ARCHIVE") right now; wait for it, then run 'make backup' again"
  # Check the final names only after the reservation: another run's finalize renames its .partial to the final
  # name atomically, so a name finished by another run is always visible here. Checking first left a window.
  for file in "$ARCHIVE" "$ARCHIVE.manifest" "$ARCHIVE.sha256"; do
    if [[ -e "$file" ]]; then
      rm -f "$ARCHIVE$PARTIAL_SUFFIX" || log "WARNING: could not remove $ARCHIVE$PARTIAL_SUFFIX; delete it by hand"
      die "a backup named $(basename "$ARCHIVE") already exists; wait a second and run 'make backup' again"
    fi
  done
  IS_RESERVED=1
}

# discard_unfinished_run -> remove only this run's partial files and the final files it renamed.
discard_unfinished_run() {
  local file index=0
  for file in "$ARCHIVE" "$ARCHIVE.manifest" "$ARCHIVE.sha256"; do
    rm -f "$file$PARTIAL_SUFFIX" || log "WARNING: could not remove $file$PARTIAL_SUFFIX; delete it by hand"
    if ((index < RENAMED_COUNT)); then
      rm -f "$file" || log "WARNING: could not remove $file; delete it by hand"
    fi
    index=$((index + 1))
  done
}

# finalize_run -> rename the three complete partial files to their final names, then mark the run complete.
finalize_run() {
  local file
  for file in "$ARCHIVE" "$ARCHIVE.manifest" "$ARCHIVE.sha256"; do
    mv "$file$PARTIAL_SUFFIX" "$file" || die "could not finalize $file; no backup was kept"
    RENAMED_COUNT=$((RENAMED_COUNT + 1))
  done
  IS_FINALIZED=1
}

# shellcheck disable=SC2317  # invoked via trap
restart_container() {
  local exit_code=$?
  if [[ "$IS_RESERVED" -eq 1 && "$IS_FINALIZED" -eq 0 ]]; then
    discard_unfinished_run
  fi
  step "restart container"
  if ! remote_compose "start"; then
    log "WARNING: container restart failed; run 'make deploy' to bring it back"
    exit_code=1
  fi
  exit "$exit_code"
}

main() {
  local parent name digest stamp
  require_vm
  BACKUP_DIR="$(resolve_backup_dir)" || exit 1
  stamp="$(utc_stamp)" || exit 1
  ARCHIVE="$BACKUP_DIR/bm-$stamp.tgz"
  parent="$(dirname "$BM_REMOTE_DATA_ROOT")"
  name="$(basename "$BM_REMOTE_DATA_ROOT")"
  # Reserve the name before the trap and the stop: a taken name stops here with the container untouched.
  reserve_archive

  trap restart_container EXIT
  step "stop container (a brief stop keeps SQLite consistent)"
  remote_compose "stop" || die "could not confirm the container stopped: $(access_hint); restarting it and writing no backup"

  step "record a checksum manifest of every data file"
  remote "$(manifest_cmd "$BM_REMOTE_DATA_ROOT")" >"$ARCHIVE.manifest$PARTIAL_SUFFIX" \
    || die "could not build the data manifest; no backup was written"

  step "stream $BM_REMOTE_DATA_ROOT from $BM_VM_HOST"
  remote "sudo -n tar -C $parent --exclude=$name/$BM_MODEL_CACHE_REL_PATH -czf - $name" >"$ARCHIVE$PARTIAL_SUFFIX" \
    || die "backup stream failed; no archive was written"
  digest="$(sha256_of "$ARCHIVE$PARTIAL_SUFFIX")" || exit 1
  printf '%s  %s\n' "$digest" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256$PARTIAL_SUFFIX" \
    || die "could not write the checksum; no backup was kept"
  finalize_run
  log "backup saved: $ARCHIVE (+ .sha256, .manifest)"
}

main "$@"
