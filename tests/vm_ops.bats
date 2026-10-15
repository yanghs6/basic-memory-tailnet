#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname
  use_vm_env
  export BM_VM_PUBLIC_IP=203.0.113.10
  export VERIFY_ID=test1
  cp -R "$REPO_DIR/tests/fixtures/mcp-sse" "$BATS_TEST_TMPDIR/fixtures"
  export CURL_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  export CURL_SB_COOKIE="set-cookie: auth_agent-hub=stub-session-token; Path=/; SameSite=Lax; HttpOnly; Secure"
}

# --- deploy ---

@test "deploy uploads compose.yaml, an owner-only VM .env with SB_USER and the space files, then pulls and waits for healthy" {
  install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  refute_output --partial "test-password"
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  assert_line "SB_PORT=3000"
  assert_line "SB_USER=admin:test-password"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
  run diff "$REPO_DIR/silverbullet/notes.gitignore" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore"
  assert_success
  run diff "$REPO_DIR/silverbullet/agent-hub.md" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
  assert_success
  run grep -F 'docker compose pull -q' "$STUB_LOG"
  assert_success
  run grep -F 'docker compose up -d --wait --wait-timeout 360' "$STUB_LOG"
  assert_success
}

@test "deploy recreates Basic Memory before starting SilverBullet only when the notes .gitignore changed, and writes the pages after the recreate" {
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^docker compose up -d --wait --wait-timeout 360$/ { u = NR } END { exit !(r && u && r < u) }' "$STUB_LOG"
  assert_success
  # The first write of the library page comes after the recreate, so the old Basic Memory never indexes it.
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^sudo .*Library\/agent-hub\/agent-hub\.md/ && !p { p = NR } END { exit !(r && p && r < p) }' "$STUB_LOG"
  assert_success
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
}

@test "deploy still recreates Basic Memory on the retry after the image pull failed behind a new notes .gitignore" {
  local page="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
  export DOCKER_STUB_FAIL_MATCH="pull -q"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "0"
  [[ ! -e "$page" ]] || fail "the pages must wait until Basic Memory was recreated"
  unset DOCKER_STUB_FAIL_MATCH
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  [[ ! -e "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore.pending" ]] \
    || fail "the marker must be removed once Basic Memory was recreated"
  [[ -e "$page" ]] || fail "the retry must write the pages after the recreate"
}

@test "deploy leaves the VM untouched without a valid SB_USER" {
  unset SB_USER
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  run grep -c '^ssh ' "$STUB_LOG"
  assert_output "0"
}

@test "deploy reports an unhealthy container" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "did not become healthy within 360s"
}

@test "deploy requires the VM settings from .env" {
  unset BM_VM_HOST
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "missing env BM_VM_HOST"
  assert_output --partial "set it in .env in the main checkout"
}

# --- verify-vm ---

@test "verify runs the MCP round trip and the SilverBullet login over the tailnet URLs and checks both loopback ports" {
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
  assert_output --partial "OK: SilverBullet checks passed for https://agent-hub.example.ts.net:8443"
  assert_output --partial "port 8737 listens on 127.0.0.1 only"
  assert_output --partial "port 3000 listens on 127.0.0.1 only"
  assert_output --partial "443 -> 127.0.0.1:8737, 8443 -> 127.0.0.1:3000"
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8443 8737 3000"
  run grep -F 'https://agent-hub.example.ts.net/mcp' "$STUB_LOG"
  assert_success
  run grep -c '^nc ' "$STUB_LOG"
  assert_output 6
}

@test "verify fails when the port is exposed beyond loopback" {
  export SS_STUB_OUTPUT="LISTEN 0 4096 0.0.0.0:8737 0.0.0.0:*"
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "port 8737 is exposed beyond loopback"
}

