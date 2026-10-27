#!/usr/bin/env bats
load helpers

# The base URL the fixtures were recorded against: the local gateway of make local-verify with BM_WEB=on.
LOCAL_BASE=http://127.0.0.1:8738
PUBLIC_HOST=mcp.example.com
# A documentation address (RFC 5737) standing in for a public IPv4 address.
PUBLIC_ADDRESS=203.0.113.10
# 100.64.0.0/10, the CGNAT range claude.ai refuses, as its first octet and its lowest second octet. The test builds an
# address inside it at run time, so no file holds a literal CGNAT address.
CGNAT_FIRST_OCTET=100
CGNAT_SECOND_OCTET_MIN=64
# The redirect URI the registration check sends; the gateway allows only the claude.ai callback.
FOREIGN_REDIRECT_URI=https://example.invalid/callback

setup() {
  setup_stubs curl dig
  SCRIPT="$REPO_DIR/scripts/verify-web.sh"
  use_web_fixtures "$LOCAL_BASE"
}

# use_web_fixtures BASE_URL: copy tests/fixtures/verify-web to the test tmpdir with BASE_URL in place of the recorded
# base URL, and point the curl stub at the copy.
use_web_fixtures() {
  local dir="$BATS_TEST_TMPDIR/web" file
  rm -rf "$dir" && cp -R "$REPO_DIR/tests/fixtures/verify-web" "$dir" || return 1
  for file in "$dir"/*; do
    sed "s#$LOCAL_BASE#$1#g" "$file" >"$file.tmp" && mv "$file.tmp" "$file" || return 1
  done
  export CURL_WEB_FIXTURES="$dir"
}

# set_json NAME FILTER: apply the jq FILTER to the recorded body of NAME.
set_json() {
  jq "$2" "$CURL_WEB_FIXTURES/$1.body" >"$CURL_WEB_FIXTURES/$1.body.tmp" \
    && mv "$CURL_WEB_FIXTURES/$1.body.tmp" "$CURL_WEB_FIXTURES/$1.body"
}

@test "passes when the gateway answers 401 with resource_metadata, serves both metadata documents and refuses a foreign redirect URI" {
  run "$SCRIPT" "$LOCAL_BASE"
  assert_success
  assert_output --partial "OK: POST /mcp without a token answers 401 with resource_metadata"
  assert_output --partial "OK: the protected resource metadata names BASE_URL/mcp"
  assert_output --partial "OK: the authorization server metadata offers S256, client ID metadata documents and the none token auth method"
  assert_output --partial "OK: /register refuses a foreign redirect URI"
  run grep -cF "\"$FOREIGN_REDIRECT_URI\"" "$STUB_LOG.requests"
  assert_output 1
  refute_stub_called '^dig '
}

@test "fails on a 200 without a token, a 401 without resource_metadata, a wrong resource, a missing S256, CIMD off, no none auth method or an accepted registration" {
  local case fault expected
  # Each case: the fault | the check that must stop the script.
  for case in "mcp-200|POST /mcp: expected HTTP 401" \
    "no-resource-metadata|POST /mcp: the 401 has no resource_metadata" \
    "wrong-resource|protected resource metadata" \
    "no-s256|S256" \
    "cimd-off|client_id_metadata_document_supported" \
    "no-none|token_endpoint_auth_methods_supported" \
    "register-201|/register: expected HTTP 400"; do
    IFS='|' read -r fault expected <<<"$case"
    (
      use_web_fixtures "$LOCAL_BASE" || exit 1
      case "$fault" in
        mcp-200) echo 200 >"$CURL_WEB_FIXTURES/mcp.status" ;;
        no-resource-metadata) printf 'HTTP/1.1 401 Unauthorized\r\nwww-authenticate: Bearer error="invalid_token"\r\n\r\n' >"$CURL_WEB_FIXTURES/mcp.headers" ;;
        wrong-resource) set_json well-known_oauth-protected-resource_mcp '.resource = "http://127.0.0.1:9999/mcp"' ;;
        no-s256) set_json well-known_oauth-authorization-server '.code_challenge_methods_supported = ["plain"]' ;;
        cimd-off) set_json well-known_oauth-authorization-server '.client_id_metadata_document_supported = false' ;;
        no-none) set_json well-known_oauth-authorization-server '.token_endpoint_auth_methods_supported = ["client_secret_post"]' ;;
        register-201) echo 201 >"$CURL_WEB_FIXTURES/register.status" && echo '{"client_id":"stub-client"}' >"$CURL_WEB_FIXTURES/register.body" ;;
      esac || exit 1
      run "$SCRIPT" "$LOCAL_BASE"
      assert_failure && assert_output --partial "$expected"
    ) || fail "verify-web did not stop at the expected check for: $fault"
  done
}

@test "--public fails when the host resolves to a private, CGNAT or loopback address and never prints the host or the addresses" {
  local cgnat case kind address
  cgnat="$CGNAT_FIRST_OCTET.$((CGNAT_SECOND_OCTET_MIN + 1)).2.3"
  use_web_fixtures "https://$PUBLIC_HOST"
  # Each case: the kind of address | what dig answers.
  for case in "RFC 1918|10.1.2.3" "CGNAT|$cgnat" "loopback|127.0.0.1"; do
    IFS='|' read -r kind address <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      DIG_STUB_ANSWER="$address" run "$SCRIPT" --public "https://$PUBLIC_HOST"
      assert_failure \
        && refute_output --partial "$PUBLIC_HOST" \
        && refute_output --partial "$address" \
        && refute_stub_called '^curl '
    ) || fail "verify-web --public went on, or printed the host or the address, for a $kind address"
  done
  DIG_STUB_ANSWER="$PUBLIC_ADDRESS" run "$SCRIPT" --public "https://$PUBLIC_HOST"
  assert_success
  assert_output --partial "OK: the host resolves only to public IPv4 addresses"
  refute_output --partial "$PUBLIC_HOST"
  refute_output --partial "$PUBLIC_ADDRESS"
}
