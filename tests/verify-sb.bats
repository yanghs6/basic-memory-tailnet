#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl
  export SB_USER=admin:test-password
  VERIFY_SB="$REPO_DIR/scripts/verify-sb.sh"
}

@test "logs in with the password on stdin only, checks the cookie and the disabled shell, warns about fonts and logs out" {
  run "$VERIFY_SB" http://127.0.0.1:3000
  assert_success
  assert_output --partial "OK: SilverBullet checks passed for http://127.0.0.1:3000"
  refute_output --partial "WARNING"
  refute_output --partial "test-password"
  refute_output --partial "stub-session-token"
  refute_stub_called -F "test-password"
  run cat "$STUB_LOG.stdin"
  assert_output "test-password"
  assert_stub_called -F "http://127.0.0.1:3000/.logout"

  CURL_SB_FONT_STATUS=404 run "$VERIFY_SB" http://127.0.0.1:3000
  assert_success
  assert_output --partial "WARNING: the font"
}

@test "fails when SilverBullet is down, open without a login, refuses the login, sets a weak cookie or runs shell commands" {
  local case
  for case in \
    "CURL_SB_PING_STATUS=000" \
    "CURL_SB_FS_STATUS=200" \
    'CURL_SB_AUTH_BODY={"status":"error","error":"Invalid username and/or password"}' \
    "CURL_SB_AUTH_STATUS=500" \
    "CURL_SB_COOKIE=" \
    "CURL_SB_COOKIE=set-cookie: auth_x=t; Path=/; HttpOnly" \
    "CURL_SB_COOKIE=set-cookie: auth_x=t; Path=/; SameSite=Lax" \
    "CURL_SB_SHELL_STATUS=200"; do
    run env "$case" "$VERIFY_SB" http://127.0.0.1:3000
    [[ "$status" -ne 0 ]] || fail "expected a failure with $case; got: $output"
  done
  # Over https the session cookie must also be Secure (Tailscale Serve sends X-Forwarded-Proto: https).
  run "$VERIFY_SB" https://agent-hub.example.ts.net:8443
  assert_failure
  CURL_SB_COOKIE="set-cookie: auth_x=t; Path=/; SameSite=Lax; HttpOnly; Secure" run "$VERIFY_SB" https://agent-hub.example.ts.net:8443
  assert_success
}
