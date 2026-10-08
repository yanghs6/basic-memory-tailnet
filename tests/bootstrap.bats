#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh
  use_vm_env
  export ETC_DIR="$BATS_TEST_TMPDIR/etc" RUN_DIR="$BATS_TEST_TMPDIR/run"
  export OS_RELEASE="$REPO_DIR/tests/fixtures/os-release" ADMIN_USER=root
  mkdir -p "$RUN_DIR"
  BOOTSTRAP="$REPO_DIR/scripts/remote/bootstrap.sh"
  WRAPPER="$REPO_DIR/scripts/bootstrap-vm.sh"
}

run_bootstrap_with_key() {
  run bash -c 'printf "%s\n" "$1" | "$0"' "$BOOTSTRAP" "$1"
}

@test "installs docker from the official apt repo when docker is missing" {
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key tskey-auth-test123
  assert_success
  run grep -F 'apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' "$STUB_LOG"
  assert_success
  run cat "$ETC_DIR/apt/sources.list.d/docker.sources"
  assert_line "Suites: noble"
  assert_line "Architectures: arm64"
}

@test "skips the docker install when docker exists" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "docker already installed"
  run grep -F 'docker-ce' "$STUB_LOG"
  assert_failure
}

@test "adds the admin user to the docker group only when missing" {
  setup_stubs docker
  export ID_STUB_GROUPS="root"
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'usermod -aG docker root' "$STUB_LOG"
  assert_success

  : >"$STUB_LOG"
  export ID_STUB_GROUPS="root docker"
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'usermod' "$STUB_LOG"
  assert_failure
}

@test "installs tailscale with the official script when missing" {
  setup_stubs docker
  rm "$STUB_BIN/tailscale"
  export CURL_STUB_SCRIPT="ln -s $REPO_DIR/tests/stubs/tailscale $STUB_BIN/tailscale"
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'curl -fsSL https://tailscale.com/install.sh' "$STUB_LOG"
  assert_success
}

@test "joins the tailnet with the key in a temp file, never in argv" {
  setup_stubs docker
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key tskey-auth-secret987
  assert_success
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-secret987"
  run grep -F 'tskey-auth-secret987' "$STUB_LOG"
  assert_failure
  run grep -E 'tailscale up --auth-key=file:.* --hostname=bm-node --ssh' "$STUB_LOG"
  assert_success
  run ls -A "$RUN_DIR"
  assert_output ""
}

@test "removes the key file even when tailscale up fails" {
  setup_stubs docker
  export TS_STUB_STATUS_EXIT=1 TS_STUB_UP_EXIT=1
  run_bootstrap_with_key tskey-auth-rejected1
  assert_failure
  assert_output --partial "tailscale up failed"
  run ls -A "$RUN_DIR"
  assert_output ""
}

@test "fails with guidance when not on the tailnet and no key is given" {
  setup_stubs docker
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key ""
  assert_failure
  assert_output --partial "not on the tailnet and no auth key given"
}

@test "only refreshes hostname and Tailscale SSH when already on the tailnet" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'tailscale set --hostname=bm-node --ssh' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale up' "$STUB_LOG"
  assert_failure
}

@test "creates data dirs owned by the container uid and serves the loopback port" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
  run grep -F 'tailscale serve --bg http://127.0.0.1:8737' "$STUB_LOG"
  assert_success
}

@test "bootstrap-vm uploads the script and passes the key on stdin only" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-wrapper123 TS_STUB_STATUS_EXIT=1
  run "$WRAPPER" 203.0.113.10
  assert_success
  assert_output --partial "using auth key tske****"
  assert_output --partial "only then delete the OCI ingress rule for port 22"
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

@test "bootstrap-vm requires the public IP" {
  run "$WRAPPER"
  assert_failure
  assert_output --partial "usage: make vm-bootstrap HOST=<public-ip>"
}

@test "bootstrap-vm explains an upload failure" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x SSH_STUB_FAIL_MATCH="cat > /tmp/bm-bootstrap."
  run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "upload failed"
  run grep -F 'rm -f /tmp/bm-bootstrap.' "$STUB_LOG"
  assert_success
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
