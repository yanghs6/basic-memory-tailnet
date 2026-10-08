#!/usr/bin/env bash
# End-to-end check of a Basic Memory MCP endpoint over streamable HTTP:
# initialize -> tools/list -> write_note -> read_note -> delete_note.
# --read-only stops after tools/list and writes nothing (make probe, bm-diagnose).
# Usage: verify-mcp.sh [--host-header HOST] [--read-only] URL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PROTOCOL_VERSION="2025-06-18"
readonly REQUEST_TIMEOUT_SECONDS=30
readonly REQUIRED_TOOLS="write_note read_note search_notes delete_note"
readonly VERIFY_DIRECTORY="verify"
readonly VERIFY_ID="${VERIFY_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM}"

URL=""
HOST_HEADER=""
SESSION_ID=""
WORK_DIR=""
NOTE_WRITTEN=""
READ_ONLY=""

usage() { die "usage: verify-mcp.sh [--host-header HOST] [--read-only] URL"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --host-header)
        [[ -n "${2:-}" && "$2" != -* ]] || usage
        HOST_HEADER="$2"
        shift 2
        ;;
      --read-only)
        READ_ONLY=1
        shift
        ;;
      -*) usage ;;
      *)
        URL="$1"
        shift
        ;;
    esac
  done
  [[ -n "$URL" ]] || usage
}

# post PAYLOAD -> prints the HTTP status; response headers and body land in $WORK_DIR.
post() {
  local -a args=(-sS -m "$REQUEST_TIMEOUT_SECONDS" -D "$WORK_DIR/headers" -o "$WORK_DIR/body" -w '%{http_code}'
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    -H "MCP-Protocol-Version: $PROTOCOL_VERSION")
  if [[ -n "$HOST_HEADER" ]]; then
    args+=(-H "Host: $HOST_HEADER")
  fi
  if [[ -n "$SESSION_ID" ]]; then
    args+=(-H "Mcp-Session-Id: $SESSION_ID")
  fi
  curl "${args[@]}" -d "$1" "$URL"
}

# extract_message ID -> the JSON-RPC message with that id from a JSON or SSE response body.
extract_message() {
  local id="$1" body="$WORK_DIR/body"
  if grep -q '^data:' "$body"; then
    sed -n 's/^data: \{0,1\}//p' "$body" | jq -c --argjson id "$id" 'select(.id == $id)' | tail -n 1
  else
    jq -c --argjson id "$id" 'select(.id == $id)' "$body"
  fi
}

# rpc ID METHOD PARAMS_JSON -> prints the JSON-RPC result object.
rpc() {
  local id="$1" method="$2" params="$3" payload status message label="$2"
  if [[ "$method" == tools/call ]]; then
    label="$(jq -r '.name' <<<"$params")"
  fi
  payload="$(jq -cn --argjson id "$id" --arg method "$method" --argjson params "$params" \
    '{jsonrpc: "2.0", id: $id, method: $method, params: $params}')"
  status="$(post "$payload")" \
    || die "$label: request to $URL failed (is the server running? try 'make local-up' or 'make status')"
  [[ "$status" == 200 ]] || die "$label: HTTP $status from $URL: $(head -c 300 "$WORK_DIR/body")"
  message="$(extract_message "$id" 2>/dev/null)" \
    || die "$label: response is not JSON-RPC: $(head -c 300 "$WORK_DIR/body")"
  [[ -n "$message" ]] || die "$label: no response with id $id: $(head -c 300 "$WORK_DIR/body")"
  if jq -e 'has("error")' <<<"$message" >/dev/null; then
    die "$label: JSON-RPC error $(jq -c '.error' <<<"$message")"
  fi
  jq -c '.result' <<<"$message"
}

notify() {
  local method="$1" status
  status="$(post "$(jq -cn --arg method "$method" '{jsonrpc: "2.0", method: $method}')")" \
    || die "$method: request to $URL failed"
  [[ "$status" == 200 || "$status" == 202 ]] || die "$method: unexpected HTTP $status"
}

