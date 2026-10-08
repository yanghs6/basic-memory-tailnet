#!/usr/bin/env bash
# Download a consistent backup of the VM data root into backups/: archive, .sha256 and a .manifest of every
# data file. The container is stopped briefly so SQLite files are not copied mid-write; the restart is
# registered before the stop, so it runs even if the stop's reply is lost.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly BACKUP_DIR="${BACKUP_DIR:-$REPO_DIR/backups}"
ARCHIVE=""

# shellcheck disable=SC2317  # invoked via trap
restart_container() {
  local exit_code=$?
  if [[ -n "$ARCHIVE" ]]; then
    rm -f "$ARCHIVE.partial" "$ARCHIVE.manifest.partial"
  fi
  step "restart container"
  if ! remote_compose "start"; then
    log "WARNING: container restart failed; run 'make deploy' to bring it back"
    exit_code=1
  fi
  exit "$exit_code"
}

main() {
  local parent name digest
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-$(date -u +%Y%m%dT%H%M%SZ).tgz"
  parent="$(dirname "$BM_REMOTE_DATA_ROOT")"
  name="$(basename "$BM_REMOTE_DATA_ROOT")"

  trap restart_container EXIT
  step "stop container (a brief stop keeps SQLite consistent)"
  remote_compose "stop" || die "could not confirm the container stopped; restarting it and writing no backup"

  step "record a checksum manifest of every data file"
  remote "cd $BM_REMOTE_DATA_ROOT && sudo -n find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2" \
    >"$ARCHIVE.manifest.partial" || die "could not build the data manifest; no backup was written"

  step "stream $BM_REMOTE_DATA_ROOT from $BM_VM_HOST"
  remote "sudo -n tar -C $parent -czf - $name" >"$ARCHIVE.partial" \
    || die "backup stream failed; no archive was written"
  digest="$(sha256_of "$ARCHIVE.partial")" || exit 1
  mv "$ARCHIVE.manifest.partial" "$ARCHIVE.manifest"
  mv "$ARCHIVE.partial" "$ARCHIVE"
  printf '%s  %s\n' "$digest" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
  log "backup saved: $ARCHIVE (+ .sha256, .manifest)"
}

main "$@"
