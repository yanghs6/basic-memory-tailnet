#!/usr/bin/env bash
# Restore a backup made by `make backup` onto the VM, together with this repo's compose.yaml and the VM .env
# (image, config and data move as a set, so an older image never runs on data a newer one migrated).
# The archive is extracted into a staging dir and checked against its manifest before anything live is
# touched. Current data is moved aside, never deleted. Any failure after the stop puts the previous data,
# compose.yaml and .env back and restarts the container.
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

verify_checksum() {
  local archive="$1" expected actual
  expected="$(awk '{ print $1 }' "$archive.sha256")" || exit 1
  actual="$(sha256_of "$archive")" || exit 1
  [[ "$expected" == "$actual" ]] \
    || die "checksum mismatch for $archive (expected $expected, got $actual): the file is corrupt or was modified"
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
  if remote "if [ -e $COMPOSE_FILE ]; then cd $BM_REMOTE_APP_DIR && docker compose up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS; fi"; then
    log "rolled back: the previous data is live again"
  else
    log "WARNING: the container did not come back after rollback; run 'make status' and 'make logs'"
  fi
  exit "$exit_code"
}

# upload_vm_file TARGET PREV: keep a copy of TARGET at PREV, then read the new content from stdin.
upload_vm_file() {
  remote "mkdir -p $BM_REMOTE_APP_DIR && if [ -e $1 ]; then cp $1 $2; fi && cat > $1"
}

main() {
  local archive="${1:-}" actual expected
  [[ -n "$archive" ]] || die "usage: make restore BACKUP=backups/bm-<stamp>.tgz"
  [[ -f "$archive" ]] || die "backup not found: $archive"
  [[ -f "$archive.sha256" ]] || die "checksum file missing: $archive.sha256 (restore only archives made by 'make backup')"
  [[ -f "$archive.manifest" ]] || die "manifest missing: $archive.manifest (restore only archives made by 'make backup')"
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  verify_checksum "$archive"
  confirm "Replace $ROOT, $COMPOSE_FILE and $ENV_FILE on $BM_VM_HOST with $(basename "$archive") and this repo's compose.yaml? Current data moves to $PREV. Type 'yes': "

  trap rollback EXIT
  STOP_ATTEMPTED=1
  step "stop container"
  # A recreated VM has no compose.yaml yet, so there is nothing to stop.
  remote "if [ -e $COMPOSE_FILE ]; then cd $BM_REMOTE_APP_DIR && docker compose stop; fi" \
    || die "could not confirm the container stopped"

  step "extract into $STAGE"
  remote "sudo -n mkdir -p $STAGE && sudo -n tar -C $STAGE -xzf -" <"$archive" \
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

  step "start container"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "container did not become healthy with the restored data"
  remote "rm -f $COMPOSE_PREV $ENV_PREV" || log "WARNING: could not remove $COMPOSE_PREV and $ENV_PREV"
  log "restored $(basename "$archive"); previous data kept at $PREV"
}

main "$@"
