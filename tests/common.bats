#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker
  use_vm_env
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
}

@test "die prints an error and exits 1" {
  run die "boom"
  assert_failure 1
  assert_output "ERROR: boom"
}

@test "step logs a timestamped marker" {
  run step "deploy"
  assert_success
  assert_output --regexp '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ==> deploy$'
}

@test "require_cmd passes when every command exists" {
  run require_cmd bash jq
  assert_success
}

@test "require_cmd names the missing command" {
  run require_cmd definitely-not-installed
  assert_failure
  assert_output --partial "missing command 'definitely-not-installed'"
}

@test "require_env passes when variables are set" {
  BM_TEST_VALUE=x
  run require_env BM_TEST_VALUE BM_VM_HOST
  assert_success
}

@test "require_env names the missing variable" {
  unset BM_TEST_MISSING
  run require_env BM_TEST_MISSING
  assert_failure
  assert_output --partial "missing env BM_TEST_MISSING"
}

@test "mask keeps only a 4-character prefix of long values" {
  run mask "tskey-auth-abcdef123456"
  assert_output "tske****"
}

@test "mask hides short values completely" {
  run mask "short"
  assert_output "****"
}

@test "remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST" {
  run remote "echo hi"
  assert_success
  assert_output "hi"
  run cat "$STUB_LOG"
  assert_output "ssh -o BatchMode=yes -o ConnectTimeout=10 ubuntu@bm-node echo hi"
}

@test "remote_compose runs docker compose inside the VM app dir" {
  run remote_compose "ps"
  assert_success
  assert_output --partial "basic-memory-server"
  run grep -F "cd $BM_REMOTE_APP_DIR && docker compose ps" "$STUB_LOG"
  assert_success
}

@test "sha256_of prints only the hex digest" {
  printf 'abc' >"$BATS_TEST_TMPDIR/f"
  run sha256_of "$BATS_TEST_TMPDIR/f"
  assert_output "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}
