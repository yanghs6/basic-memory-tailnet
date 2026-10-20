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
  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC/basic-memory/knowledge" "$SRC/basic-memory/config"
  echo "$1" >"$SRC/basic-memory/knowledge/restored.md"
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-20261007T000000Z.tgz"
  pack_archive basic-memory
  local_manifest "$SRC/basic-memory" >"$ARCHIVE.manifest"
}

# pack_archive TAR_ARGS... -> rebuild $ARCHIVE from $SRC with a valid .sha256 (the manifest is left as is).
pack_archive() {
  tar -C "$SRC" -czf "$ARCHIVE" "$@"
  printf '%s  %s\n' "$(sha256sum "$ARCHIVE" | awk '{ print $1 }')" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
}

# local_manifest DIR -> the manifest of DIR, built by the same command backup.sh and restore.sh run on the VM.
local_manifest() {
  bash -c "$(. "$REPO_DIR/scripts/lib/vm.sh" && manifest_cmd "$1")"
}

# fail_command NAME -> put a NAME first on PATH that prints an error and exits 1.
fail_command() {
  mkdir -p "$BATS_TEST_TMPDIR/failbin"
  printf '#!/usr/bin/env bash\necho "%s: simulated failure" >&2\nexit 1\n' "$1" >"$BATS_TEST_TMPDIR/failbin/$1"
  chmod +x "$BATS_TEST_TMPDIR/failbin/$1"
  export PATH="$BATS_TEST_TMPDIR/failbin:$PATH"
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
  run ls "$BACKUP_DIR"
  refute_output --partial ".partial"
  assert_equal "${#lines[@]}" 3
  run grep -E '^docker compose (stop|start)' "$STUB_LOG"
  assert_line --index 0 "docker compose stop"
  assert_line --index 1 "docker compose start"
}

# add_model_cache -> a HuggingFace-style cache in the fake data root: a blob plus a relative symlink to it.
add_model_cache() {
  local cache="$BM_REMOTE_DATA_ROOT/config/fastembed_cache"
  mkdir -p "$cache/blobs" "$cache/snapshots/rev"
  echo "model" >"$cache/blobs/hash1"
  ln -s ../../blobs/hash1 "$cache/snapshots/rev/model.onnx"
}

