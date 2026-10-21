#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh swapon fallocate mkswap docker
  use_provision_env
  BOOTSTRAP="$REPO_DIR/scripts/remote/provision-vm.sh"
}

run_bootstrap_with_key() {
  run bash -c 'printf "%s\n" "$1" | "$0"' "$BOOTSTRAP" "$1"
}

@test "installs tailscale with the official script and sets up swap before it installs docker from the official apt repo" {
  export TS_STUB_STATUS_EXIT=1
  rm "$STUB_BIN/docker" "$STUB_BIN/tailscale"
  export CURL_STUB_SCRIPT="ln -s $REPO_DIR/tests/stubs/tailscale $STUB_BIN/tailscale"
  run_bootstrap_with_key tskey-auth-test123
  assert_success
  assert_stub_called -F 'curl -fsSL https://tailscale.com/install.sh'
  run cat "$STUB_LOG"
  assert_line --index 0 "swapon --show --noheadings"
  assert_log_order "swapon $SWAP_FILE" "apt-get"
  assert_stub_called -F 'apt-get -o DPkg::Lock::Timeout=300 install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
  # Every apt-get call waits for the dpkg lock that unattended-upgrades holds right after first boot.
  run bash -c 'grep "^apt-get " "$0" | grep -vF -- "apt-get -o DPkg::Lock::Timeout=300 "' "$STUB_LOG"
  assert_failure
  run cat "$ETC_DIR/apt/sources.list.d/docker.sources"
  assert_line "Suites: noble"
  assert_line "Architectures: arm64"
}

@test "joins the tailnet with the key in a temp file that it removes, also when tailscale up fails" {
  local case up_exit key outcome
  export TS_STUB_STATUS_EXIT=1
  # Each case: the exit code of tailscale up | the key | the outcome.
  for case in "0|tskey-auth-secret987|success" "1|tskey-auth-rejected1|failure"; do
    IFS='|' read -r up_exit key outcome <<<"$case"
    (
      : >"$STUB_LOG"
      rm -f "$STUB_LOG.authkey"
      export TS_STUB_UP_EXIT="$up_exit"
      run_bootstrap_with_key "$key"
      if [[ "$outcome" == success ]]; then
        assert_success
      else
        assert_failure && assert_output --partial "tailscale up failed"
      fi || exit 1
      assert_equal "$(cat "$STUB_LOG.authkey")" "$key" \
        && refute_stub_called -F "$key" \
        && assert_stub_called -E 'tailscale up --auth-key=file:.* --hostname=agent-hub --ssh' \
        && assert_equal "$(ls -A "$RUN_DIR")" ""
    ) || fail "provision-vm with tailscale up exiting $up_exit"
  done
}

@test "fails with guidance when not on the tailnet and no key is given" {
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key ""
  assert_failure
  assert_output --partial "not on the tailnet and no auth key given"
}

@test "on a host already on the tailnet it skips the docker install, refreshes only hostname and Tailscale SSH, creates data dirs owned by the container uid and serves both loopback ports" {
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "docker already installed"
  refute_stub_called -F 'docker-ce'
  assert_stub_called -F 'tailscale set --hostname=agent-hub --ssh'
  refute_stub_called -F 'tailscale up'
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
  assert_stub_called -F 'tailscale serve --bg http://127.0.0.1:8737'
  assert_stub_called -F 'tailscale serve --bg --https=8443 http://127.0.0.1:3000'
  assert_stub_called -Fx 'tailscale serve status'
}

@test "fails when Serve is not active, misses the 8443 mapping or has Funnel on" {
  local case setting expected
  for case in "TS_STUB_SERVE_EMPTY=1|Serve is not active" "TS_STUB_SERVE_8443=|Serve is not active" \
    "TS_STUB_FUNNEL=on|Funnel is on for this node"; do
    IFS='|' read -r setting expected <<<"$case"
    (
      export "${setting?}"
      run_bootstrap_with_key ""
      assert_failure && assert_output --partial "$expected" && refute_output --partial "done"
    ) || fail "provision-vm went on with $setting"
  done
}

@test "creates, formats and enables a swap file once and keeps other fstab entries, even when run twice" {
  local entry expected
  # Each case: the fstab line already there (empty: no fstab yet).
  for entry in "" "UUID=abc / ext4 defaults 0 1"; do
    (
      : >"$STUB_LOG"
      rm -f "$ETC_DIR/fstab" "$SWAP_FILE"
      if [[ -n "$entry" ]]; then
        printf '%s\n' "$entry" >"$ETC_DIR/fstab"
      fi
      run_bootstrap_with_key ""
      assert_success \
        && assert_stub_called -F "fallocate -l 1024M $SWAP_FILE" \
        && assert_stub_called -F "mkswap $SWAP_FILE" \
        && assert_stub_called -F "swapon $SWAP_FILE" \
        && assert_equal "$(stat -c %a "$SWAP_FILE")" 600 || exit 1
      run_bootstrap_with_key ""
      assert_success || exit 1
      expected="$SWAP_FILE none swap sw 0 0"
      if [[ -n "$entry" ]]; then
        expected="$entry"$'\n'"$expected"
      fi
      assert_equal "$(cat "$ETC_DIR/fstab")" "$expected"
    ) || fail "swap setup with the fstab line '$entry' already there"
  done
}

@test "writes no fstab line when swap is already active or swapon fails" {
  local case setting outcome message
  # Each case: the swapon stub setting | the outcome | the message that tells which branch ran.
  for case in "SWAPON_STUB_ACTIVE=/dev/sda2 partition 1G 0B -2|success|swap already active" \
    "SWAPON_STUB_EXIT=1|failure|swapon failed"; do
    IFS='|' read -r setting outcome message <<<"$case"
    (
      : >"$STUB_LOG"
      export "${setting?}"
      run_bootstrap_with_key ""
      if [[ "$outcome" == success ]]; then
        assert_success && refute_stub_called -E 'fallocate|mkswap' && refute_stub_called -F "swapon $SWAP_FILE"
      else
        assert_failure
      fi && assert_output --partial "$message" && [[ ! -e "$ETC_DIR/fstab" ]]
    ) || fail "provision-vm wrote an fstab line or took the wrong branch with $setting"
  done
}
