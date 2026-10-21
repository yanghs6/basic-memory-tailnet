#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
}

@test "deploy uploads compose.yaml, an owner-only VM .env with SB_USER and the space files, then pulls and waits for healthy" {
  local expected_env="$BATS_TEST_TMPDIR/vm.env"
  install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  refute_output --partial "test-password"
  assert_same_file "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  (
    # shellcheck source=../scripts/lib/vm.sh
    . "$REPO_DIR/scripts/lib/vm.sh"
    vm_env
  ) >"$expected_env"
  assert_same_file "$expected_env" "$BM_REMOTE_APP_DIR/.env"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
  [[ -e "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md" ]] \
    || fail "deploy must write the managed library page"
  assert_stub_called -F 'docker compose pull -q'
  assert_stub_called -F 'docker compose up -d --wait --wait-timeout 360'
}

@test "deploy recreates Basic Memory before starting SilverBullet only when the notes .gitignore changed, and writes the pages after the recreate" {
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^docker compose up -d --wait --wait-timeout 360$/ { u = NR } END { exit !(r && u && r < u) }' "$STUB_LOG"
  assert_success
  # The first write of the library page comes after the recreate, so the old Basic Memory never indexes it.
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^sudo .*Library\/agent-hub\/agent-hub\.md/ && !p { p = NR } END { exit !(r && p && r < p) }' "$STUB_LOG"
  assert_success
}

@test "deploy writes nothing into the notes folder when the image pull fails" {
  local notes="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
  export DOCKER_STUB_FAIL_MATCH="pull -q"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  [[ ! -e "$notes/.gitignore" && ! -e "$notes/.gitignore.pending" ]] \
    || fail "a failed pull must leave the notes .gitignore and its marker unwritten"
}

@test "deploy reports an unhealthy container" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  assert_output --partial "did not become healthy within 360s"
}
