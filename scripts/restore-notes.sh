#!/usr/bin/env bash
# Restore a backup made by `make backup` onto the VM, together with this repo's compose.yaml and the VM .env
# (image, config and data move as a set, so an older image never runs on data a newer one migrated).
# The archive is extracted into a staging dir and checked against its manifest before anything live is
# touched. Current data is moved aside, never deleted. This repo's SilverBullet space files are written into the
# restored notes folder while the containers are stopped, so Basic Memory starts with the current notes .gitignore.
# Any failure or Ctrl-C after the stop, until the restored data is healthy, puts the previous data, compose.yaml and .env
# back and restarts the container.
# With BM_WEB=on only Basic Memory and SilverBullet decide success (and the rollback); the web connector starts after
# them and only warns when it is not healthy.
# Usage: make restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz   (asks the user to type yes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

ROOT="$BM_REMOTE_DATA_ROOT"
NAME="$(basename "$ROOT")"
STAMP="$(utc_stamp)" || exit 1
STAGE="$ROOT.restore-$STAMP"
PREV="$ROOT.prev-$STAMP"
COMPOSE_FILE="$BM_REMOTE_APP_DIR/compose.yaml"
COMPOSE_PREV="$COMPOSE_FILE.prev-$STAMP"
ENV_FILE="$BM_REMOTE_APP_DIR/.env"
ENV_PREV="$ENV_FILE.prev-$STAMP"
# Where this run backs up the live gateway files (BM_WEB=on); unique to the run and outside the data root and backups/.
GATEWAY_BACKUP_PATH="$BM_REMOTE_APP_DIR/gateway.backup-$STAMP"
STOP_ATTEMPTED=""
# Set when the VM had data before this restore; without it (a recreated VM) there is nothing to roll back to.
HAD_PREVIOUS_DATA=""
# The status a shell reports for Ctrl-C (128 + SIGINT).
readonly INTERRUPTED_EXIT_CODE=130
# The services the restored notes need.
readonly NOTE_SERVICES="basic-memory silverbullet"
# The services whose health decides the restore and its rollback: empty (every service, as before the web connector)
# with BM_WEB off; NOTE_SERVICES with BM_WEB=on, so a web connector service that does not come up never fails the
# restore or rolls the notes back (start_web_services starts the rest). Set in main.
WAIT_SERVICES=""

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
  if [[ -n "$GATEWAY_BACKUP_DIR" ]]; then
    remote "$(gateway_rollback_cmd "$GATEWAY_BACKUP_DIR")" \
      || log "WARNING: rollback could not restore the gateway files; they are backed up in $GATEWAY_BACKUP_DIR on the VM"
  fi
  if [[ -z "$HAD_PREVIOUS_DATA" ]]; then
    report_no_previous_data
    exit "$exit_code"
  fi
  # --force-recreate: with an unchanged compose.yaml and .env, plain `up -d` keeps the running container, whose
  # bind mount still points at the restored data now renamed to .failed-*.
  if remote_compose --if-deployed "up -d --force-recreate --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS${WAIT_SERVICES:+ $WAIT_SERVICES}"; then
    log "rolled back: the previous data is live again"
    start_web_services --if-deployed
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
  state="$(remote_exists "$ROOT")" || state=unknown
  case "$state" in
    present) where="the restored data is now at $ROOT" ;;
    absent) where="$ROOT does not exist (the restored copy was removed)" ;;
    *) where="the state of $ROOT is unknown (the VM did not answer)" ;;
  esac
  log "nothing rolled back: $BM_VM_HOST had no data before this restore; $where. Next: run 'make status' and 'make logs', fix the cause, then rerun 'make restore BACKUP=<archive>'"
}

# start_web_services [--if-deployed]: with BM_WEB=on, once the note services are healthy, start the rest (the web
# connector) with a plain `up -d`, then wait up to HEALTH_TIMEOUT_SECONDS once for every service to be healthy. It only
# warns: the notes are restored whether or not the web connector comes up. The wait names no service, so after a
# rollback to an .env without the web profiles it starts nothing new. Does nothing with BM_WEB off.
# shellcheck disable=SC2317  # also invoked from the rollback trap
start_web_services() {
  local deployed="${1:-}"
  if [[ -n "$WAIT_SERVICES" ]]; then
    step "start the web connector services (waits up to ${HEALTH_TIMEOUT_SECONDS}s; the notes do not depend on them)"
    if ! { remote_compose ${deployed:+"$deployed"} "up -d" \
      && remote_compose ${deployed:+"$deployed"} "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS"; }; then
      log "WARNING: the web connector services are not healthy; the notes are not affected: run 'make status' and 'make logs'"
    fi
  fi
}

