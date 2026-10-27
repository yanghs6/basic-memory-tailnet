#!/usr/bin/env bash
# Checks the OAuth front of the claude.ai web connector gateway the way claude.ai discovers it: POST /mcp without a
# token answers 401 with resource_metadata, the protected resource and authorization server metadata are right, and
# /register refuses a foreign redirect URI (so the check stores nothing). --public first checks that the host name
# resolves only to public IPv4 addresses. Changes nothing, and never prints the base URL, the host name or its addresses.
# Usage: verify-web.sh [--public] BASE_URL (make local-verify with BM_WEB=on)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PROTOCOL_VERSION="2025-06-18"
# claude.ai gives the discovery and registration endpoints 10 seconds.
readonly REQUEST_TIMEOUT_SECONDS=10
readonly DNS_TIMEOUT_SECONDS=5
readonly MCP_PATH="/mcp"
readonly RESOURCE_METADATA_PATH="/.well-known/oauth-protected-resource/mcp"
readonly AUTH_SERVER_METADATA_PATH="/.well-known/oauth-authorization-server"
readonly REGISTER_PATH="/register"
# The gateway allows only the claude.ai callback, so registering this one must fail and store nothing.
readonly FOREIGN_REDIRECT_URI="https://example.invalid/callback"
readonly EXPECTED_REGISTER_STATUS=400
readonly EXPECTED_REGISTER_ERROR="invalid_redirect_uri"
readonly IPV4_PATTERN='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
readonly MAX_OCTET=255
# IPv4 ranges that are not public: this network, RFC 1918, CGNAT, loopback, link-local, multicast and reserved.
# claude.ai refuses a host that resolves into the private, CGNAT and loopback ranges.
readonly NON_PUBLIC_RANGES="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/3"

BASE_URL=""
PUBLIC=""
WORK_DIR=""

usage_text() { printf 'usage: verify-web.sh [--public] BASE_URL'; }

usage() { die "$(usage_text)"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --public)
        PUBLIC=1
        shift
        ;;
      -*) usage ;;
      *)
        [[ -z "$BASE_URL" ]] || die "only one BASE_URL is allowed: $(usage_text)"
        BASE_URL="${1%/}"
        shift
        ;;
    esac
  done
  [[ -n "$BASE_URL" ]] || usage
}

# ipv4_number ADDRESS -> the address as one 32-bit number (octets read as decimal, also with leading zeros).
ipv4_number() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  printf '%s\n' $(((10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d))
}

