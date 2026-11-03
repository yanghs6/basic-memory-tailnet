#!/usr/bin/env bash
# End-to-end check of a Basic Memory MCP endpoint over streamable HTTP:
# initialize -> tools/list -> search_notes (a hybrid search must answer that semantic search is off) -> write_note ->
# read_note -> delete_note.
# --read-only stops after the search_notes check and writes nothing (make probe, bm-diagnose).
# Usage: verify-mcp.sh [--host-header HOST] [--read-only] URL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/mcp.sh
. "$SCRIPT_DIR/lib/mcp.sh"

readonly REQUIRED_TOOLS="write_note read_note search_notes delete_note"
readonly VERIFY_DIRECTORY="verify"
# The query of the semantic search probe: matches no note, so a server with semantic search on answers an empty result.
readonly SEMANTIC_PROBE_QUERY="bm-verify-semantic-probe"
# What Basic Memory 0.23.2 answers to a hybrid search while semantic search is off (mcp/tools/search.py).
readonly SEMANTIC_DISABLED_TEXT="Semantic Search Disabled"
VERIFY_ID="${VERIFY_ID:-$(utc_stamp)-$RANDOM}" || exit 1
readonly VERIFY_ID

MCP_URL=""
MCP_HOST_HEADER=""
NOTE_WRITTEN=""
READ_ONLY=""

usage_text() { printf 'usage: verify-mcp.sh [--host-header HOST] [--read-only] URL'; }

usage() { die "$(usage_text)"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --host-header)
        [[ -n "${2:-}" && "$2" != -* ]] || usage
        MCP_HOST_HEADER="$2"
        shift 2
        ;;
      --read-only)
        READ_ONLY=1
        shift
        ;;
      -*) usage ;;
      *)
        [[ -z "$MCP_URL" ]] || die "only one URL is allowed (got '$MCP_URL' and '$1'): $(usage_text)"
        MCP_URL="$1"
        shift
        ;;
    esac
  done
  [[ -n "$MCP_URL" ]] || usage
}

check_tools() {
  local result names tool
  result="$(mcp_rpc 2 tools/list '{}')" || exit 1
  names="$(jq -r '.tools[].name' <<<"$result")" \
    || die "tools/list: unexpected result: $(head -c "$MCP_PREVIEW_BYTES" <<<"$result")"
  for tool in $REQUIRED_TOOLS; do
    grep -qx "$tool" <<<"$names" \
      || die "tools/list: missing tool '$tool' (did the Basic Memory image change? see compose.yaml)"
  done
  log "tools/list ok"
}

# check_semantic_search_off -> dies unless a hybrid search_notes answers that semantic search is disabled. Writes
# nothing. With it on, writes stall the 1 GB VM (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md).
check_semantic_search_off() {
  local arguments payload
  arguments="$(jq -cn --arg query "$SEMANTIC_PROBE_QUERY-$VERIFY_ID" '{query: $query, search_type: "hybrid", output_format: "json"}')"
  payload="$(mcp_call_tool 6 search_notes "$arguments")" || exit 1
  jq -e --arg text "$SEMANTIC_DISABLED_TEXT" 'type == "string" and contains($text)' <<<"$payload" >/dev/null \
    || die "search_notes: a hybrid search did not answer that semantic search is disabled: check BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED in compose.yaml and the image version, then follow bm-diagnose (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md)"
  log "semantic search off ok"
}

check_write() {
  local title="$1" content="$2" arguments payload
  arguments="$(jq -cn --arg title "$title" --arg content "$content" --arg directory "$VERIFY_DIRECTORY" \
    '{title: $title, content: $content, directory: $directory, output_format: "json"}')"
  # Titles are unique per run, so a cleanup delete of a note that was never created only logs a WARNING.
  NOTE_WRITTEN="$title"
  payload="$(mcp_call_tool 3 write_note "$arguments")" || exit 1
  [[ "$(jq -r '.action' <<<"$payload")" == created ]] || die "write_note: expected action=created, got $payload"
  log "write_note ok ($VERIFY_DIRECTORY/$title)"
}

check_read() {
  local title="$1" marker="$2" payload
  payload="$(mcp_call_tool 4 read_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
  jq -e --arg marker "$marker" '.content | contains($marker)' <<<"$payload" >/dev/null \
    || die "read_note: content of '$title' does not contain '$marker'"
  log "read_note ok"
}

check_delete() {
  local title="$1" payload
  payload="$(mcp_call_tool 5 delete_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
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
  mcp_close
  exit "$exit_code"
}

main() {
  parse_args "$@"
  require_cmd curl jq
  mcp_open
  trap cleanup EXIT
  local title="bm-verify-$VERIFY_ID" marker="bm-verify marker $VERIFY_ID"
  step "MCP round trip against $MCP_URL${MCP_HOST_HEADER:+ (Host: $MCP_HOST_HEADER)}"
  mcp_initialize bm-verify
  check_tools
  check_semantic_search_off
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
