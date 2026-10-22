#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs curl ssh nc
  use_vm_env
  unset BM_ACCESS
  export BM_ACCESS_CHECK_URL=https://tunnel.example.test/ CURL_STUB_HTTP_CODE=404
  ACCESS_CHECK="$REPO_DIR/scripts/check-access.sh"
}

@test "access-check recommends the mode that works on this network, or asks for BM_ACCESS_CHECK_URL when Tailscale is blocked and the tunnel was not checked" {
  local case blocked url control tunnel recommendation
  # Each case: the host curl cannot reach | BM_ACCESS_CHECK_URL | the control plane state | the tunnel endpoint line |
  # the recommendation.
  for case in \
    "controlplane.tailscale.com|https://tunnel.example.test/|blocked (timeout)|tunnel endpoint https://tunnel.example.test/: reachable (HTTP 404)|ssh" \
    "controlplane.tailscale.com||blocked (timeout)|tunnel endpoint: not set (BM_ACCESS_CHECK_URL in .env)|tailscale is blocked here; set BM_ACCESS_CHECK_URL (.env.example) to check the ssh mode" \
    "||reachable (HTTP 404)|tunnel endpoint: not set (BM_ACCESS_CHECK_URL in .env)|tailscale (the ssh mode was not checked: BM_ACCESS_CHECK_URL is not set)"; do
    IFS='|' read -r blocked url control tunnel recommendation <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      export CURL_STUB_FAIL_MATCH="$blocked" BM_ACCESS_CHECK_URL="$url"
      run "$ACCESS_CHECK"
      assert_success \
        && assert_output --partial "this network only: run it on every network your clients use" \
        && assert_output --partial "tailscale control plane: $control" \
        && assert_output --partial "$tunnel" \
        && assert_output --partial "recommendation for this network: $recommendation" \
        && refute_output --partial "neither works here" \
        && assert_stub_called -F 'curl -sS -o /dev/null --max-time 8 -w %{http_code} https://controlplane.tailscale.com/' \
        && refute_stub_called -F 'ssh '
    ) || fail "access-check with CURL_STUB_FAIL_MATCH='$blocked' and BM_ACCESS_CHECK_URL='$url'"
  done
}

@test "access-check fails only when the mode chosen in BM_ACCESS does not work on this network" {
  export CURL_STUB_FAIL_MATCH=controlplane.tailscale.com CURL_STUB_FAIL_EXIT=6 BM_ACCESS=tailscale
  run "$ACCESS_CHECK"
  assert_failure
  assert_output --partial "tailscale control plane: blocked (dns)"
  assert_output --partial "BM_ACCESS=tailscale does not work on this network"

  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "ssh ubuntu@agent-hub-iap: ok"

  export SSH_STUB_FAIL_MATCH=true
  run "$ACCESS_CHECK"
  assert_failure
  assert_output --partial "ssh ubuntu@agent-hub-iap: failed: check the ProxyCommand for agent-hub-iap in ~/.ssh/config"
}
