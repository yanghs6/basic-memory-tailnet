#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh sudo
  use_vm_env
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/local-notes"
  SB_SPACE="$REPO_DIR/scripts/sync-sb-space.sh"
  SRC="$REPO_DIR/silverbullet"
  VM_NOTES="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
}

@test "local: writes only the .gitignore until Basic Memory was recreated, then the library page every run and index.md once" {
  local page="$SB_LOCAL_NOTES_DIR/Library/agent-hub/agent-hub.md"
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  assert_same_file "$SRC/notes.gitignore" "$SB_LOCAL_NOTES_DIR/.gitignore"
  [[ ! -e "$page" && ! -e "$SB_LOCAL_NOTES_DIR/index.md" ]] \
    || fail "the pages must wait until Basic Memory loaded the new .gitignore, or it indexes them"

  # The caller failed before recreating Basic Memory, so the marker stays and the next run asks again.
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  [[ ! -e "$page" && ! -e "$SB_LOCAL_NOTES_DIR/index.md" ]] || fail "the pages must wait while the marker stays"

  # The caller recreated Basic Memory and removed the marker.
  rm "$SB_LOCAL_NOTES_DIR/.gitignore.pending"
  run "$SB_SPACE" --local
  assert_success
  assert_line unchanged
  assert_same_file "$SRC/agent-hub.md" "$page"
  assert_same_file "$SRC/index.md" "$SB_LOCAL_NOTES_DIR/index.md"

  echo "my dashboard" >"$SB_LOCAL_NOTES_DIR/index.md"
  echo "stale" >"$page"
  run "$SB_SPACE" --local
  assert_success
  assert_line unchanged
  run cat "$SB_LOCAL_NOTES_DIR/index.md"
  assert_output "my dashboard"
  assert_same_file "$SRC/agent-hub.md" "$page"

  echo "/extra/" >>"$SB_LOCAL_NOTES_DIR/.gitignore"
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  assert_same_file "$SRC/notes.gitignore" "$SB_LOCAL_NOTES_DIR/.gitignore"
  refute_stub_called '^ssh '
}

@test "VM: writes the space files into the VM notes folder, always as the container user" {
  local total as_container
  run "$SB_SPACE"
  assert_success
  assert_line changed
  # The caller recreated Basic Memory and removed the marker; the second run writes the pages.
  rm "$VM_NOTES/.gitignore.pending"
  run "$SB_SPACE"
  assert_success
  assert_line unchanged
  assert_same_file "$SRC/notes.gitignore" "$VM_NOTES/.gitignore"
  assert_same_file "$SRC/agent-hub.md" "$VM_NOTES/Library/agent-hub/agent-hub.md"
  assert_same_file "$SRC/index.md" "$VM_NOTES/index.md"
  total="$(grep -c '^sudo ' "$STUB_LOG")"
  as_container="$(grep -c '^sudo -n -u #1000 sh -c ' "$STUB_LOG")"
  ((total > 0 && total == as_container)) || fail "every VM write must run as uid 1000: $(grep '^sudo ' "$STUB_LOG")"
}

@test "VM: fails and leaves index.md alone when it cannot tell whether index.md exists" {
  mkdir -p "$VM_NOTES"
  # Basic Memory already loaded this .gitignore (no marker), so the run goes on to the index.md check.
  cp "$SRC/notes.gitignore" "$VM_NOTES/.gitignore"
  echo "my dashboard" >"$VM_NOTES/index.md"
  SSH_STUB_FAIL_MATCH="-e index.md" run "$SB_SPACE"
  assert_failure
  assert_output --partial "could not check for index.md"
  run cat "$VM_NOTES/index.md"
  assert_output "my dashboard"
}
