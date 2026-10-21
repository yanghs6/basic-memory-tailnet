#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl
  export VERIFY_ID=test1
  use_mcp_fixtures sse
  VERIFY="$REPO_DIR/scripts/verify-mcp.sh"
  URL=http://127.0.0.1:8737/mcp
}

@test "passes a full round trip against SSE and JSON responses, sends the session id and the Host header on every later request, never prints the full session id and writes, reads and deletes the same note" {
  local case kind host
  # Each case: the fixture kind | the --host-header value (empty: none).
  for case in "sse|" "json|" "sse|agent-hub.example.ts.net"; do
    IFS='|' read -r kind host <<<"$case"
    (
      : >"$STUB_LOG"
      rm -rf "$BATS_TEST_TMPDIR/mcp-$kind" "$STUB_LOG.requests"
      use_mcp_fixtures "$kind"
      run "$VERIFY" ${host:+--host-header "$host"} "$URL"
      assert_success \
        && assert_output --partial "OK: MCP round trip passed" \
        && refute_output --partial "test-session-0123456789" \
        && assert_equal "$(grep -c 'Mcp-Session-Id: test-session-0123456789' "$STUB_LOG")" 5 \
        && assert_equal "$(jq -r 'select(.method == "tools/call") | "\(.params.name) \(.params.arguments.title // .params.arguments.identifier)"' "$STUB_LOG.requests")" \
          $'write_note bm-verify-test1\nread_note bm-verify-test1\ndelete_note bm-verify-test1' || exit 1
      if [[ -n "$host" ]]; then
        assert_equal "$(grep -c "Host: $host" "$STUB_LOG")" 6
      fi
    ) || fail "verify-mcp round trip against $kind responses${host:+ with --host-header $host}"
  done
}

@test "logs 'no session id' unmasked when initialize returns no session header" {
  printf 'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n' >"$CURL_FIXTURES/headers.txt"
  run "$VERIFY" "$URL"
  assert_success
  assert_output --partial "no session id"
  refute_output --partial "session ****"
}

@test "fails on a missing tool, a non-200 status, a JSON-RPC error or no connection" {
  local fault expected
  for fault in missing-tool http-503 json-rpc-error no-connection; do
    (
      rm -rf "$CURL_FIXTURES"
      use_mcp_fixtures sse
      case "$fault" in
        missing-tool)
          echo 'data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"write_note"},{"name":"read_note"},{"name":"search_notes"}]}}' >"$CURL_FIXTURES/tools_list.body"
          expected="tools/list: missing tool 'delete_note'"
          ;;
        http-503)
          echo 503 >"$CURL_FIXTURES/initialize.status"
          expected="initialize: HTTP 503"
          ;;
        json-rpc-error)
          echo 'data: {"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid request"}}' >"$CURL_FIXTURES/initialize.body"
          expected='initialize: JSON-RPC error {"code":-32600,"message":"Invalid request"}'
          ;;
        no-connection)
          export CURL_STUB_EXIT=7
          expected="initialize: request to $URL failed"
          ;;
      esac
      run "$VERIFY" "$URL"
      assert_failure && assert_output --partial "$expected"
    ) || fail "verify-mcp did not stop at the expected step for: $fault"
  done
}

@test "deletes the leftover note during cleanup when write_note fails or reports an error, or the read-back does not match" {
  local fault expected
  for fault in write-http-500 write-tool-error read-mismatch; do
    (
      rm -rf "$CURL_FIXTURES" "$STUB_LOG.requests"
      use_mcp_fixtures sse
      case "$fault" in
        write-http-500)
          echo 500 >"$CURL_FIXTURES/call_write_note.status"
          expected="write_note: HTTP 500"
          ;;
        write-tool-error)
          printf 'event: message\ndata: %s\n' '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Note already exists"}],"isError":true}}' \
            >"$CURL_FIXTURES/call_write_note.body"
          expected="write_note: tool error: Note already exists"
          ;;
        read-mismatch)
          echo 'data: {"jsonrpc":"2.0","id":4,"result":{"content":[],"isError":false,"structuredContent":{"result":{"title":"bm-verify-test1","content":"something else"}}}}' >"$CURL_FIXTURES/call_read_note.body"
          expected="read_note: content of 'bm-verify-test1' does not contain 'bm-verify marker test1'"
          ;;
      esac
      run "$VERIFY" "$URL"
      assert_failure \
        && assert_output --partial "$expected" \
        && assert_output --partial "cleanup: deleting leftover note 'bm-verify-test1'" \
        && assert_equal "$(grep -c '"name":"delete_note"' "$STUB_LOG.requests")" 1
    ) || fail "verify-mcp did not clean up after: $fault"
  done
}
