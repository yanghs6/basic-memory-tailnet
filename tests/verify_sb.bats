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
  run grep -F "test-password" "$STUB_LOG"
  assert_failure
  run cat "$STUB_LOG.stdin"
  assert_output "test-password"
  run grep -F "http://127.0.0.1:3000/.logout" "$STUB_LOG"
  assert_success

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

@test "--read-only stops before the login and needs no SB_USER" {
  unset SB_USER
  run "$VERIFY_SB" --read-only http://127.0.0.1:3000
  assert_success
  run grep -F "/.auth" "$STUB_LOG"
  assert_failure
}

@test "rejects an SB_USER that make or docker compose would change, before contacting the server" {
  local value
  for value in "" "admin" "admin:pa ss" 'admin:pa$ss' "admin:pa#ss" "admin:pa'ss" 'admin:pa"ss' "ad min:secret123"; do
    SB_USER="$value" run "$VERIFY_SB" http://127.0.0.1:3000
    [[ "$status" -ne 0 ]] || fail "expected SB_USER '$value' to be rejected"
    assert_output --partial "SB_USER"
    if [[ "$value" == *:* ]]; then
      refute_output --partial "${value#*:}"
    fi
  done
  run grep -c '^curl ' "$STUB_LOG"
  assert_output 0
}

@test "rejects an SB_USER that make changed while reading the env file, naming the file but neither value" {
  local env_file="$BATS_TEST_TMPDIR/main.env" pair raw passed
  # Each pair: the raw .env value | what GNU make passes on (# starts a comment, $o expands to nothing).
  for pair in 'admin:Tr4mp#oline|admin:Tr4mp' 'admin:Tr4mp$oline|admin:Tr4mpline'; do
    IFS='|' read -r raw passed <<<"$pair"
    printf 'BM_PORT=8737\nSB_USER=%s\n' "$raw" >"$env_file"
    SB_ENV_FILE="$env_file" SB_USER="$passed" run "$VERIFY_SB" http://127.0.0.1:3000
    assert_failure
    assert_output --partial "SB_USER in $env_file"
    refute_output --partial "Tr4mp"
  done
  run grep -c '^curl ' "$STUB_LOG"
  assert_output 0

  # The last SB_USER line wins, and a CRLF line ending is not part of the value.
  printf 'SB_USER=admin:old-password\nSB_USER=admin:test-password\r\n' >"$env_file"
  SB_ENV_FILE="$env_file" run "$VERIFY_SB" http://127.0.0.1:3000
  assert_success
}
