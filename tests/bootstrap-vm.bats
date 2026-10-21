#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh swapon fallocate mkswap
  use_provision_env
  WRAPPER="$REPO_DIR/scripts/bootstrap-vm.sh"
}

@test "bootstrap-vm passes the key on stdin only, from TS_AUTHKEY or the prompt, and removes its remote script also after a failed run" {
  local case source key fail_match outcome remote_script
  export BM_VM_USER=root TS_STUB_STATUS_EXIT=1
  # Each case: where the key comes from | the key | the remote command that fails (empty: none) | the outcome.
  for case in "TS_AUTHKEY|tskey-auth-wrapper123||success" "prompt|tskey-auth-prompt456||success" \
    "TS_AUTHKEY|tskey-auth-x|bash /tmp/bm-bootstrap.|failure"; do
    IFS='|' read -r source key fail_match outcome <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      rm -f "$STUB_LOG.authkey" || exit 1
      export SSH_STUB_FAIL_MATCH="$fail_match"
      if [[ "$source" == prompt ]]; then
        run bash -c 'printf "%s\n" "$1" | "$0" 203.0.113.10' "$WRAPPER" "$key"
      else
        TS_AUTHKEY="$key" run "$WRAPPER" 203.0.113.10
      fi
      remote_script="$(grep -oE '/tmp/bm-bootstrap\.[A-Za-z0-9]{6}' "$STUB_LOG" | head -n 1)"
      refute_output --partial "$key" \
        && refute_stub_called -F "$key" \
        && assert_stub_called -E 'root@203.0.113.10 cat > /tmp/bm-bootstrap\.[A-Za-z0-9]{6}$' \
        && refute_stub_called -F '/tmp/bm-bootstrap.sh' \
        && [[ -n "$remote_script" && ! -e "$remote_script" ]] || exit 1
      if [[ "$outcome" == failure ]]; then
        assert_failure && assert_output --partial "bootstrap failed on the VM"
      else
        assert_success \
          && assert_output --partial "only then delete the firewall rule that opens port 22" \
          && assert_equal "$(cat "$STUB_LOG.authkey")" "$key"
      fi
    ) || fail "bootstrap-vm with the key $key from $source (expected $outcome)"
  done
}

@test "bootstrap-vm refuses an unexpected temp path from the VM" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x
  fake_cmd mktemp 'echo "/tmp/x; touch pwned"'
  run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "unexpected temp path from mktemp"
  refute_stub_called -F 'cat > /tmp/x'
}

@test "bootstrap-vm in ssh mode never asks for a key or touches Tailscale, passes the mode to the VM, still sets up docker and the data dirs and points to make tunnel" {
  export BM_ACCESS=ssh BM_VM_USER=root TS_AUTHKEY=tskey-auth-ssh123
  run "$WRAPPER" agent-hub-iap </dev/null
  assert_success
  refute_output --partial "Tailscale auth key"
  refute_output --partial "using auth key"
  refute_output --partial tskey-auth-ssh123
  refute_output --partial "delete the firewall rule that opens port 22"
  assert_output --partial "access mode ssh: skipping Tailscale"
  assert_output --partial "make tunnel, then connect the agents"
  assert_stub_called -F 'sudo BM_ACCESS=ssh '
  refute_stub_called -E '^tailscale |tailscale\.com/install\.sh'
  # No docker stub in this file: the VM script installs docker from the official apt repo.
  assert_stub_called -F 'docker-ce'
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
}