# upload_vm_file TARGET PREV: keep a copy of TARGET at PREV, then replace TARGET with stdin. Both writes go to
# a temp name first and are moved into place only when complete, so a partial copy never replaces a good file
# or becomes the rollback source; on failure the temp files are removed. Files are written owner-only, because
# the VM .env holds SB_USER.
upload_vm_file() {
  local target="$1" prev="$2" tmp="$1.upload-$STAMP"
  remote "umask 077 && mkdir -p $BM_REMOTE_APP_DIR && { if [ -e $target ]; then cp $target $prev.partial && mv $prev.partial $prev; fi && cat > $tmp && mv $tmp $target; } || { rm -f $tmp $prev.partial; exit 1; }"
}

main() {
  local archive="${1:-}" actual expected present web
  [[ -n "$archive" ]] || die "usage: make restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz"
  [[ -f "$archive" ]] || die "backup not found: $archive (archives from 'make backup' are in <main checkout>/backups/; pass the full path if you are in another checkout)"
  [[ -f "$archive.sha256" ]] || die "checksum file missing: $archive.sha256 (restore only archives made by 'make backup')"
  [[ -f "$archive.manifest" ]] || die "manifest missing: $archive.manifest (restore only archives made by 'make backup')"
  require_vm
  require_sb_user
  require_web_settings
  web="$(web_mode)" || exit 1
  if [[ "$web" == on ]]; then
    WAIT_SERVICES="$NOTE_SERVICES"
  fi
  verify_checksum "$archive"
  check_archive_entries "$archive"
  confirm "Replace $ROOT, $COMPOSE_FILE and $ENV_FILE on $BM_VM_HOST with $(basename "$archive") and this repo's compose.yaml? Current data moves to $PREV. Type 'yes': "

  present="$(remote_exists "$ROOT")" \
    || die "could not reach $BM_VM_HOST: $(access_hint)"
  if [[ "$present" == present ]]; then
    HAD_PREVIOUS_DATA=1
  fi

  trap rollback EXIT
  # Ctrl-C exits through the rollback with a failure status: without this trap bash 5 runs the EXIT trap with $? = 0
  # after the interrupted ssh dies, and the rollback takes that for success (bash 3.2 passes 130).
  trap 'exit $INTERRUPTED_EXIT_CODE' INT
  STOP_ATTEMPTED=1
  step "stop container"
  # A recreated VM has no compose.yaml yet, so there is nothing to stop.
  remote_compose --if-deployed stop \
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
  backup_gateway_files "$GATEWAY_BACKUP_PATH"
  upload_gateway_files

  step "swap in the restored data (previous data -> $PREV)"
  remote "if [ -e $ROOT ]; then sudo -n mv $ROOT $PREV; fi" || die "could not move the current data aside"
  remote "sudo -n mv $STAGE/$NAME $ROOT && sudo -n rmdir $STAGE" || die "could not swap the restored data into place"

  # Basic Memory is stopped and reads the notes .gitignore when it starts, so a changed .gitignore needs no recreate.
  # A failure here rolls back like the other steps.
  step "write the SilverBullet space files while Basic Memory is stopped"
  sb_space_apply vm "rerun 'make restore BACKUP=$archive'"

  step "start container"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS${WAIT_SERVICES:+ $WAIT_SERVICES}" \
    || die "container did not become healthy with the restored data"
  # The notes are restored: nothing after this rolls them back, neither an interrupted removal of the backups below
  # (it only leaves them on the VM) nor an interrupted wait for the web connector.
  trap - EXIT
  remote "rm -f $COMPOSE_PREV $ENV_PREV" || log "WARNING: could not remove $COMPOSE_PREV and $ENV_PREV"
  # The gateway backup only serves this run's rollback; the restored data is kept in $PREV, the gateway files are in the repo.
  if [[ -n "$GATEWAY_BACKUP_DIR" ]]; then
    remote "rm -rf $GATEWAY_BACKUP_DIR" || log "WARNING: could not remove $GATEWAY_BACKUP_DIR"
  fi
  log "restored $(basename "$archive"); previous data kept at $PREV"
  start_web_services
}

main "$@"
