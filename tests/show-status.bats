#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker free sudo tailscale
  use_vm_env
}

@test "status shows containers, memory and swap use, and warns only when no swap is active" {
  local case setting swap warning
  # Each case: the free stub setting | the swap line | the warning status must print (empty: none).
  for case in "FREE_STUB_SWAP_USED_MB=0|0/1023|" "FREE_STUB_SWAP_USED_MB=200|200/1023|" \
    "FREE_STUB_SWAP_TOTAL_MB=0|0/0|WARNING: no active swap on this 1GB VM"; do
    IFS='|' read -r setting swap warning <<<"$case"
    (
      run env "$setting" "$REPO_DIR/scripts/show-status.sh"
      assert_success \
        && assert_output --partial "basic-memory-server" \
        && assert_output --partial "memory used: 23%" \
        && assert_output --partial "swap used: $swap MB" \
        && assert_output --partial "proxy http://127.0.0.1:8737" || exit 1
      if [[ -z "$warning" ]]; then
        refute_output --partial "WARNING"
      else
        assert_output --partial "$warning"
      fi
    ) || fail "status with $setting"
  done
}

@test "ssh mode: status shows the access mode instead of Serve and warns while Tailscale is logged in on the VM" {
  use_ssh_mode
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "access: ssh"
  assert_output --partial "tailscale: not installed or logged out"
  refute_output --partial "proxy http://127.0.0.1:8737"
  export TS_STUB_BACKEND_STATE=Running
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "WARNING: Tailscale is still logged in on the VM; BM_ACCESS=ssh expects it off"
}

# make_gateway_store CLIENTS: a gateway store under the fake data root with CLIENTS client registrations next to other
# files that are not registrations. Prints its size in KiB, as du -sk reports it.
make_gateway_store() {
  local store="$BM_REMOTE_DATA_ROOT/gateway/oauth-proxy/fingerprint" n
  mkdir -p "$store/mcp-oauth-proxy-clients" "$store/mcp-oauth-proxy-transactions" || return 1
  for ((n = 1; n <= $1; n++)); do
    printf 'registration %s' "$n" >"$store/mcp-oauth-proxy-clients/client-$n.json" || return 1
  done
  printf 'transaction' >"$store/mcp-oauth-proxy-transactions/t.json" || return 1
  du -sk "$BM_REMOTE_DATA_ROOT/gateway" | cut -f1
}

@test "status with BM_WEB=on adds the gateway store size and the number of client registrations" {
  local kib
  use_web_env
  kib="$(make_gateway_store 3)"
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "gateway store: $kib KiB, 3 client registrations"
  assert_stub_called -F 'du -sk'
  assert_stub_called -F 'mcp-oauth-proxy-clients'
  refute_output --partial "$BM_WEB_HOST"
  refute_output --partial "test-client-secret"
}

@test "status with BM_WEB=on reports an empty store when the gateway has not run yet, and fails when the VM does not answer" {
  use_web_env
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "gateway store: 0 KiB, 0 client registrations"
  SSH_STUB_FAIL_MATCH="mcp-oauth-proxy-clients" run "$REPO_DIR/scripts/show-status.sh"
  assert_failure
  assert_output --partial "gateway store"
}

@test "status with BM_WEB=off or unset shows no gateway store line" {
  local web
  make_gateway_store 2 >/dev/null
  for web in "" off; do
    (
      export BM_WEB="$web"
      run "$REPO_DIR/scripts/show-status.sh"
      assert_success && refute_output --partial "gateway store" && refute_stub_called -F 'mcp-oauth-proxy-clients'
    ) || fail "status showed the gateway store with BM_WEB='$web'"
  done
}

@test "status stops on an unknown BM_WEB before it runs ssh" {
  BM_WEB=yes run "$REPO_DIR/scripts/show-status.sh"
  assert_failure
  assert_output --partial "BM_WEB must be on or off (got 'yes')"
  refute_stub_called -F 'ssh '
}

@test "status fails without a memory line and checks no access when free -m prints no Mem: or Swap: line or a zero memory total" {
  local free_output
  # Each case: what free -m prints on the VM (\n between lines).
  for free_output in 'Swap:  1023  0  1023' 'Mem:  3900  700  2200  5  1000  3000' 'Mem:  0  0  0  0  0  0\nSwap:  1023  0  1023'; do
    (
      : >"$STUB_LOG" && fake_cmd free "printf 'free %s\n' \"\$*\" >>\"\$STUB_LOG\"; printf '%b\n' '$free_output'" || exit 1
      run "$REPO_DIR/scripts/show-status.sh"
      assert_failure && assert_stub_called -Fx 'free -m' && refute_output --partial "memory used" \
        && refute_stub_called -F 'tailscale serve'
    ) || fail "status went on with free -m printing: $free_output"
  done
}
