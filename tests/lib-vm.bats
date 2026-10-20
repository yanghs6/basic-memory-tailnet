#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker sudo
  use_vm_env
  # shellcheck source=../scripts/lib/vm.sh
  . "$REPO_DIR/scripts/lib/vm.sh"
}

@test "remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST" {
  run remote "echo hi"
  assert_success
  assert_output "hi"
  run cat "$STUB_LOG"
  assert_output "ssh -o BatchMode=yes -o ConnectTimeout=10 ubuntu@agent-hub echo hi"
}

@test "require_vm stops on an unknown BM_ACCESS, a missing command or missing VM settings, before any ssh" {
  BM_ACCESS=SSH run require_vm
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'SSH')"
  run require_vm no-such-command
  assert_failure
  assert_output --partial "missing command 'no-such-command'"
  BM_VM_USER= run require_vm
  assert_failure
  assert_output --partial "missing env BM_VM_USER"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
  BM_ACCESS=ssh run require_vm
  assert_success
}

@test "remote_exists and remote_compose --if-deployed follow what is on the VM, and remote_exists fails when the VM does not answer" {
  local file="$BM_REMOTE_APP_DIR/compose.yaml"
  run remote_exists "$file"
  assert_success
  assert_output absent
  run remote_compose --if-deployed stop
  assert_success
  run grep '^docker ' "$STUB_LOG"
  assert_failure
  touch "$file"
  run remote_exists "$file"
  assert_output present
  run remote_compose --if-deployed stop
  assert_success
  run grep -Fx 'docker compose stop' "$STUB_LOG"
  assert_success
  SSH_STUB_FAIL_MATCH="-e $file" run remote_exists "$file"
  assert_failure
  refute_line absent
}

@test "manifest_cmd lists every file's sha256 sorted by path" {
  setup_stubs sudo
  mkdir -p "$BATS_TEST_TMPDIR/d/b"
  printf 'abc' >"$BATS_TEST_TMPDIR/d/b/z.md"
  printf 'abc' >"$BATS_TEST_TMPDIR/d/a.md"
  run bash -c "$(manifest_cmd "$BATS_TEST_TMPDIR/d")"
  assert_success
  assert_line --index 0 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  ./a.md"
  assert_line --index 1 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  ./b/z.md"
}