@test "backup archive and manifest skip the model cache and restore accepts that archive" {
  add_model_cache
  echo "{}" >"$BM_REMOTE_DATA_ROOT/config/config.json"
  run "$BACKUP"
  assert_success
  local archive
  archive="$(ls "$BACKUP_DIR"/bm-*.tgz)"
  run tar -tzf "$archive"
  assert_line "basic-memory/config/config.json"
  refute_output --partial "fastembed_cache"
  run cat "$archive.manifest"
  refute_output --partial "fastembed_cache"
  ARCHIVE="$archive"
  restore_with_answer yes
  assert_success
  [[ ! -e "$BM_REMOTE_DATA_ROOT/config/fastembed_cache" ]]
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

@test "backup publishes no file of its run when the checksum cannot be written, and spares earlier backups" {
  mkdir -p "$BACKUP_DIR" "$BATS_TEST_TMPDIR/datebin"
  printf '#!/usr/bin/env bash\necho 20261008T000000Z\n' >"$BATS_TEST_TMPDIR/datebin/date"
  chmod +x "$BATS_TEST_TMPDIR/datebin/date"
  export PATH="$BATS_TEST_TMPDIR/datebin:$PATH"
  echo old >"$BACKUP_DIR/bm-20261007T000000Z.tgz"
  echo old >"$BACKUP_DIR/bm-20261007T000000Z.tgz.sha256"
  echo old >"$BACKUP_DIR/bm-20261007T000000Z.tgz.manifest"
  mkdir "$BACKUP_DIR/bm-20261008T000000Z.tgz.sha256.partial"
  run "$BACKUP"
  assert_failure
  assert_output --partial "could not write the checksum"
  rmdir "$BACKUP_DIR/bm-20261008T000000Z.tgz.sha256.partial"
  run ls -A "$BACKUP_DIR"
  assert_output "$(printf '%s\n' bm-20261007T000000Z.tgz bm-20261007T000000Z.tgz.manifest bm-20261007T000000Z.tgz.sha256)"
  run cat "$BACKUP_DIR/bm-20261007T000000Z.tgz"
  assert_output "old"
  run grep -F 'docker compose start' "$STUB_LOG"
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

# fix_backup_stamp STAMP -> make backup.sh name its archive bm-STAMP.tgz.
fix_backup_stamp() {
  mkdir -p "$BATS_TEST_TMPDIR/datebin" "$BACKUP_DIR"
  printf '#!/usr/bin/env bash\necho %s\n' "$1" >"$BATS_TEST_TMPDIR/datebin/date"
  chmod +x "$BATS_TEST_TMPDIR/datebin/date"
  export PATH="$BATS_TEST_TMPDIR/datebin:$PATH"
}

@test "backup refuses a name that already holds a backup and never touches it or the container" {
  fix_backup_stamp 20261008T000000Z
  local file
  for file in bm-20261008T000000Z.tgz bm-20261008T000000Z.tgz.sha256 bm-20261008T000000Z.tgz.manifest; do
    echo old >"$BACKUP_DIR/$file"
  done
  export SSH_STUB_FAIL_MATCH="compose stop"
  run "$BACKUP"
  assert_failure
  assert_output --partial "already exists"
  for file in bm-20261008T000000Z.tgz bm-20261008T000000Z.tgz.sha256 bm-20261008T000000Z.tgz.manifest; do
    run cat "$BACKUP_DIR/$file"
    assert_output "old"
  done
  # The name check runs after the exclusive reservation, so the run must release its own reservation.
  [[ ! -e "$BACKUP_DIR/bm-20261008T000000Z.tgz.partial" ]]
  run grep -F 'compose stop' "$STUB_LOG"
  assert_failure
}

@test "backup refuses while another run holds the same name and leaves its files alone" {
  fix_backup_stamp 20261008T000000Z
  echo other >"$BACKUP_DIR/bm-20261008T000000Z.tgz.partial"
  run "$BACKUP"
  assert_failure
  assert_output --partial "another backup"
  run cat "$BACKUP_DIR/bm-20261008T000000Z.tgz.partial"
  assert_output "other"
  run grep -F 'compose stop' "$STUB_LOG"
  assert_failure
}

@test "backup fails and writes nothing when listing the data files fails" {
  fail_command find
  run "$BACKUP"
  assert_failure
  assert_output --partial "could not build the data manifest"
  run ls -A "$BACKUP_DIR"
  assert_output ""
  run grep -F 'docker compose start' "$STUB_LOG"
  assert_success
}

# --- restore ---

@test "restore replaces the data, keeps the previous copy and fixes ownership" {
  make_archive "from backup"
  install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "from backup"
  run bash -c 'cat "$0".prev-*/knowledge/a.md' "$BM_REMOTE_DATA_ROOT"
  assert_output "original"
  run stat -c '%u' "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "1000"
  run grep -F 'tar --no-same-owner --no-same-permissions -C' "$STUB_LOG"
  assert_success
  run grep -F 'compose up -d --wait --wait-timeout 360' "$STUB_LOG"
  assert_success
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run bash -c 'ls -d "$0".restore-* "$1"/compose.yaml.prev-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_APP_DIR"
  assert_failure
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "SB_USER=admin:test-password"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
}

@test "restore writes the SilverBullet space files into the restored notes folder while stopped, keeping its index.md" {
  local notes="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
  make_archive "from backup"
  # An archive from before the web UI: a notes folder with an index.md but no .gitignore and no library page.
  mkdir -p "$SRC/basic-memory/knowledge/basic-memory"
  echo "my dashboard" >"$SRC/basic-memory/knowledge/basic-memory/index.md"
  pack_archive basic-memory
  local_manifest "$SRC/basic-memory" >"$ARCHIVE.manifest"
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  restore_with_answer yes
  assert_success
  run diff "$REPO_DIR/silverbullet/notes.gitignore" "$notes/.gitignore"
  assert_success
  run diff "$REPO_DIR/silverbullet/agent-hub.md" "$notes/Library/agent-hub/agent-hub.md"
  assert_success
  run cat "$notes/index.md"
  assert_output "my dashboard"
  [[ ! -e "$notes/.gitignore.pending" ]] \
    || fail "the marker must be removed: the stopped Basic Memory loads the new .gitignore when it starts"
  # Every space file write (as the container user) comes after the stop and before the first start.
  run awk '/^docker compose stop$/ { s = NR } /^sudo -n -u #1000 / { if (!f) f = NR; w = NR } /^docker compose up/ && !u { u = NR } END { exit !(s && f && u && s < f && w < u) }' "$STUB_LOG"
  assert_success
}

@test "restore rolls back without starting the restored data when the SilverBullet pages cannot be written" {
  make_archive "restored"
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  export SSH_STUB_FAIL_MATCH="Library/agent-hub"
  restore_with_answer yes
  assert_failure
  assert_output --partial "could not write the SilverBullet pages"
  assert_output --partial "rolled back: the previous data is live again"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  # Only the rollback starts the containers (on the previous data); the half-written space never runs.
  run grep -E '^docker compose up -d --wait' "$STUB_LOG"
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

@test "restore stops before the confirmation without a valid SB_USER, so the VM .env never loses the login" {
  make_archive "x"
  unset SB_USER
  restore_with_answer yes
  assert_failure
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

@test "restore refuses an archive holding a symlink before touching the VM" {
  make_archive "x"
  ln -s /etc "$SRC/basic-memory/knowledge/etc"
  pack_archive basic-memory
  restore_with_answer yes
  assert_failure
  assert_output --partial "unsafe archive"
  assert_output --partial "not a regular file or directory"
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}

@test "restore refuses an archive holding a ../ or absolute path before touching the VM" {
  local entry pack_path reason
  for entry in "../outside.md|../outside.md|'..' component" "$BATS_TEST_TMPDIR/outside.md|$BATS_TEST_TMPDIR/outside.md|absolute path"; do
    IFS='|' read -r entry pack_path reason <<<"$entry"
    make_archive "x"
    echo "outside" >"$BATS_TEST_TMPDIR/outside.md"
    pack_archive -P basic-memory "$pack_path"
    run tar -tzf "$ARCHIVE"
    assert_line "$entry"
    restore_with_answer yes
    assert_failure
    assert_output --partial "unsafe archive"
    assert_output --partial "$reason"
    run grep -F 'ssh' "$STUB_LOG"
    assert_failure
  done
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

@test "restore rollback recreates the container so it mounts the previous data even with an unchanged compose" {
  make_archive "bad"
  cp "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  printf 'BM_PORT=8737\nBM_KNOWLEDGE_DIR=%s/knowledge\nBM_CONFIG_DIR=%s/config\n' \
    "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_DATA_ROOT" >"$BM_REMOTE_APP_DIR/.env"
  # Only the restore's own start fails; the rollback start succeeds.
  export DOCKER_STUB_FAIL_MATCH="up -d --wait"
  restore_with_answer yes
  assert_failure
  assert_output --partial "container did not become healthy with the restored data"
  assert_output --partial "rolled back: the previous data is live again"
  run grep -F 'docker compose up -d --force-recreate --wait --wait-timeout 360' "$STUB_LOG"
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
}

@test "restore on a VM without previous data says the restored data stays when the start fails" {
  make_archive "restored"
  rm -r "$BM_REMOTE_DATA_ROOT"
  export DOCKER_STUB_FAIL_MATCH="up -d"
  restore_with_answer yes
  assert_failure
  refute_output --partial "the previous data is live again"
  assert_output --partial "had no data before this restore"
  assert_output --partial "the restored data is now at $BM_REMOTE_DATA_ROOT"
  assert_output --partial "rerun 'make restore BACKUP=<archive>'"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "restored"
}

@test "restore never rolls back to a partial copy of compose.yaml" {
  make_archive "x"
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  echo "PREVIOUS=env" >"$BM_REMOTE_APP_DIR/.env"
  # A cp that dies midway (disk full): it leaves a partial destination file and fails.
  mkdir -p "$BATS_TEST_TMPDIR/failbin"
  printf '#!/usr/bin/env bash\nprintf partial >"${@: -1}"\nexit 1\n' >"$BATS_TEST_TMPDIR/failbin/cp"
  chmod +x "$BATS_TEST_TMPDIR/failbin/cp"
  export PATH="$BATS_TEST_TMPDIR/failbin:$PATH"
  restore_with_answer yes
  assert_failure
  assert_output --partial "could not upload compose.yaml"
  run cat "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_output "previous compose"
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_output "PREVIOUS=env"
  run ls -A "$BM_REMOTE_APP_DIR"
  assert_output ".env
compose.yaml"
}

@test "restore writes the VM .env and succeeds on a recreated VM with no data, compose or .env" {
  make_archive "fresh"
  rm -r "$BM_REMOTE_DATA_ROOT"
  rm -f "$BM_REMOTE_APP_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/.env"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "fresh"
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

# --- round trip (spec completion criterion 3) ---

@test "a backup made by backup.sh restores with restore.sh and matches its manifest" {
  # A deployed VM already holds the current space files, which the restore writes again unchanged.
  local notes="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
  mkdir -p "$notes/Library/agent-hub"
  cp "$REPO_DIR/silverbullet/notes.gitignore" "$notes/.gitignore"
  cp "$REPO_DIR/silverbullet/agent-hub.md" "$notes/Library/agent-hub/agent-hub.md"
  cp "$REPO_DIR/silverbullet/index.md" "$notes/index.md"
  run "$BACKUP"
  assert_success
  ARCHIVE="$(ls "$BACKUP_DIR"/bm-*.tgz)"
  echo "changed after the backup" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  echo "written after the backup" >"$BM_REMOTE_DATA_ROOT/knowledge/later.md"
  restore_with_answer yes
  assert_success
  assert_output --partial "restored $(basename "$ARCHIVE")"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  [[ ! -e "$BM_REMOTE_DATA_ROOT/knowledge/later.md" ]]
  run local_manifest "$BM_REMOTE_DATA_ROOT"
  assert_output "$(cat "$ARCHIVE.manifest")"
}
