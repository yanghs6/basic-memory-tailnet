#!/usr/bin/env bash
# Restore a backup made by `make backup` onto the VM, together with this repo's compose.yaml and the VM .env
# (image, config and data move as a set, so an older image never runs on data a newer one migrated).
# The archive is extracted into a staging dir and checked against its manifest before anything live is
# touched. Current data is moved aside, never deleted. This repo's SilverBullet space files are written into the
# restored notes folder while the containers are stopped, so Basic Memory starts with the current notes .gitignore.
# Any failure after the stop puts the previous data, compose.yaml and .env back and restarts the container.
# Usage: restore.sh backups/bm-<stamp>.tgz   (asks the user to type yes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

ROOT="$BM_REMOTE_DATA_ROOT"
NAME="$(basename "$ROOT")"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STAGE="$ROOT.restore-$STAMP"
PREV="$ROOT.prev-$STAMP"
COMPOSE_FILE="$BM_REMOTE_APP_DIR/compose.yaml"
COMPOSE_PREV="$COMPOSE_FILE.prev-$STAMP"
ENV_FILE="$BM_REMOTE_APP_DIR/.env"
ENV_PREV="$ENV_FILE.prev-$STAMP"
STOP_ATTEMPTED=""
# Set when the VM had data before this restore; without it (a recreated VM) there is nothing to roll back to.
HAD_PREVIOUS_DATA=""

verify_checksum() {
  local archive="$1" expected actual
  expected="$(awk '{ print $1 }' "$archive.sha256")" || exit 1
  actual="$(sha256_of "$archive")" || exit 1
  [[ "$expected" == "$actual" ]] \
    || die "checksum mismatch for $archive (expected $expected, got $actual): the file is corrupt or was modified"
}

# check_archive_entries ARCHIVE: refuse entries that could write outside the staging dir when tar runs as root
# on the VM: absolute paths, '..' components, and anything but regular files and directories (symlinks, hard
# links, devices, fifos). The manifest covers regular files only, so it cannot catch these. `tar -tv` prints
# the entry type as the first character of the mode column on GNU tar and bsdtar alike.
check_archive_entries() {
  local archive="$1" names types
  names="$(tar -tzf "$archive")" || die "could not list the entries of $archive: the archive is unreadable"
  types="$(tar -tzvf "$archive" | cut -c1)" || die "could not list the entries of $archive: the archive is unreadable"
  if grep -qv '^[-d]$' <<<"$types"; then
    die "unsafe archive $archive: it holds an entry that is not a regular file or directory (symlink, hard link or device); restore only archives made by 'make backup'"
  fi
  if grep -qE '^/|(^|/)\.\.(/|$)' <<<"$names"; then
    die "unsafe archive $archive: it holds an absolute path or a '..' component; restore only archives made by 'make backup'"
  fi
}

confirm() {
  local answer=""
  read -r -p "$1" answer || true
  [[ "$answer" == yes ]] || die "aborted: you must type 'yes' to restore"
}

# shellcheck disable=SC2317  # invoked via trap
rollback() {
  local exit_code=$?
  if [[ "$exit_code" -eq 0 || -z "$STOP_ATTEMPTED" ]]; then
    exit "$exit_code"
  fi
  log "restore failed; rolling back"
  remote "if [ -e $PREV ]; then if [ -e $ROOT ]; then sudo -n mv $ROOT $ROOT.failed-$STAMP; fi; sudo -n mv $PREV $ROOT; fi; if [ -e $COMPOSE_PREV ]; then mv $COMPOSE_PREV $COMPOSE_FILE; fi; if [ -e $ENV_PREV ]; then mv $ENV_PREV $ENV_FILE; fi; sudo -n rm -rf $STAGE" \
    || log "WARNING: rollback could not restore the directories; check $ROOT, $PREV, $COMPOSE_FILE and $ENV_FILE on the VM by hand"
  if [[ -z "$HAD_PREVIOUS_DATA" ]]; then
    report_no_previous_data
    exit "$exit_code"
  fi
  # --force-recreate: with an unchanged compose.yaml and .env, plain `up -d` keeps the running container, whose
  # bind mount still points at the restored data now renamed to .failed-*.
  if remote "if [ -e $COMPOSE_FILE ]; then cd $BM_REMOTE_APP_DIR && docker compose up -d --force-recreate --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS; fi"; then
    log "rolled back: the previous data is live again"
  else
    log "WARNING: the container did not come back after rollback; run 'make status' and 'make logs'"
  fi
  exit "$exit_code"
}

# report_no_previous_data: on a recreated VM there is no previous data to bring back, so say what the failed
# restore left behind and what to do next instead of claiming a rollback. The container is not restarted.
# shellcheck disable=SC2317  # invoked from the rollback trap
report_no_previous_data() {
  local state where
  state="$(remote "if [ -e $ROOT ]; then echo present; fi")" || state=unknown
  case "$state" in
    present) where="the restored data is now at $ROOT" ;;
    "") where="$ROOT does not exist (the restored copy was removed)" ;;
    *) where="the state of $ROOT is unknown (the VM did not answer)" ;;
  esac
  log "nothing rolled back: $BM_VM_HOST had no data before this restore; $where. Next: run 'make status' and 'make logs', fix the cause, then rerun 'make restore BACKUP=<archive>'"
}

