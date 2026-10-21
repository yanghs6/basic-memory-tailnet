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

@test "access-check reports each path on this network and recommends ssh when only the tunnel endpoint answers" {
  export CURL_STUB_FAIL_MATCH=controlplane.tailscale.com
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "this network only: run it on every network your clients use"
  assert_output --partial "tailscale control plane: blocked (timeout)"
  assert_output --partial "tunnel endpoint https://tunnel.example.test/: reachable (HTTP 404)"
  assert_output --partial "recommendation for this network: ssh"
  run grep -F 'curl -sS -o /dev/null --max-time 8 -w %{http_code} https://controlplane.tailscale.com/' "$STUB_LOG"
  assert_success
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
}

@test "access-check asks for BM_ACCESS_CHECK_URL instead of calling the network hopeless when Tailscale is blocked and the tunnel was not checked" {
  unset BM_ACCESS_CHECK_URL
  export CURL_STUB_FAIL_MATCH=controlplane.tailscale.com
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "tunnel endpoint: not set (BM_ACCESS_CHECK_URL in .env)"
  assert_output --partial "recommendation for this network: tailscale is blocked here; set BM_ACCESS_CHECK_URL (.env.example) to check the ssh mode"
  refute_output --partial "neither works here"
}

@test "access-check recommends tailscale and says the ssh mode was not checked when the tunnel endpoint is not set" {
  unset BM_ACCESS_CHECK_URL
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "recommendation for this network: tailscale (the ssh mode was not checked: BM_ACCESS_CHECK_URL is not set)"
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
