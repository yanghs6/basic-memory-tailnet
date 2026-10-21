#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh swapon fallocate mkswap
  use_provision_env
  WRAPPER="$REPO_DIR/scripts/bootstrap-vm.sh"
}

@test "bootstrap-vm uploads the script and passes the key on stdin only" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-wrapper123 TS_STUB_STATUS_EXIT=1
  run "$WRAPPER" 203.0.113.10
  assert_success
  assert_output --partial "using auth key tske****"
  assert_output --partial "only then delete the firewall rule that opens port 22"
  refute_output --partial "tskey-auth-wrapper123"
  run grep -E 'root@203.0.113.10 cat > /tmp/bm-bootstrap\.[A-Za-z0-9]{6}$' "$STUB_LOG"
  assert_success
  run grep -F '/tmp/bm-bootstrap.sh' "$STUB_LOG"
  assert_failure
  remote_script="$(grep -oE '/tmp/bm-bootstrap\.[A-Za-z0-9]{6}' "$STUB_LOG" | head -n 1)"
  [[ -n "$remote_script" ]]
  [[ ! -e "$remote_script" ]]
  run grep -F 'tskey-auth-wrapper123' "$STUB_LOG"
  assert_failure
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-wrapper123"
}

@test "bootstrap-vm reads the key from the prompt when TS_AUTHKEY is unset" {
  export BM_VM_USER=root TS_STUB_STATUS_EXIT=1
  run bash -c 'printf "tskey-auth-prompt456\n" | "$0" 203.0.113.10' "$WRAPPER"
  assert_success
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-prompt456"
}

@test "bootstrap-vm says a failed run is safe to repeat" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x SSH_STUB_FAIL_MATCH="bash /tmp/bm-bootstrap."
  run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "it is safe to repeat"
  remote_script="$(grep -oE '/tmp/bm-bootstrap\.[A-Za-z0-9]{6}' "$STUB_LOG" | head -n 1)"
  [[ -n "$remote_script" ]]
  [[ ! -e "$remote_script" ]]
}

@test "bootstrap-vm refuses an unexpected temp path from the VM" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/usr/bin/env bash\necho "/tmp/x; touch pwned"\n' >"$BATS_TEST_TMPDIR/fakebin/mktemp"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/mktemp"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "unexpected temp path from mktemp"
  run grep -F 'cat > /tmp/x' "$STUB_LOG"
  assert_failure
}

@test "bootstrap-vm in ssh mode never asks for a key, passes the mode to the VM and points to make tunnel" {
  export BM_ACCESS=ssh BM_VM_USER=root TS_AUTHKEY=tskey-auth-ssh123
  run "$WRAPPER" agent-hub-iap </dev/null
  assert_success
  refute_output --partial "Tailscale auth key"
  refute_output --partial "using auth key"
  refute_output --partial tskey-auth-ssh123
  refute_output --partial "delete the firewall rule that opens port 22"
  assert_output --partial "make tunnel, then connect the agents"
  run grep -F 'sudo BM_ACCESS=ssh ' "$STUB_LOG"
  assert_success
  run grep -E '^tailscale ' "$STUB_LOG"
  assert_failure
}
