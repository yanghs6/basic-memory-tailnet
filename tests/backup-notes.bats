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
  fake_cmd "$1" "echo \"$1: simulated failure\" >&2
exit 1"
}

# fix_backup_stamp STAMP -> make backup-notes.sh name its archive bm-STAMP.tgz.
fix_backup_stamp() {
  mkdir -p "$BACKUP_DIR"
  fake_cmd date "echo $1"
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
  run ls "$BACKUP_DIR"
  refute_output --partial ".partial"
  assert_equal "${#lines[@]}" 3
  run grep -E '^docker compose (stop|start)' "$STUB_LOG"
  assert_line --index 0 "docker compose stop"
  assert_line --index 1 "docker compose start"
}

@test "backup restarts the container, keeps no file of its run and spares earlier backups when the stop, the listing, the stream or the checksum fails" {
  local case step match message file
  local earlier=(bm-20261007T000000Z.tgz bm-20261007T000000Z.tgz.manifest bm-20261007T000000Z.tgz.sha256)
  # Each case, in pipeline order: the step that fails | the ssh stub's fail match for it | the message of that step.
  for case in "stop|compose stop|could not confirm the container stopped" \
    "listing||could not build the data manifest" \
    "stream|tar -C|backup stream failed" \
    "checksum||could not write the checksum"; do
    IFS='|' read -r step match message <<<"$case"
    (
      : >"$STUB_LOG"
      rm -rf "$BACKUP_DIR" "$STUB_BIN/find"
      fix_backup_stamp 20261008T000000Z
      for file in "${earlier[@]}"; do
        echo old >"$BACKUP_DIR/$file"
      done
      case "$step" in
        listing) fail_command find ;;
        # A directory in the way of the checksum file makes its write fail.
        checksum) mkdir "$BACKUP_DIR/bm-20261008T000000Z.tgz.sha256.partial" ;;
      esac
      SSH_STUB_FAIL_MATCH="$match" run "$BACKUP"
      assert_failure && assert_output --partial "$message" && assert_stub_called -F 'docker compose start' || exit 1
      if [[ "$step" == checksum ]]; then
        rmdir "$BACKUP_DIR/bm-20261008T000000Z.tgz.sha256.partial" || exit 1
      fi
      run ls -A "$BACKUP_DIR"
      assert_output "$(printf '%s\n' "${earlier[@]}")" || exit 1
      for file in "${earlier[@]}"; do
        run cat "$BACKUP_DIR/$file"
        assert_output old || exit 1
      done
    ) || fail "backup after a failed $step"
  done
}

@test "backup refuses a name that another backup or another run holds, without stopping the container or touching those files" {
  local case message content names file held
  # Each case: the message of the check that refuses | the content of the files that hold the name | those files.
  for case in "already exists|old|bm-20261008T000000Z.tgz bm-20261008T000000Z.tgz.manifest bm-20261008T000000Z.tgz.sha256" \
    "another backup|other|bm-20261008T000000Z.tgz.partial"; do
    IFS='|' read -r message content names <<<"$case"
    read -r -a held <<<"$names"
    (
      : >"$STUB_LOG"
      rm -rf "$BACKUP_DIR"
      fix_backup_stamp 20261008T000000Z
      for file in "${held[@]}"; do
        echo "$content" >"$BACKUP_DIR/$file"
      done
      SSH_STUB_FAIL_MATCH="compose stop" run "$BACKUP"
      assert_failure && assert_output --partial "$message" && refute_stub_called -F 'compose stop' || exit 1
      # Only the held files remain: the name check runs after the exclusive reservation, so the run released its own .partial.
      run ls -A "$BACKUP_DIR"
      assert_output "$(printf '%s\n' "${held[@]}")" || exit 1
      for file in "${held[@]}"; do
        run cat "$BACKUP_DIR/$file"
        assert_output "$content" || exit 1
      done
    ) || fail "backup went on although $names held its name"
  done
}

@test "backup saves into the main checkout's backups/, from a linked worktree and from GIT_DIR" {
  local from
  unset BACKUP_DIR
  make_worktree_fixture
  cp -R "$REPO_DIR/scripts" "$LINKED_WT/scripts"
  for from in "linked worktree" GIT_DIR; do
    (
      : >"$STUB_LOG"
      rm -rf "$MAIN_REPO/backups" "$LINKED_WT/backups"
      case "$from" in
        "linked worktree")
          cd "$LINKED_WT" || exit 1
          run "$LINKED_WT/scripts/backup-notes.sh"
          ;;
        GIT_DIR) GIT_DIR="$MAIN_REPO/.git" run "$REPO_DIR/scripts/backup-notes.sh" ;;
      esac
      assert_success && assert_output --partial "backup saved: $MAIN_REPO/backups/bm-" || exit 1
      run ls "$MAIN_REPO/backups"
      assert_success && assert_output --partial ".tgz.manifest" && assert_output --partial ".tgz.sha256" \
        && [[ ! -e "$LINKED_WT/backups" ]]
    ) || fail "backup from $from"
  done
}

@test "backup fails with an actionable message when the main checkout cannot be found" {
  unset BACKUP_DIR
  make_worktree_fixture
  GIT_DIR="$BATS_TEST_TMPDIR/missing-repo" run "$REPO_DIR/scripts/backup-notes.sh"
  assert_failure
  assert_output --partial "cannot find the main checkout"
  assert_output --partial "set BACKUP_DIR"
  refute_stub_called -F 'docker compose'
}
