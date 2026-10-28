#!/usr/bin/env bash
# MCP client helpers for scripts/*.sh: streamable HTTP, the session and tool calls, shared by verify-mcp.sh and the
# agent memory scripts. Sources common.sh. Must stay compatible with macOS bash 3.2.
# The caller sets MCP_URL (required), MCP_HOST_HEADER (optional) and MCP_TIMEOUT_SECONDS (default 30), then calls mcp_open.
#   mcp_open -> create MCP_WORK_DIR, which holds the last response and the session id
#   mcp_close -> remove MCP_WORK_DIR
#   mcp_post PAYLOAD -> prints the HTTP status; response headers and body land in MCP_WORK_DIR
#   mcp_extract_message ID -> the JSON-RPC message with that id from a JSON or SSE response body
#   mcp_rpc ID METHOD PARAMS_JSON -> prints the JSON-RPC result object; dies on any failure
#   mcp_notify METHOD -> sends a notification; dies unless the server accepts it
#   mcp_call_tool ID NAME ARGUMENTS_JSON -> prints the tool's structured result object; dies on a tool error
#   mcp_initialize CLIENT_NAME -> initializes the session, stores its id in MCP_WORK_DIR/session and logs it masked
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_MCP:-}" ] && return 0
readonly _BM_LIB_MCP=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

readonly MCP_PROTOCOL_VERSION="2025-06-18"
readonly MCP_DEFAULT_TIMEOUT_SECONDS=30
# How much of an unexpected response an error message shows.
readonly MCP_PREVIEW_BYTES=300

MCP_WORK_DIR=""

mcp_open() {
  MCP_WORK_DIR="$(mktemp -d)" || exit 1
}

mcp_close() {
  [[ -z "$MCP_WORK_DIR" ]] || rm -rf "$MCP_WORK_DIR"
}

mcp_post() {
  local -a args=(-sS -m "${MCP_TIMEOUT_SECONDS:-$MCP_DEFAULT_TIMEOUT_SECONDS}"
    -D "$MCP_WORK_DIR/headers" -o "$MCP_WORK_DIR/body" -w '%{http_code}'
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    -H "MCP-Protocol-Version: $MCP_PROTOCOL_VERSION")
  if [[ -n "${MCP_HOST_HEADER:-}" ]]; then
    args+=(-H "Host: $MCP_HOST_HEADER")
  fi
  if [[ -s "$MCP_WORK_DIR/session" ]]; then
    args+=(-H "Mcp-Session-Id: $(cat "$MCP_WORK_DIR/session")")
  fi
  curl "${args[@]}" -d "$1" "$MCP_URL"
}

mcp_extract_message() {
  local id="$1" body="$MCP_WORK_DIR/body"
  if grep -q '^data:' "$body"; then
    sed -n 's/^data: \{0,1\}//p' "$body" | jq -c --argjson id "$id" 'select(.id == $id)' | tail -n 1
  else
    jq -c --argjson id "$id" 'select(.id == $id)' "$body"
  fi
}

mcp_rpc() {
  local id="$1" method="$2" params="$3" payload status message label="$2"
  if [[ "$method" == tools/call ]]; then
    label="$(jq -r '.name' <<<"$params")"
  fi
  payload="$(jq -cn --argjson id "$id" --arg method "$method" --argjson params "$params" \
    '{jsonrpc: "2.0", id: $id, method: $method, params: $params}')"
  status="$(mcp_post "$payload")" \
    || die "$label: request to $MCP_URL failed (is the server running? try 'make local-up' or 'make status')"
  [[ "$status" == 200 ]] || die "$label: HTTP $status from $MCP_URL: $(head -c "$MCP_PREVIEW_BYTES" "$MCP_WORK_DIR/body")"
  message="$(mcp_extract_message "$id" 2>/dev/null)" \
    || die "$label: response is not JSON-RPC: $(head -c "$MCP_PREVIEW_BYTES" "$MCP_WORK_DIR/body")"
  [[ -n "$message" ]] || die "$label: no response with id $id: $(head -c "$MCP_PREVIEW_BYTES" "$MCP_WORK_DIR/body")"
  if jq -e 'has("error")' <<<"$message" >/dev/null; then
    die "$label: JSON-RPC error $(jq -c '.error' <<<"$message")"
  fi
  jq -c '.result' <<<"$message"
}

mcp_notify() {
  local method="$1" status
  status="$(mcp_post "$(jq -cn --arg method "$method" '{jsonrpc: "2.0", method: $method}')")" \
    || die "$method: request to $MCP_URL failed"
  [[ "$status" == 200 || "$status" == 202 ]] || die "$method: unexpected HTTP $status"
}

mcp_call_tool() {
  local id="$1" name="$2" arguments="$3" params result
  params="$(jq -cn --arg name "$name" --argjson arguments "$arguments" '{name: $name, arguments: $arguments}')"
  result="$(mcp_rpc "$id" tools/call "$params")" || exit 1
  if jq -e '.isError == true' <<<"$result" >/dev/null; then
    die "$name: tool error: $(jq -r '.content[0].text // ""' <<<"$result" | head -c "$MCP_PREVIEW_BYTES")"
  fi
  jq -c '.structuredContent.result // (.content[0].text | fromjson)' <<<"$result" \
    || die "$name: unexpected result: $(head -c "$MCP_PREVIEW_BYTES" <<<"$result")"
}

mcp_initialize() {
  local client_name="$1" params session_id
  params="$(jq -cn --arg version "$MCP_PROTOCOL_VERSION" --arg name "$client_name" \
    '{protocolVersion: $version, capabilities: {}, clientInfo: {name: $name, version: "1"}}')"
  mcp_rpc 1 initialize "$params" >/dev/null || exit 1
  session_id="$(grep -i '^mcp-session-id:' "$MCP_WORK_DIR/headers" | cut -d: -f2- | tr -d ' \r' || true)"
  if [[ -n "$session_id" ]]; then
    printf '%s' "$session_id" >"$MCP_WORK_DIR/session"
    log "initialized (session $(mask "$session_id"))"
  else
    log "initialized (no session id)"
  fi
  mcp_notify notifications/initialized
}
