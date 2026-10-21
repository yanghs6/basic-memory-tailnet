#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl
  export VERIFY_ID=test1
  use_mcp_fixtures sse
  VERIFY="$REPO_DIR/scripts/verify-mcp.sh"
  URL=http://127.0.0.1:8737/mcp
}

@test "passes a full round trip against SSE responses and sends the session id on every later request" {
  run "$VERIFY" "$URL"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
  run grep -c 'Mcp-Session-Id: test-session-0123456789' "$STUB_LOG"
  assert_output 5
}

@test "passes a full round trip against plain JSON responses" {
  use_mcp_fixtures json
  run "$VERIFY" "$URL"
  assert_success
}

@test "never prints the full session id" {
  run "$VERIFY" "$URL"
  refute_output --partial "test-session-0123456789"
  assert_output --partial "session test****"
}

@test "logs 'no session id' unmasked when initialize returns no session header" {
  printf 'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n' >"$CURL_FIXTURES/headers.txt"
  run "$VERIFY" "$URL"
  assert_success
  assert_output --partial "no session id"
  refute_output --partial "session ****"
}

@test "sends the Host header on every request when --host-header is given" {
  run "$VERIFY" --host-header agent-hub.example.ts.net "$URL"
  assert_success
  run grep -c 'Host: agent-hub.example.ts.net' "$STUB_LOG"
  assert_output 6
}

@test "writes, reads and deletes the same uniquely named note" {
  run "$VERIFY" "$URL"
  assert_success
  run jq -r 'select(.method == "tools/call") | "\(.params.name) \(.params.arguments.title // .params.arguments.identifier)"' "$STUB_LOG.requests"
  assert_output $'write_note bm-verify-test1\nread_note bm-verify-test1\ndelete_note bm-verify-test1'
}

@test "fails with the server message when a tool reports an error" {
  cat >"$CURL_FIXTURES/call_write_note.body" <<'EOF'
event: message
data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Note already exists"}],"isError":true}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "write_note: tool error: Note already exists"
}

@test "fails when a required tool is missing" {
  cat >"$CURL_FIXTURES/tools_list.body" <<'EOF'
data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"write_note"},{"name":"read_note"},{"name":"search_notes"}]}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "tools/list: missing tool 'delete_note'"
}

@test "fails on a non-200 HTTP status" {
  echo 503 >"$CURL_FIXTURES/initialize.status"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "initialize: HTTP 503"
}

@test "fails on a JSON-RPC error response" {
  echo 'data: {"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid request"}}' >"$CURL_FIXTURES/initialize.body"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial 'initialize: JSON-RPC error {"code":-32600,"message":"Invalid request"}'
}

@test "deletes the note during cleanup when read-back fails" {
  cat >"$CURL_FIXTURES/call_read_note.body" <<'EOF'
data: {"jsonrpc":"2.0","id":4,"result":{"content":[],"isError":false,"structuredContent":{"result":{"title":"bm-verify-test1","content":"something else"}}}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "read_note: content of 'bm-verify-test1' does not contain 'bm-verify marker test1'"
  assert_output --partial "cleanup: deleting leftover note 'bm-verify-test1'"
  run grep -c '"name":"delete_note"' "$STUB_LOG.requests"
  assert_output 1
}

@test "deletes the note during cleanup when write_note fails after the server may have written it" {
  echo 500 >"$CURL_FIXTURES/call_write_note.status"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "write_note: HTTP 500"
  assert_output --partial "cleanup: deleting leftover note 'bm-verify-test1'"
  run grep -c '"name":"delete_note"' "$STUB_LOG.requests"
  assert_output 1
}

@test "explains how to start the server when curl cannot connect" {
  export CURL_STUB_EXIT=7
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "initialize: request to $URL failed"
}

@test "rejects --host-header followed by another option" {
  run "$VERIFY" --host-header --read-only "$URL"
  assert_failure
  assert_output --partial "usage: verify-mcp.sh"
}
