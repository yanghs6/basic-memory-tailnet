#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker sudo
  use_vm_env
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  BACKUP="$REPO_DIR/scripts/backup-notes.sh"
}

# fail_command NAME -> put a NAME first on PATH that prints an error and exits 1.
fail_command() {
  mkdir -p "$BATS_TEST_TMPDIR/failbin"
  printf '#!/usr/bin/env bash\necho "%s: simulated failure" >&2\nexit 1\n' "$1" >"$BATS_TEST_TMPDIR/failbin/$1"
  chmod +x "$BATS_TEST_TMPDIR/failbin/$1"
  export PATH="$BATS_TEST_TMPDIR/failbin:$PATH"
}

# fix_backup_stamp STAMP -> make backup-notes.sh name its archive bm-STAMP.tgz.
fix_backup_stamp() {
  mkdir -p "$BATS_TEST_TMPDIR/datebin" "$BACKUP_DIR"
  printf '#!/usr/bin/env bash\necho %s\n' "$1" >"$BATS_TEST_TMPDIR/datebin/date"
  chmod +x "$BATS_TEST_TMPDIR/datebin/date"
  export PATH="$BATS_TEST_TMPDIR/datebin:$PATH"
}

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

@test "backup from a linked worktree saves into the main checkout's backups/" {
  unset BACKUP_DIR
  make_worktree_fixture
  cp -R "$REPO_DIR/scripts" "$LINKED_WT/scripts"
  cd "$LINKED_WT"
  run "$LINKED_WT/scripts/backup-notes.sh"
  assert_success
  assert_output --partial "backup saved: $MAIN_REPO/backups/bm-"
  run ls "$MAIN_REPO/backups"
  assert_success
  assert_output --partial ".tgz.sha256"
  [[ ! -e "$LINKED_WT/backups" ]]
}

@test "backup defaults to backups/ in the main checkout that git reports" {
  unset BACKUP_DIR
  make_worktree_fixture
  GIT_DIR="$MAIN_REPO/.git" run "$REPO_DIR/scripts/backup-notes.sh"
  assert_success
  assert_output --partial "backup saved: $MAIN_REPO/backups/bm-"
  run ls "$MAIN_REPO/backups"
  assert_output --partial ".tgz.manifest"
}

@test "backup fails with an actionable message when the main checkout cannot be found" {
  unset BACKUP_DIR
  make_worktree_fixture
  GIT_DIR="$BATS_TEST_TMPDIR/missing-repo" run "$REPO_DIR/scripts/backup-notes.sh"
  assert_failure
  assert_output --partial "cannot find the main checkout"
  assert_output --partial "set BACKUP_DIR"
  run grep -F 'docker compose' "$STUB_LOG"
  assert_failure
}