@test "verify bounds the public probe's connect time with -G on macOS only" {
  export UNAME_STUB_OUTPUT=Darwin
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  run grep -Fx 'nc -z -G 5 -w 5 203.0.113.10 22' "$STUB_LOG"
  assert_success
  run grep -c '^nc -z -G 5 -w 5 ' "$STUB_LOG"
  assert_output 6

  : >"$STUB_LOG"
  export UNAME_STUB_OUTPUT=Linux
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  run grep -Fx 'nc -z -w 5 203.0.113.10 22' "$STUB_LOG"
  assert_success
  run grep -F -- '-G' "$STUB_LOG"
  assert_failure
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

@test "verify fails unless Serve sends 443 to Basic Memory and 8443 to SilverBullet with Funnel off on both" {
  local case
  for case in "TS_STUB_SERVE_8443=" "TS_STUB_SERVE_8443=http://127.0.0.1:8737" "TS_STUB_SERVE_EMPTY=1" \
    "TS_STUB_FUNNEL=on TS_STUB_FUNNEL_PORT=8443"; do
    run env $case "$REPO_DIR/scripts/verify-vm.sh" --read-only
    [[ "$status" -ne 0 ]] || fail "expected a failure with $case; got: $output"
  done
}

@test "probe runs every check without writing notes, logging in or needing SB_USER" {
  unset SB_USER
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "OK: SilverBullet answers and refuses requests without a login"
  assert_output --partial "tailscale serve is tailnet only"
  assert_output --partial "public IP 203.0.113.10 refuses"
  run grep -F '"method":"tools/call"' "$STUB_LOG.requests"
  assert_failure
  run grep -F '/.auth' "$STUB_LOG"
  assert_failure
}

@test "verify fails when the public IP still accepts connections" {
  export NC_STUB_EXIT=0
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "accepts connections on port 22"
}

@test "verify rejects non-IP and private or loopback public IPs" {
  local ip
  for ip in example.com 1.2.3 999.1.1.1 127.0.0.1 10.0.0.5 172.16.0.1 172.31.255.255 192.168.1.1 169.254.1.1 0.0.0.0; do
    BM_VM_PUBLIC_IP="$ip" run "$REPO_DIR/scripts/verify-vm.sh"
    assert_failure
    assert_output --partial "docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md"
    if [[ "$ip" == 999.1.1.1 ]]; then
      assert_output --partial "BM_VM_PUBLIC_IP must be the VM's public IPv4"
    fi
  done
  run grep -c '^nc ' "$STUB_LOG"
  assert_output 0
}

@test "verify fails when nc rejects its options instead of probing" {
  export NC_STUB_EXIT=1 NC_STUB_STDERR="nc: invalid option -- G"
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "public port probe error on 203.0.113.10:22: nc: invalid option -- G"
}

@test "verify treats refused, timed out and ICMP-rejected connections as closed" {
  local msg
  for msg in \
    "nc: connect to 203.0.113.10 port 22 (tcp) failed: Connection refused" \
    "nc: connect to 203.0.113.10 port 22 (tcp) failed: Operation timed out" \
    "nc: connect to 203.0.113.10 port 8737 (tcp) failed: No route to host"; do
    # A host firewall may reject with icmp-host-prohibited, which nc reports as no route to host.
    NC_STUB_EXIT=1 NC_STUB_STDERR="$msg" run "$REPO_DIR/scripts/verify-vm.sh"
    assert_success
  done
}

# --- status ---

@test "status shows containers, memory use and tailscale serve" {
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "basic-memory-server"
  assert_output --partial "memory used: 23%"
  assert_output --partial "swap used: 0/1023 MB"
  assert_output --partial "proxy http://127.0.0.1:8737"
  refute_output --partial "WARNING"
  export FREE_STUB_SWAP_USED_MB=200
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "swap used: 200/1023 MB"
  refute_output --partial "WARNING"
}

@test "status warns to rerun vm-bootstrap when no swap is active" {
  export FREE_STUB_SWAP_TOTAL_MB=0
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "swap used: 0/0 MB"
  assert_output --partial "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  assert_output --partial "proxy http://127.0.0.1:8737"
}

# --- logs ---

@test "logs prints the last 200 lines from the VM" {
  run "$REPO_DIR/scripts/logs.sh"
  assert_success
  run grep -F 'docker compose logs --tail=200' "$STUB_LOG"
  assert_success
}