# upload_vm_file TARGET PREV: keep a copy of TARGET at PREV, then replace TARGET with stdin. Both writes go to
# a temp name first and are moved into place only when complete, so a partial copy never replaces a good file
# or becomes the rollback source; on failure the temp files are removed. Files are written owner-only, because
# the VM .env holds SB_USER.
upload_vm_file() {
  local target="$1" prev="$2" tmp="$1.upload-$STAMP"
  remote "umask 077 && mkdir -p $BM_REMOTE_APP_DIR && { if [ -e $target ]; then cp $target $prev.partial && mv $prev.partial $prev; fi && cat > $tmp && mv $tmp $target; } || { rm -f $tmp $prev.partial; exit 1; }"
}

# write_space_files ARCHIVE: write the SilverBullet space files into the restored notes folder while Basic Memory is
# stopped. It reads the notes .gitignore when it starts, so a changed .gitignore needs no recreate here: the marker is
# removed at once and sb-space.sh runs again to write the pages. A failure here rolls back like the other steps.
write_space_files() {
  local archive="$1" state
  state="$("$SCRIPT_DIR/sb-space.sh")" \
    || die "could not write the SilverBullet space files into the restored notes folder: fix the error above, then rerun 'make restore BACKUP=$archive'"
  [[ "$state" == changed ]] || return 0
  in_notes_dir "" "rm -f $SB_GITIGNORE_PENDING" </dev/null \
    || die "could not remove $SB_GITIGNORE_PENDING from the restored notes folder: rerun 'make restore BACKUP=$archive'"
  state="$("$SCRIPT_DIR/sb-space.sh")" \
    || die "could not write the SilverBullet pages into the restored notes folder: fix the error above, then rerun 'make restore BACKUP=$archive'"
  [[ "$state" == unchanged ]] \
    || die "the notes .gitignore changed again during the restore, so the SilverBullet pages were not written: rerun 'make restore BACKUP=$archive'"
}

main() {
  local archive="${1:-}" actual expected present
  [[ -n "$archive" ]] || die "usage: make restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz"
  [[ -f "$archive" ]] || die "backup not found: $archive (archives from 'make backup' are in <main checkout>/backups/; pass the full path if you are in another checkout)"
  [[ -f "$archive.sha256" ]] || die "checksum file missing: $archive.sha256 (restore only archives made by 'make backup')"
  [[ -f "$archive.manifest" ]] || die "manifest missing: $archive.manifest (restore only archives made by 'make backup')"
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  require_sb_user
  verify_checksum "$archive"
  check_archive_entries "$archive"
  confirm "Replace $ROOT, $COMPOSE_FILE and $ENV_FILE on $BM_VM_HOST with $(basename "$archive") and this repo's compose.yaml? Current data moves to $PREV. Type 'yes': "

  present="$(remote "if [ -e $ROOT ]; then echo present; fi")" \
    || die "could not reach $BM_VM_HOST: $(access_hint)"
  if [[ "$present" == present ]]; then
    HAD_PREVIOUS_DATA=1
  fi

  trap rollback EXIT
  STOP_ATTEMPTED=1
  step "stop container"
  # A recreated VM has no compose.yaml yet, so there is nothing to stop.
  remote "if [ -e $COMPOSE_FILE ]; then cd $BM_REMOTE_APP_DIR && docker compose stop; fi" \
    || die "could not confirm the container stopped"

  step "extract into $STAGE"
  remote "sudo -n mkdir -p $STAGE && sudo -n tar --no-same-owner --no-same-permissions -C $STAGE -xzf -" <"$archive" \
    || die "extract failed; current data was not touched"

  step "check extracted files against $(basename "$archive").manifest"
  actual="$(remote "$(manifest_cmd "$STAGE/$NAME")")" \
    || die "could not list the extracted files; current data was not touched"
  expected="$(cat "$archive.manifest")" || exit 1
  [[ "$actual" == "$expected" ]] || die "extracted files do not match the backup manifest; current data was not touched"
  remote "sudo -n chown -R $BM_CONTAINER_UID:$BM_CONTAINER_UID $STAGE/$NAME" \
    || die "could not fix ownership of the extracted data; current data was not touched"

  step "apply this repo's compose.yaml and the VM .env (previous copies kept until the restore succeeds)"
  upload_vm_file "$COMPOSE_FILE" "$COMPOSE_PREV" <"$REPO_DIR/compose.yaml" || die "could not upload compose.yaml"
  vm_env | upload_vm_file "$ENV_FILE" "$ENV_PREV" || die "could not write $ENV_FILE on the VM"

  step "swap in the restored data (previous data -> $PREV)"
  remote "if [ -e $ROOT ]; then sudo -n mv $ROOT $PREV; fi" || die "could not move the current data aside"
  remote "sudo -n mv $STAGE/$NAME $ROOT && sudo -n rmdir $STAGE" || die "could not swap the restored data into place"

  step "write the SilverBullet space files while Basic Memory is stopped"
  write_space_files "$archive"

  step "start container"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "container did not become healthy with the restored data"
  remote "rm -f $COMPOSE_PREV $ENV_PREV" || log "WARNING: could not remove $COMPOSE_PREV and $ENV_PREV"
  log "restored $(basename "$archive"); previous data kept at $PREV"
}

main "$@"
