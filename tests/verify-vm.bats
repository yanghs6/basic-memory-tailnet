#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
  export BM_VM_PUBLIC_IP=203.0.113.10
  export VERIFY_ID=test1
  cp -R "$REPO_DIR/tests/fixtures/mcp-sse" "$BATS_TEST_TMPDIR/fixtures"
  export CURL_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  export CURL_SB_COOKIE="set-cookie: auth_agent-hub=stub-session-token; Path=/; SameSite=Lax; HttpOnly; Secure"
}

# A failing test must not leave a stub tunnel (sleep) behind.
teardown() {
  local pid
  [[ -f "$STUB_LOG.tunnel-pids" ]] || return 0
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done <"$STUB_LOG.tunnel-pids"
}

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
    # shellcheck disable=SC2086 # a case may hold several VAR=value words; env needs them split
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

@test "ssh mode: probe checks through a verify tunnel on 127.0.0.1 and leaves no tunnel behind" {
  use_ssh_mode
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "OK: Tailscale does not expose the VM"
  assert_output --partial "OK: sshd accepts keys only"
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8443 8737 3000"
  assert_output --partial "OK: automated VM checks passed (access: ssh)"
  run grep -Fx 'ssh -N -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=10 -L 127.0.0.1:28737:127.0.0.1:8737 -L 127.0.0.1:23000:127.0.0.1:3000 ubuntu@agent-hub-iap' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale serve' "$STUB_LOG"
  assert_failure
  run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
  assert_failure
}

@test "verify in the ssh mode refuses a verify port that is already in use before it starts ssh" {
  use_ssh_mode
  export NC_STUB_OPEN_MATCH=28737
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "port 28737 is in use on 127.0.0.1"
  run grep -F 'ssh -N' "$STUB_LOG"
  assert_failure
}

@test "ssh mode: verify closes its tunnel even when a check fails" {
  use_ssh_mode
  export CURL_STUB_EXIT=7
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "verify tunnel is open"
  [[ -s "$STUB_LOG.tunnel-pids" ]] || fail "the verify tunnel never started"
  run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
  assert_failure
}

@test "ssh mode: verify fails while Tailscale is logged in or unreadable on the VM, sshd takes passwords or the tunnel does not open" {
  use_ssh_mode
  TS_STUB_BACKEND_STATE=Running run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "Tailscale is logged in on the VM but BM_ACCESS=ssh"

  # A state it cannot read or does not know never counts as off.
  TS_STUB_BACKEND_STATE=Starting run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "unexpected Tailscale state on agent-hub-iap: 'Starting'"

  SSH_STUB_FAIL_MATCH="tailscale status" run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "could not read the Tailscale state on agent-hub-iap"

  SSHD_STUB_PASSWORD=yes run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "sshd on the VM accepts passwords"

  # The failed tunnel also leaves the local port closed, or nc could report it open before the stub exits (the runs
  # above left tunnel pids behind, so the open-after-tunnel mode is off here).
  SSH_STUB_TUNNEL_EXIT=255 NC_STUB_OPEN_AFTER_TUNNEL='' run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_failure
  assert_output --partial "verify tunnel exited before it opened"
}

@test "verify rejects a BM_ACCESS it does not know, also in another case, before it contacts the VM" {
  local value
  for value in SSH Ssh; do
    BM_ACCESS=$value run "$REPO_DIR/scripts/verify-vm.sh"
    assert_failure
    assert_output --partial "BM_ACCESS must be tailscale or ssh (got '$value')"
    run grep -E '^(ssh|curl|nc) ' "$STUB_LOG"
    assert_failure
  done
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
    assert_output --partial "docs/runbooks/rbk-2026-10-12-gcp-vm.md"
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
