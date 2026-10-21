#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
  export BM_VM_PUBLIC_IP=203.0.113.10
  export VERIFY_ID=test1
  use_mcp_fixtures sse
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
  assert_stub_called -F 'https://agent-hub.example.ts.net/mcp'
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
  assert_stub_called -Fx 'nc -z -G 5 -w 5 203.0.113.10 22'
  run grep -c '^nc -z -G 5 -w 5 ' "$STUB_LOG"
  assert_output 6

  : >"$STUB_LOG"
  export UNAME_STUB_OUTPUT=Linux
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_stub_called -Fx 'nc -z -w 5 203.0.113.10 22'
  refute_stub_called -F -- '-G'
}

@test "verify stops before any probe without a public IPv4" {
  local case ip expected private="is loopback, private, link-local or unspecified"
  for case in "<unset>|missing env BM_VM_PUBLIC_IP" "|missing env BM_VM_PUBLIC_IP" \
    "example.com|BM_VM_PUBLIC_IP must be the VM's public IPv4 (got" "1.2.3|BM_VM_PUBLIC_IP must be the VM's public IPv4 (got" \
    "999.1.1.1|BM_VM_PUBLIC_IP must be the VM's public IPv4 (octets 0-255" \
    "127.0.0.1|$private" "10.0.0.5|$private" "172.16.0.1|$private" "172.31.255.255|$private" "192.168.1.1|$private" \
    "169.254.1.1|$private" "0.0.0.0|$private"; do
    IFS='|' read -r ip expected <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      if [[ "$ip" == "<unset>" ]]; then
        unset BM_VM_PUBLIC_IP
      else
        export BM_VM_PUBLIC_IP="$ip"
      fi
      run "$REPO_DIR/scripts/verify-vm.sh"
      assert_failure && assert_output --partial "$expected" && refute_stub_called '^nc '
    ) || fail "verify went on with BM_VM_PUBLIC_IP $ip"
  done
}

@test "verify fails unless Serve sends 443 to Basic Memory and 8443 to SilverBullet with Funnel off on both" {
  local case settings expected words
  for case in "TS_STUB_SERVE_8443=|tailscale serve must proxy https port 8443" \
    "TS_STUB_SERVE_8443=http://127.0.0.1:8737|tailscale serve must proxy https port 8443" \
    "TS_STUB_SERVE_EMPTY=1|tailscale serve must proxy https port 443" \
    "TS_STUB_FUNNEL=on|Funnel is on for this node" \
    "TS_STUB_FUNNEL=on TS_STUB_FUNNEL_PORT=8443|Funnel is on for this node"; do
    IFS='|' read -r settings expected <<<"$case"
    read -r -a words <<<"$settings"
    (
      run env "${words[@]}" "$REPO_DIR/scripts/verify-vm.sh" --read-only
      assert_failure && assert_output --partial "$expected"
    ) || fail "verify did not stop at the Serve check with $settings"
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
  refute_stub_called -F '/.auth'
}

@test "ssh mode: probe checks through a verify tunnel on 127.0.0.1 and closes it, also when a check fails" {
  use_ssh_mode
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "OK: Tailscale does not expose the VM"
  assert_output --partial "OK: sshd accepts keys only"
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8443 8737 3000"
  assert_output --partial "OK: automated VM checks passed (access: ssh)"
  assert_stub_called -Fx 'ssh -N -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=10 -L 127.0.0.1:28737:127.0.0.1:8737 -L 127.0.0.1:23000:127.0.0.1:3000 ubuntu@agent-hub-iap'
  refute_stub_called -F 'tailscale serve'
  run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
  assert_failure

  # The tunnel above is closed (checked), so a fresh pid list shows whether this run opened and closed its own.
  rm "$STUB_LOG.tunnel-pids"
  (
    export CURL_STUB_EXIT=7
    run "$REPO_DIR/scripts/verify-vm.sh"
    assert_failure && assert_output --partial "verify tunnel is open" && [[ -s "$STUB_LOG.tunnel-pids" ]] || exit 1
    run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
    assert_failure
  ) || fail "CURL_STUB_EXIT=7: the failing verify never opened its tunnel or left it open"
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

@test "verify fails when the public IP accepts a connection or nc rejects its options, and treats refused, timed out and ICMP-rejected probes as closed" {
  local case code stderr expected
  # Each case: nc exit | nc stderr | the failure verify must report (empty: verify passes, the port counts as closed).
  # A host firewall may reject with icmp-host-prohibited, which nc reports as no route to host.
  for case in "0||accepts connections on port 22" \
    "1|nc: invalid option -- G|public port probe error on 203.0.113.10:22: nc: invalid option -- G" \
    "1|nc: connect to 203.0.113.10 port 22 (tcp) failed: Connection refused|" \
    "1|nc: connect to 203.0.113.10 port 22 (tcp) failed: Operation timed out|" \
    "1|nc: connect to 203.0.113.10 port 8737 (tcp) failed: No route to host|"; do
    IFS='|' read -r code stderr expected <<<"$case"
    (
      export NC_STUB_EXIT="$code" NC_STUB_STDERR="$stderr"
      run "$REPO_DIR/scripts/verify-vm.sh"
      if [[ -z "$expected" ]]; then
        assert_success
      else
        assert_failure && assert_output --partial "$expected"
      fi
    ) || fail "verify judged the public probe wrongly with nc exit $code and '$stderr'"
  done
}
