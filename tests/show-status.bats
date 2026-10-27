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

# The gateway store layout of FastMCP 4.1.3 on py-key-value-aio 0.4.6: oauth-proxy/<key fingerprint>/ holds a directory
# per collection, named by the FileTreeV1 strategy (S_, the name with _ for -, then - and the first 8 hex of the name's
# sha256), and next to it that collection's metadata file <directory>-info.json.
CLIENTS_COLLECTION_DIR=S_mcp_oauth_proxy_clients-4db71f6a
TRANSACTIONS_COLLECTION_DIR=S_mcp_oauth_transactions-6f3deda7

# make_gateway_store CURRENT OLD: a gateway store under the fake data root with CURRENT client registrations under one key
# fingerprint and OLD under an older one (a former BM_WEB_JWT_KEY), next to collection metadata and transaction files
# that are not registrations. Prints its size in KiB, as du -sk reports it.
make_gateway_store() {
  local root="$BM_REMOTE_DATA_ROOT/gateway/oauth-proxy" entry dir n
  for entry in "0123abcd4567:$1" "89efcdab0123:$2"; do
    dir="$root/${entry%%:*}"
    mkdir -p "$dir/$CLIENTS_COLLECTION_DIR" "$dir/$TRANSACTIONS_COLLECTION_DIR" || return 1
    printf '{}' >"$dir/$CLIENTS_COLLECTION_DIR-info.json" || return 1
    printf '{}' >"$dir/$TRANSACTIONS_COLLECTION_DIR-info.json" || return 1
    printf 'transaction' >"$dir/$TRANSACTIONS_COLLECTION_DIR/t.json" || return 1
    for ((n = 1; n <= ${entry#*:}; n++)); do
      printf 'registration %s' "$n" >"$dir/$CLIENTS_COLLECTION_DIR/client-$n.json" || return 1
    done
  done
  du -sk "$BM_REMOTE_DATA_ROOT/gateway" | cut -f1
}

@test "status with BM_WEB=on adds the gateway store size and the client registrations under every key fingerprint" {
  local kib
  use_web_env
  kib="$(make_gateway_store 2 1)"
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "gateway store: $kib KiB, 3 client registrations"
  assert_stub_called -F "sudo -n test -d $BM_REMOTE_DATA_ROOT/gateway"
  assert_stub_called -F 'du -sk'
  refute_output --partial "$BM_WEB_HOST"
  refute_output --partial "test-client-secret"
}

@test "status with BM_WEB=on reports an empty store when the gateway has not run yet, and fails when the VM does not answer or refuses sudo" {
  use_web_env
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "gateway store: 0 KiB, 0 client registrations"
  SSH_STUB_FAIL_MATCH="S_mcp_oauth_proxy_clients" run "$REPO_DIR/scripts/show-status.sh"
  assert_failure
  assert_output --partial "gateway store"
  # sudo -n without a password rule: the store must not read as empty.
  fake_cmd sudo 'exit 1'
  run "$REPO_DIR/scripts/show-status.sh"
  assert_failure
  assert_output --partial "gateway store"
}

@test "status counts registrations with the pattern that gateway/test_gateway.py checks against a real registration" {
  local script_pattern test_pattern
  script_pattern="$(sed -n "s/^readonly GATEWAY_CLIENT_FILES_PATTERN='\(.*\)'$/\1/p" "$REPO_DIR/scripts/show-status.sh")"
  test_pattern="$(sed -n 's/^CLIENT_FILES_PATTERN = "\(.*\)"$/\1/p' "$REPO_DIR/gateway/test_gateway.py")"
  [[ -n "$script_pattern" && "$script_pattern" == "$test_pattern" ]] \
    || fail "GATEWAY_CLIENT_FILES_PATTERN in scripts/show-status.sh ('$script_pattern') must equal CLIENT_FILES_PATTERN in gateway/test_gateway.py ('$test_pattern')"
}

@test "status with BM_WEB=off or unset shows no gateway store line" {
  local web
  make_gateway_store 2 0 >/dev/null
  for web in "" off; do
    (
      export BM_WEB="$web"
      run "$REPO_DIR/scripts/show-status.sh"
      assert_success && refute_output --partial "gateway store" && refute_stub_called -F 'S_mcp_oauth_proxy_clients'
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
