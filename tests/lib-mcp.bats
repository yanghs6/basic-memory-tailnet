#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs curl
  use_mcp_fixtures sse
  # shellcheck source=../scripts/lib/mcp.sh
  . "$REPO_DIR/scripts/lib/mcp.sh"
  MCP_URL=http://127.0.0.1:18737/mcp
  mcp_open
}

teardown() { mcp_close; }

@test "mcp_initialize in a subshell keeps the session id for the caller's later calls, and every request passes MCP_TIMEOUT_SECONDS to curl" {
  MCP_TIMEOUT_SECONDS=3
  (mcp_initialize bm-test) 2>/dev/null
  run mcp_call_tool 3 write_note '{"title":"t","content":"c","directory":"d"}'
  assert_success
  assert_equal "$(jq -r .action <<<"$output")" created
  assert_equal "$(grep -c -- ' -m 3 ' "$STUB_LOG")" 3
  assert_equal "$(grep -c 'Mcp-Session-Id: test-session-0123456789' "$STUB_LOG")" 2
}

@test "mcp_initialize fails in a subshell without ending the caller, and stores no session, when the endpoint is down" {
  export CURL_STUB_EXIT=7
  if (mcp_initialize bm-test) 2>/dev/null; then
    fail "initialize passed without a connection"
  fi
  [[ ! -s "$MCP_WORK_DIR/session" ]] || fail "a session id was stored"
}
