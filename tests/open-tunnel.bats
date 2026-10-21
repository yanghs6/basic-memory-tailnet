#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs curl ssh nc
  use_vm_env
  unset BM_ACCESS
  export BM_ACCESS_CHECK_URL=https://tunnel.example.test/ CURL_STUB_HTTP_CODE=404
  TUNNEL="$REPO_DIR/scripts/open-tunnel.sh"
}

@test "tunnel forwards both ports on 127.0.0.1 only over the SSH alias and fails with the exit code when ssh ends" {
  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap SSH_STUB_TUNNEL_EXIT=255
  run "$TUNNEL"
  assert_failure 255
  assert_output --partial "MCP: http://127.0.0.1:18737/mcp  web UI: http://127.0.0.1:13000"
  assert_output --partial "tunnel closed (exit 255): rerun 'make tunnel'; check the ProxyCommand for agent-hub-iap"
  assert_stub_called -Fx 'ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:18737:127.0.0.1:8737 -L 127.0.0.1:13000:127.0.0.1:3000 ubuntu@agent-hub-iap'
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

  refute_stub_called -F 'ssh -N'
}
