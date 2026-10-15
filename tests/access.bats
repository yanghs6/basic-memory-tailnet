#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl ssh nc
  use_vm_env
  unset BM_ACCESS
  export BM_ACCESS_CHECK_URL=https://tunnel.example.test/ CURL_STUB_HTTP_CODE=404
  ACCESS_CHECK="$REPO_DIR/scripts/access-check.sh"
  TUNNEL="$REPO_DIR/scripts/tunnel.sh"
}

# --- access-check ---

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

# --- every VM target ---

@test "a VM target that never reads the mode still stops on a BM_ACCESS it does not know before it runs ssh" {
  export BM_ACCESS=Ssh
  run "$REPO_DIR/scripts/logs.sh"
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'Ssh')"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
}

# --- tunnel ---

@test "tunnel forwards both ports on 127.0.0.1 only over the SSH alias and fails with the exit code when ssh ends" {
  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap SSH_STUB_TUNNEL_EXIT=255
  run "$TUNNEL"
  assert_failure
  assert_output --partial "MCP: http://127.0.0.1:18737/mcp  web UI: http://127.0.0.1:13000"
  assert_output --partial "tunnel closed (exit 255): rerun 'make tunnel'; check the ProxyCommand for agent-hub-iap"
  run grep -Fx 'ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:18737:127.0.0.1:8737 -L 127.0.0.1:13000:127.0.0.1:3000 ubuntu@agent-hub-iap' "$STUB_LOG"
  assert_success
}

@test "tunnel refuses the tailscale mode, a privileged port and a local port in use, before it runs ssh" {
  run "$TUNNEL"
  assert_failure
  assert_output --partial "make tunnel is for BM_ACCESS=ssh"

  export BM_ACCESS=ssh
  BM_TUNNEL_MCP_PORT=80 run "$TUNNEL"
  assert_failure
  assert_output --partial "BM_TUNNEL_MCP_PORT must be a port number from 1024 to 65535 (got '80')"

  NC_STUB_OPEN_MATCH=13000 run "$TUNNEL"
  assert_failure
  assert_output --partial "port 13000 is in use on 127.0.0.1: another 'make tunnel'? or set BM_TUNNEL_WEB_PORT in .env"

  run grep -F 'ssh -N' "$STUB_LOG"
  assert_failure
}
