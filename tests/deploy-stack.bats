#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
}

@test "deploy uploads compose.yaml, an owner-only VM .env with SB_USER and the space files, then pulls and waits for healthy" {
  install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  refute_output --partial "test-password"
  assert_same_file "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  assert_line "SB_PORT=3000"
  assert_line "SB_USER=admin:test-password"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
  assert_same_file "$REPO_DIR/silverbullet/notes.gitignore" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore"
  assert_same_file "$REPO_DIR/silverbullet/agent-hub.md" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
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
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
}

@test "deploy still recreates Basic Memory on the retry after the image pull failed behind a new notes .gitignore" {
  local page="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
  export DOCKER_STUB_FAIL_MATCH="pull -q"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  refute_stub_called '^docker compose .*--force-recreate basic-memory$'
  [[ ! -e "$page" ]] || fail "the pages must wait until Basic Memory was recreated"
  unset DOCKER_STUB_FAIL_MATCH
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  [[ ! -e "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore.pending" ]] \
    || fail "the marker must be removed once Basic Memory was recreated"
  [[ -e "$page" ]] || fail "the retry must write the pages after the recreate"
}

@test "deploy leaves the VM untouched without a valid SB_USER" {
  unset SB_USER
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  refute_stub_called '^ssh '
}

@test "deploy reports an unhealthy container" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  assert_output --partial "did not become healthy within 360s"
}

@test "deploy requires the VM settings from .env" {
  unset BM_VM_HOST
  run "$REPO_DIR/scripts/deploy-stack.sh"
  assert_failure
  assert_output --partial "missing env BM_VM_HOST"
  assert_output --partial "set it in .env in the main checkout"
}
