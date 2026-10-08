#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker sudo
  use_vm_env
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  BACKUP="$REPO_DIR/scripts/backup.sh"
  RESTORE="$REPO_DIR/scripts/restore.sh"
}

# make_archive NOTE -> creates $ARCHIVE (+ .sha256, .manifest) holding basic-memory/knowledge/restored.md
make_archive() {
  local src="$BATS_TEST_TMPDIR/src"
  mkdir -p "$src/basic-memory/knowledge" "$src/basic-memory/config"
  echo "$1" >"$src/basic-memory/knowledge/restored.md"
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-20261007T000000Z.tgz"
  tar -C "$src" -czf "$ARCHIVE" basic-memory
  printf '%s  %s\n' "$(sha256sum "$ARCHIVE" | awk '{ print $1 }')" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
  (cd "$src/basic-memory" && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2) >"$ARCHIVE.manifest"
}

restore_with_answer() {
  run bash -c 'printf "%s\n" "$1" | "$0" "$2"' "$RESTORE" "$1" "$ARCHIVE"
}

# --- backup ---

@test "backup stores a checksummed archive of the data root and restarts the container" {
  run "$BACKUP"
  assert_success
  local archive
  archive="$(ls "$BACKUP_DIR"/bm-*.tgz)"
  run tar -tzf "$archive"
  assert_line "basic-memory/knowledge/a.md"
  run cat "$archive.sha256"
  assert_output "$(sha256sum "$archive" | awk '{ print $1 }')  $(basename "$archive")"
  run cat "$archive.manifest"
  assert_output "$(sha256sum "$BM_REMOTE_DATA_ROOT/knowledge/a.md" | awk '{ print $1 }')  ./knowledge/a.md"
  run grep -E '^docker compose (stop|start)' "$STUB_LOG"
  assert_line --index 0 "docker compose stop"
  assert_line --index 1 "docker compose start"
}

@test "backup leaves no partial archive and still restarts the container when streaming fails" {
  export SSH_STUB_FAIL_MATCH="tar -C"
  run "$BACKUP"
  assert_failure
  assert_output --partial "backup stream failed"
  run ls -A "$BACKUP_DIR"
  assert_output ""
  run grep -F 'compose start' "$STUB_LOG"
  assert_success
}

@test "backup still restarts the container when the stop cannot be confirmed" {
  export SSH_STUB_FAIL_MATCH="compose stop"
  run "$BACKUP"
  assert_failure
  assert_output --partial "could not confirm the container stopped"
  run grep -F 'docker compose start' "$STUB_LOG"
  assert_success
  run ls -A "$BACKUP_DIR"
  assert_output ""
}

# --- restore ---

@test "restore replaces the data, keeps the previous copy and fixes ownership" {
  make_archive "from backup"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "from backup"
  run bash -c 'cat "$0".prev-*/knowledge/a.md' "$BM_REMOTE_DATA_ROOT"
  assert_output "original"
  run stat -c '%u' "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "1000"
  run grep -F 'compose up -d --wait --wait-timeout 180' "$STUB_LOG"
  assert_success
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run bash -c 'ls -d "$0".restore-* "$1"/compose.yaml.prev-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_APP_DIR"
  assert_failure
}

@test "restore works on a fresh VM without existing data" {
  make_archive "fresh"
  rm -r "$BM_REMOTE_DATA_ROOT"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "fresh"
  run bash -c 'ls -d "$0".prev-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT"
  assert_failure
}

@test "restore aborts without touching the VM unless the user types yes" {
  make_archive "x"
  restore_with_answer no
  assert_failure
  assert_output --partial "aborted: you must type 'yes'"
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}

@test "restore rejects an archive whose checksum does not match" {
  make_archive "x"
  echo "0000  $(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
  restore_with_answer yes
  assert_failure
  assert_output --partial "checksum mismatch"
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
}

@test "restore requires an existing archive with its checksum and manifest files" {
  run "$RESTORE" "$BACKUP_DIR/missing.tgz"
  assert_failure
  assert_output --partial "backup not found"

  make_archive "x"
  rm "$ARCHIVE.sha256"
  run "$RESTORE" "$ARCHIVE"
  assert_failure
  assert_output --partial "checksum file missing"

  make_archive "x"
  rm "$ARCHIVE.manifest"
  run "$RESTORE" "$ARCHIVE"
  assert_failure
  assert_output --partial "manifest missing"
}

@test "restore prints usage without an argument" {
  run "$RESTORE"
  assert_failure
  assert_output --partial "usage: make restore BACKUP=backups/bm-<stamp>.tgz"
}

@test "restore leaves current data live and restarts when extraction fails" {
  make_archive "x"
  export SSH_STUB_FAIL_MATCH="-xzf"
  restore_with_answer yes
  assert_failure
  assert_output --partial "extract failed; current data was not touched"
  assert_output --partial "rolled back: the previous data is live again"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  run bash -c 'ls -d "$0".prev-* "$0".restore-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT"
  assert_failure
}

@test "restore refuses extracted files that do not match the manifest" {
  make_archive "x"
  echo "0000  ./knowledge/missing.md" >>"$ARCHIVE.manifest"
  restore_with_answer yes
  assert_failure
  assert_output --partial "extracted files do not match the backup manifest"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}

@test "restore rolls back data and compose when the restored service is unhealthy" {
  make_archive "bad"
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  echo "PREVIOUS=env" >"$BM_REMOTE_APP_DIR/.env"
  export DOCKER_STUB_FAIL_MATCH="up -d"
  restore_with_answer yes
  assert_failure
  assert_output --partial "container did not become healthy with the restored data"
  assert_output --partial "restore failed; rolling back"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  run cat "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_output "previous compose"
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_output "PREVIOUS=env"
  run bash -c 'cat "$0".failed-*/knowledge/restored.md' "$BM_REMOTE_DATA_ROOT"
  assert_output "bad"
}

@test "restore writes the VM .env and succeeds on a recreated VM with no data, compose or .env" {
  make_archive "fresh"
  rm -r "$BM_REMOTE_DATA_ROOT"
  rm -f "$BM_REMOTE_APP_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/.env"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  run bash -c 'ls -d "$0".prev-* "$1"/.env.prev-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_APP_DIR"
  assert_failure
}

@test "restore rolls back data, compose.yaml and .env when the swap fails" {
  make_archive "bad"
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  echo "PREVIOUS=env" >"$BM_REMOTE_APP_DIR/.env"
  export SSH_STUB_FAIL_MATCH="rmdir"
  restore_with_answer yes
  assert_failure
  assert_output --partial "could not swap the restored data into place"
  assert_output --partial "restore failed; rolling back"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  run cat "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_output "previous compose"
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_output "PREVIOUS=env"
}
