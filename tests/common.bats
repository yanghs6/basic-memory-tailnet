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
  assert_output --partial "set it in .env in the main checkout"
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

@test "remote propagates a failing command's non-zero exit" {
  export SSH_STUB_FAIL_MATCH="boom"
  run remote "boom"
  assert_failure 255
}

@test "remote_compose propagates a failing compose command's non-zero exit" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run remote_compose "up -d"
  assert_failure 1
}

@test "sha256_of prints only the hex digest" {
  printf 'abc' >"$BATS_TEST_TMPDIR/f"
  run sha256_of "$BATS_TEST_TMPDIR/f"
  assert_output "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
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

@test "manifest_cmd fails when find fails instead of printing a short list" {
  setup_stubs sudo
  mkdir -p "$BATS_TEST_TMPDIR/d" "$BATS_TEST_TMPDIR/failbin"
  printf '#!/usr/bin/env bash\necho "find: simulated failure" >&2\nexit 1\n' >"$BATS_TEST_TMPDIR/failbin/find"
  chmod +x "$BATS_TEST_TMPDIR/failbin/find"
  PATH="$BATS_TEST_TMPDIR/failbin:$PATH" run bash -c "$(manifest_cmd "$BATS_TEST_TMPDIR/d")"
  assert_failure
}

@test "main_checkout_root prints the repo root when asked about the main checkout" {
  make_worktree_fixture
  run main_checkout_root "$MAIN_REPO"
  assert_success
  assert_output "$MAIN_REPO"
}

@test "main_checkout_root prints the main checkout when asked about a linked worktree" {
  make_worktree_fixture
  run main_checkout_root "$LINKED_WT"
  assert_success
  assert_output "$MAIN_REPO"
}

@test "main_checkout_root defaults to the repo that holds the scripts" {
  run main_checkout_root
  assert_success
  assert_output --regexp '^/.+'
  refute_output --regexp '\.git$'
}

@test "main_checkout_root fails outside a git repository" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  run main_checkout_root "$BATS_TEST_TMPDIR/plain"
  assert_failure
}
