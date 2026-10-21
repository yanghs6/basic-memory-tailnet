#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh swapon fallocate mkswap
  use_provision_env
  BOOTSTRAP="$REPO_DIR/scripts/remote/provision-vm.sh"
}

run_bootstrap_with_key() {
  run bash -c 'printf "%s\n" "$1" | "$0"' "$BOOTSTRAP" "$1"
}

@test "installs tailscale with the official script and sets up swap before it installs docker from the official apt repo" {
  export TS_STUB_STATUS_EXIT=1
  rm "$STUB_BIN/tailscale"
  export CURL_STUB_SCRIPT="ln -s $REPO_DIR/tests/stubs/tailscale $STUB_BIN/tailscale"
  run_bootstrap_with_key tskey-auth-test123
  assert_success
  run grep -F 'curl -fsSL https://tailscale.com/install.sh' "$STUB_LOG"
  assert_success
  run cat "$STUB_LOG"
  assert_line --index 0 "swapon --show --noheadings"
  local swap_line apt_line
  swap_line="$(grep -nF "swapon $SWAP_FILE" "$STUB_LOG" | head -n 1 | cut -d: -f1)"
  apt_line="$(grep -nF "apt-get" "$STUB_LOG" | head -n 1 | cut -d: -f1)"
  ((swap_line < apt_line))
  run grep -F 'apt-get -o DPkg::Lock::Timeout=300 install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' "$STUB_LOG"
  assert_success
  # Every apt-get call waits for the dpkg lock that unattended-upgrades holds right after first boot.
  run bash -c 'grep "^apt-get " "$0" | grep -vF -- "apt-get -o DPkg::Lock::Timeout=300 "' "$STUB_LOG"
  assert_failure
  run cat "$ETC_DIR/apt/sources.list.d/docker.sources"
  assert_line "Suites: noble"
  assert_line "Architectures: arm64"
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
  run grep -E 'tailscale up --auth-key=file:.* --hostname=agent-hub --ssh' "$STUB_LOG"
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

@test "on a host already on the tailnet it skips the docker install, refreshes only hostname and Tailscale SSH, creates data dirs owned by the container uid and serves both loopback ports" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "docker already installed"
  run grep -F 'docker-ce' "$STUB_LOG"
  assert_failure
  run grep -F 'tailscale set --hostname=agent-hub --ssh' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale up' "$STUB_LOG"
  assert_failure
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
  run grep -F 'tailscale serve --bg http://127.0.0.1:8737' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale serve --bg --https=8443 http://127.0.0.1:3000' "$STUB_LOG"
  assert_success
  run grep -Fx 'tailscale serve status' "$STUB_LOG"
  assert_success
}

@test "fails with HTTPS guidance when Serve is not active after setup, also when only the 8443 mapping is missing" {
  local case
  setup_stubs docker
  for case in "TS_STUB_SERVE_EMPTY=1" "TS_STUB_SERVE_8443="; do
    # shellcheck disable=SC2016 # $0 expands in the inner bash, not here
    run env "$case" bash -c 'printf "\n" | "$0"' "$BOOTSTRAP"
    assert_failure
    assert_output --partial "Serve is not active"
    assert_output --partial "enable MagicDNS and HTTPS certificates"
    refute_output --partial "done"
  done
}

@test "fails when the Serve config has Funnel on" {
  setup_stubs docker
  export TS_STUB_FUNNEL=on
  run_bootstrap_with_key ""
  assert_failure
  assert_output --partial "Funnel is on for this node"
  refute_output --partial "done"
}

@test "ssh mode skips the Tailscale install, join and Serve but still sets up docker and the data dirs" {
  export BM_ACCESS=ssh
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "access mode ssh: skipping Tailscale"
  run grep -E '^tailscale |tailscale\.com/install\.sh' "$STUB_LOG"
  assert_failure
  run grep -F 'docker-ce' "$STUB_LOG"
  assert_success
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
}

@test "creates, formats and enables a swap file when no swap is active" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  run grep -F "fallocate -l 1024M $SWAP_FILE" "$STUB_LOG"
  assert_success
  run grep -F "mkswap $SWAP_FILE" "$STUB_LOG"
  assert_success
  run grep -F "swapon $SWAP_FILE" "$STUB_LOG"
  assert_success
  [[ "$(stat -c %a "$SWAP_FILE")" == 600 ]]
  run cat "$ETC_DIR/fstab"
  assert_output "$SWAP_FILE none swap sw 0 0"
}

@test "skips the swap setup when swap is already active" {
  setup_stubs docker
  export SWAPON_STUB_ACTIVE="/dev/sda2 partition 1G 0B -2"
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "swap already active"
  run grep -E 'fallocate|mkswap' "$STUB_LOG"
  assert_failure
  run grep -F "swapon $SWAP_FILE" "$STUB_LOG"
  assert_failure
  [[ ! -e "$ETC_DIR/fstab" ]]
}

@test "keeps other fstab entries and a single swap line after them, even when run twice" {
  setup_stubs docker
  printf 'UUID=abc / ext4 defaults 0 1\n' >"$ETC_DIR/fstab"
  run_bootstrap_with_key ""
  assert_success
  run_bootstrap_with_key ""
  assert_success
  run cat "$ETC_DIR/fstab"
  assert_line --index 0 "UUID=abc / ext4 defaults 0 1"
  assert_line --index 1 "$SWAP_FILE none swap sw 0 0"
  assert_equal "${#lines[@]}" 2
}

@test "fails and writes no fstab line when swapon fails" {
  setup_stubs docker
  export SWAPON_STUB_EXIT=1
  run_bootstrap_with_key ""
  assert_failure
  assert_output --partial "swapon failed"
  [[ ! -e "$ETC_DIR/fstab" ]]
}