# call_tool ID NAME ARGUMENTS_JSON -> prints the tool's structured result object.
call_tool() {
  local id="$1" name="$2" arguments="$3" params result
  params="$(jq -cn --arg name "$name" --argjson arguments "$arguments" '{name: $name, arguments: $arguments}')"
  result="$(rpc "$id" tools/call "$params")" || exit 1
  if jq -e '.isError == true' <<<"$result" >/dev/null; then
    die "$name: tool error: $(jq -r '.content[0].text // ""' <<<"$result" | head -c 300)"
  fi
  jq -c '.structuredContent.result // (.content[0].text | fromjson)' <<<"$result"
}

initialize() {
  local params
  params="$(jq -cn --arg version "$PROTOCOL_VERSION" \
    '{protocolVersion: $version, capabilities: {}, clientInfo: {name: "bm-verify", version: "1"}}')"
  rpc 1 initialize "$params" >/dev/null
  SESSION_ID="$(grep -i '^mcp-session-id:' "$WORK_DIR/headers" | cut -d: -f2- | tr -d ' \r' || true)"
  log "initialized (session $(mask "${SESSION_ID:-none}"))"
  notify notifications/initialized
}

check_tools() {
  local result names tool
  result="$(rpc 2 tools/list '{}')" || exit 1
  names="$(jq -r '.tools[].name' <<<"$result")"
  for tool in $REQUIRED_TOOLS; do
    grep -qx "$tool" <<<"$names" \
      || die "tools/list: missing tool '$tool' (did the Basic Memory image change? see compose.yaml)"
  done
  log "tools/list ok"
}

check_write() {
  local title="$1" content="$2" arguments payload
  arguments="$(jq -cn --arg title "$title" --arg content "$content" --arg directory "$VERIFY_DIRECTORY" \
    '{title: $title, content: $content, directory: $directory, output_format: "json"}')"
  # Titles are unique per run, so a cleanup delete of a note that was never created only logs a WARNING.
  NOTE_WRITTEN="$title"
  payload="$(call_tool 3 write_note "$arguments")" || exit 1
  [[ "$(jq -r '.action' <<<"$payload")" == created ]] || die "write_note: expected action=created, got $payload"
  log "write_note ok ($VERIFY_DIRECTORY/$title)"
}

check_read() {
  local title="$1" marker="$2" payload
  payload="$(call_tool 4 read_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
  jq -e --arg marker "$marker" '.content | contains($marker)' <<<"$payload" >/dev/null \
    || die "read_note: content of '$title' does not contain '$marker'"
  log "read_note ok"
}

check_delete() {
  local title="$1" payload
  payload="$(call_tool 5 delete_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
  [[ "$(jq -r '.deleted' <<<"$payload")" == true ]] || die "delete_note: '$title' was not deleted: $payload"
  NOTE_WRITTEN=""
  log "delete_note ok"
}

cleanup() {
  local exit_code=$?
  if [[ -n "$NOTE_WRITTEN" ]]; then
    log "cleanup: deleting leftover note '$NOTE_WRITTEN'"
    (check_delete "$NOTE_WRITTEN") \
      || log "WARNING: could not delete '$NOTE_WRITTEN'; remove it from the $VERIFY_DIRECTORY/ folder by hand"
  fi
  rm -rf "$WORK_DIR"
  exit "$exit_code"
}

main() {
  parse_args "$@"
  require_cmd curl jq
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT
  local title="bm-verify-$VERIFY_ID" marker="bm-verify marker $VERIFY_ID"
  step "MCP round trip against $URL${HOST_HEADER:+ (Host: $HOST_HEADER)}"
  initialize
  check_tools
  if [[ -n "$READ_ONLY" ]]; then
    log "OK: MCP read-only probe passed (no notes written)"
    return 0
  fi
  check_write "$title" "$marker"
  check_read "$title" "$marker"
  check_delete "$title"
  log "OK: MCP round trip passed"
}

main "$@"
