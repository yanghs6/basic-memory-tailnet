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
