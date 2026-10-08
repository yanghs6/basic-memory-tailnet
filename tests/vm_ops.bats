#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc
  use_vm_env
  export BM_VM_PUBLIC_IP=203.0.113.10
  export VERIFY_ID=test1
  cp -R "$REPO_DIR/tests/fixtures/mcp-sse" "$BATS_TEST_TMPDIR/fixtures"
  export CURL_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
}

# --- deploy ---

@test "deploy uploads compose.yaml and a VM .env, then pulls and waits for healthy" {
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  run grep -F 'docker compose pull -q' "$STUB_LOG"
  assert_success
  run grep -F 'docker compose up -d --wait --wait-timeout 180' "$STUB_LOG"
  assert_success
}

@test "deploy reports an unhealthy container" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "did not become healthy within 180s"
}

@test "deploy explains an unreachable VM" {
  export SSH_STUB_FAIL_MATCH="compose.yaml"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "is bm-node reachable over Tailscale SSH?"
}

@test "deploy requires the VM settings from .env" {
  unset BM_VM_HOST
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "missing env BM_VM_HOST"
}

# --- verify-vm ---

@test "verify runs the MCP round trip over the tailnet URL and checks loopback binding" {
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
  assert_output --partial "port 8737 listens on 127.0.0.1 only"
  run grep -F 'https://bm-node.example.ts.net/mcp' "$STUB_LOG"
  assert_success
}

@test "verify fails when the port is exposed beyond loopback" {
  export SS_STUB_OUTPUT="LISTEN 0 4096 0.0.0.0:8737 0.0.0.0:*"
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "port 8737 is exposed beyond loopback"
}

@test "verify fails when nothing listens on the port" {
  export SS_STUB_OUTPUT=""
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "nothing listens on port 8737"
}

@test "verify rejects a malformed tailnet domain" {
  export BM_TAILNET_DOMAIN="https://tail1234.ts.net."
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "BM_TAILNET_DOMAIN must look like tail1234.ts.net"
}

@test "verify confirms the public IP refuses SSH, HTTP, HTTPS and the MCP port" {
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8737"
  run grep -c '^nc ' "$STUB_LOG"
  assert_output 4
}

@test "verify requires the public IP so exposure is always checked" {
  unset BM_VM_PUBLIC_IP
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "missing env BM_VM_PUBLIC_IP"
}

@test "verify fails when Tailscale Funnel exposes the VM" {
  export TS_STUB_FUNNEL=on
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "Funnel is on for this node"
}

@test "probe runs every check without writing notes" {
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "tailscale serve is tailnet only"
  assert_output --partial "public IP 203.0.113.10 refuses"
  run grep -F '"method":"tools/call"' "$STUB_LOG.requests"
  assert_failure
}

@test "verify rejects unknown arguments" {
  run "$REPO_DIR/scripts/verify-vm.sh" --bogus
  assert_failure
  assert_output --partial "usage: verify-vm.sh [--read-only]"
}

@test "verify fails when the public IP still accepts connections" {
  export NC_STUB_EXIT=0
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "accepts connections on port 22"
}

# --- status ---

@test "status shows containers, memory use and tailscale serve" {
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "basic-memory-server"
  assert_output --partial "memory used: 23%"
  assert_output --partial "proxy http://127.0.0.1:8737"
  refute_output --partial "WARNING"
}

@test "status warns about OCI idle reclamation below 20% memory" {
  export FREE_STUB_AVAILABLE_MB=3500
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "memory used: 10%"
  assert_output --partial "WARNING: memory below 20%"
}

@test "status fails when tailscale serve is not configured" {
  export SSH_STUB_FAIL_MATCH="tailscale serve status"
  run "$REPO_DIR/scripts/status.sh"
  assert_failure
  assert_output --partial "tailscale serve is not configured"
}

@test "status fails when containers cannot be queried" {
  export SSH_STUB_FAIL_MATCH="compose ps"
  run "$REPO_DIR/scripts/status.sh"
  assert_failure
  assert_output --partial "could not query containers on bm-node"
}

# --- logs ---

@test "logs prints the last 200 lines from the VM" {
  run "$REPO_DIR/scripts/logs.sh"
  assert_success
  run grep -F 'docker compose logs --tail=200' "$STUB_LOG"
  assert_success
}

@test "logs explains a failure" {
  export SSH_STUB_FAIL_MATCH="compose logs"
  run "$REPO_DIR/scripts/logs.sh"
  assert_failure
  assert_output --partial "could not read logs from bm-node"
}