# is_public_ipv4 ADDRESS -> exit 0 when ADDRESS is a valid IPv4 address outside NON_PUBLIC_RANGES.
is_public_ipv4() {
  local address="$1" octet range number network bits mask
  [[ "$address" =~ $IPV4_PATTERN ]] || return 1
  for octet in ${address//./ }; do
    ((10#$octet <= MAX_OCTET)) || return 1
  done
  number="$(ipv4_number "$address")"
  for range in $NON_PUBLIC_RANGES; do
    network="$(ipv4_number "${range%/*}")"
    bits="${range#*/}"
    mask=$(((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF))
    if (((number & mask) == (network & mask))); then
      return 1
    fi
  done
  return 0
}

# check_public_host -> dies unless the host name of BASE_URL resolves to at least one IPv4 address and only to public
# ones. claude.ai connects over IPv4 only and refuses private, CGNAT and loopback addresses before it sends a request.
check_public_host() {
  local host answers address count=0
  require_cmd dig
  host="${BASE_URL#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  answers="$(dig +short +time="$DNS_TIMEOUT_SECONDS" +tries=1 A "$host" 2>/dev/null)" \
    || die "the host name did not resolve (dig failed): check BM_WEB_HOST in .env and its DNS record"
  while IFS= read -r address; do
    # dig +short also prints the names of a CNAME chain.
    [[ "$address" =~ $IPV4_PATTERN ]] || continue
    count=$((count + 1))
    is_public_ipv4 "$address" \
      || die "the host name resolves to a private, CGNAT, loopback or other non-public IPv4 address, which claude.ai refuses: point its DNS record at the Cloudflare tunnel (proxied)"
  done <<<"$answers"
  ((count > 0)) || die "the host name resolves to no IPv4 address (claude.ai connects over IPv4 only): check its DNS record"
  log "OK: the host resolves only to public IPv4 addresses"
}

# request METHOD PATH [JSON] -> prints the HTTP status; the response headers and body land in $WORK_DIR. curl's own
# error messages name the host, so they are dropped.
request() {
  local method="$1" path="$2" payload="${3:-}"
  local -a args=(-s -m "$REQUEST_TIMEOUT_SECONDS" -D "$WORK_DIR/headers" -o "$WORK_DIR/body" -w '%{http_code}' -X "$method")
  if [[ -n "$payload" ]]; then
    args+=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$payload")
  fi
  curl "${args[@]}" "$BASE_URL$path" 2>/dev/null
}

check_unauthenticated() {
  local payload status
  payload="$(jq -cn --arg version "$PROTOCOL_VERSION" \
    '{jsonrpc: "2.0", id: 1, method: "initialize", params: {protocolVersion: $version, capabilities: {}, clientInfo: {name: "bm-verify-web", version: "1"}}}')"
  status="$(request POST "$MCP_PATH" "$payload")" \
    || die "POST $MCP_PATH: request failed (is the gateway running? try 'make local-up' with BM_WEB=on, or 'make status')"
  [[ "$status" == 401 ]] || die "POST $MCP_PATH: expected HTTP 401 without a token, got $status (the gateway must refuse requests without a login)"
  grep -iq '^www-authenticate:.*resource_metadata=' "$WORK_DIR/headers" \
    || die "POST $MCP_PATH: the 401 has no resource_metadata in WWW-Authenticate (claude.ai cannot find the login; does a proxy rewrite the header?)"
  log "OK: POST /mcp without a token answers 401 with resource_metadata"
}

check_resource_metadata() {
  local status
  status="$(request GET "$RESOURCE_METADATA_PATH")" || die "GET $RESOURCE_METADATA_PATH: request failed"
  [[ "$status" == 200 ]] || die "GET $RESOURCE_METADATA_PATH: expected HTTP 200, got $status"
  jq -e --arg resource "$BASE_URL$MCP_PATH" '.resource == $resource' "$WORK_DIR/body" >/dev/null 2>&1 \
    || die "the protected resource metadata does not name BASE_URL$MCP_PATH as its resource: check the gateway's BM_WEB_BASE_URL"
  log "OK: the protected resource metadata names BASE_URL/mcp"
}

check_auth_server_metadata() {
  local status body="$WORK_DIR/body"
  status="$(request GET "$AUTH_SERVER_METADATA_PATH")" || die "GET $AUTH_SERVER_METADATA_PATH: request failed"
  [[ "$status" == 200 ]] || die "GET $AUTH_SERVER_METADATA_PATH: expected HTTP 200, got $status"
  jq -e 'any(.code_challenge_methods_supported[]?; . == "S256")' "$body" >/dev/null 2>&1 \
    || die "the authorization server metadata has no S256 in code_challenge_methods_supported (claude.ai requires PKCE S256)"
  jq -e '.client_id_metadata_document_supported == true' "$body" >/dev/null 2>&1 \
    || die "the authorization server metadata does not set client_id_metadata_document_supported to true (claude.ai would fall back to dynamic registration)"
  jq -e 'any(.token_endpoint_auth_methods_supported[]?; . == "none")' "$body" >/dev/null 2>&1 \
    || die "the authorization server metadata has no none in token_endpoint_auth_methods_supported (claude.ai uses client ID metadata documents only with it)"
  log "OK: the authorization server metadata offers S256, client ID metadata documents and the none token auth method"
}

check_registration() {
  local payload status
  payload="$(jq -cn --arg uri "$FOREIGN_REDIRECT_URI" \
    '{client_name: "bm-verify-web", redirect_uris: [$uri], grant_types: ["authorization_code"], response_types: ["code"], token_endpoint_auth_method: "none"}')"
  status="$(request POST "$REGISTER_PATH" "$payload")" || die "POST $REGISTER_PATH: request failed"
  [[ "$status" == "$EXPECTED_REGISTER_STATUS" ]] \
    || die "$REGISTER_PATH: expected HTTP $EXPECTED_REGISTER_STATUS for a foreign redirect URI, got $status (the gateway must allow only the claude.ai callback; a 2xx stored a client registration)"
  jq -e --arg error "$EXPECTED_REGISTER_ERROR" '.error == $error' "$WORK_DIR/body" >/dev/null 2>&1 \
    || die "$REGISTER_PATH: the $EXPECTED_REGISTER_STATUS is not $EXPECTED_REGISTER_ERROR (check allowed_client_redirect_uris in gateway/gateway.py)"
  log "OK: /register refuses a foreign redirect URI ($EXPECTED_REGISTER_STATUS $EXPECTED_REGISTER_ERROR)"
}

main() {
  parse_args "$@"
  require_cmd curl jq
  WORK_DIR="$(mktemp -d)" || exit 1
  trap 'rm -rf "$WORK_DIR"' EXIT
  step "web connector OAuth checks${PUBLIC:+ against the public host}"
  if [[ -n "$PUBLIC" ]]; then
    check_public_host
  fi
  check_unauthenticated
  check_resource_metadata
  check_auth_server_metadata
  check_registration
  log "OK: web connector OAuth checks passed"
}

main "$@"
