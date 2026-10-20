#!/usr/bin/env bash
# Check a SilverBullet server: it answers, refuses requests without a login, accepts SB_USER, sets a SameSite=Lax
# HttpOnly session cookie (also Secure over https), keeps the shell disabled, and has the fonts (warning only).
# The session is signed out at the end, also after a failure. Never prints SB_USER or the session cookie.
# Usage: verify-sb.sh [--read-only] URL   (URL like http://127.0.0.1:3000; --read-only stops before the login)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

readonly CURL_TIMEOUT_SECONDS=15
readonly FONT_PATH="/.fs/$SB_FONTS_REL_DIR/D2KodingLigatureNerdFont-Regular.woff2"
readonly SHELL_PROBE_BODY='{"cmd":"true","args":[]}'

URL=""
WORK=""

# http_status CURL_ARGS... -> the HTTP status of the request; 000 when the server cannot be reached.
http_status() {
  curl -sS -m "$CURL_TIMEOUT_SECONDS" -o /dev/null -w '%{http_code}' "$@" || true
}

# shellcheck disable=SC2317  # invoked via trap
cleanup() {
  if [[ -s "$WORK/cookies" ]]; then
    http_status -b "$WORK/cookies" "$URL/.logout" >/dev/null
  fi
  rm -rf "$WORK"
}

check_open_endpoints() {
  local status
  status="$(http_status "$URL/.ping")"
  [[ "$status" == 200 ]] \
    || die "SilverBullet does not answer at $URL/.ping (HTTP $status): start it with 'make local-up' (local) or check 'make status' (VM)"
  status="$(http_status "$URL/.fs/index.md")"
  [[ "$status" == 401 ]] \
    || die "SilverBullet answered $URL/.fs/index.md with HTTP $status instead of 401 without a login: SB_USER must be set when the container starts"
  log "OK: SilverBullet answers and refuses requests without a login"
}

# login -> sign in as SB_USER and keep the session cookie in $WORK/cookies. The password reaches curl on stdin.
# SilverBullet answers a wrong password with HTTP 200 too, so the JSON status and the cookie decide.
login() {
  local status result cookie
  status="$(printf '%s' "${SB_USER#*:}" | curl -sS -m "$CURL_TIMEOUT_SECONDS" -o "$WORK/login.json" \
    -D "$WORK/login.headers" -c "$WORK/cookies" -w '%{http_code}' \
    --data-urlencode "username=${SB_USER%%:*}" --data-urlencode "password@-" "$URL/.auth")" || true
  result="$(jq -r '.status // empty' "$WORK/login.json" 2>/dev/null)" || result=""
  [[ "$status" == 200 && "$result" == ok ]] \
    || die "login to $URL failed (HTTP $status): SB_USER in the main checkout .env must match the running container (after changing it, rerun 'make local-up' or 'make deploy')"
  cookie="$(grep -i '^set-cookie: auth_' "$WORK/login.headers" | tr -d '\r')" || cookie=""
  [[ -n "$cookie" ]] || die "login to $URL set no session cookie"
  [[ "$cookie" == *"SameSite=Lax"* && "$cookie" == *"HttpOnly"* ]] \
    || die "the session cookie from $URL lacks SameSite=Lax or HttpOnly"
  if [[ "$URL" == https://* && "$cookie" != *"Secure"* ]]; then
    die "the session cookie from $URL lacks Secure: check that Tailscale Serve forwards X-Forwarded-Proto: https"
  fi
  log "OK: SilverBullet login and session cookie flags"
}

check_signed_in_limits() {
  local status
  status="$(http_status -b "$WORK/cookies" -X POST -H 'Content-Type: application/json' -d "$SHELL_PROBE_BODY" "$URL/.shell")"
  [[ "$status" == 405 ]] \
    || die "SilverBullet answered a shell request with HTTP $status instead of 405: keep SB_SHELL_BACKEND off in compose.yaml"
  log "OK: the SilverBullet shell is disabled"
  status="$(http_status -b "$WORK/cookies" "$URL$FONT_PATH")"
  if [[ "$status" != 200 ]]; then
    log "WARNING: the font $FONT_PATH is missing (HTTP $status), so browsers fall back to other fonts: run 'make sb-fonts' (LOCAL=1 for the local stack)"
  fi
}

main() {
  local read_only=""
  if [[ "${1:-}" == --read-only ]]; then
    read_only=1
    shift
  fi
  URL="${1:-}"
  [[ "$URL" =~ ^https?://[^/]+$ ]] || die "usage: verify-sb.sh [--read-only] http(s)://HOST[:PORT]"
  require_cmd curl jq
  [[ -n "$read_only" ]] || require_sb_user

  step "check SilverBullet at $URL"
  check_open_endpoints
  [[ -z "$read_only" ]] || return 0
  WORK="$(mktemp -d)" || exit 1
  trap cleanup EXIT
  login
  check_signed_in_limits
  log "OK: SilverBullet checks passed for $URL"
}

main "$@"
