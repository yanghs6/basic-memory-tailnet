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

@test "remote checks BM_ACCESS before it runs ssh, so no VM target reaches the VM with a typo there" {
  BM_ACCESS=SSH run remote true
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'SSH')"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
  BM_ACCESS=ssh run remote "echo hi"
  assert_success
  assert_output "hi"
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
