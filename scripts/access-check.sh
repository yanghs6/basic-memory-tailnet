#!/usr/bin/env bash
# Report which access path works from the network this machine is on: the Tailscale control plane, the ssh mode's
# tunnel endpoint (BM_ACCESS_CHECK_URL) and, with BM_ACCESS=ssh, the SSH host alias. The recommendation covers this
# network only: run it on every network your clients use, then set BM_ACCESS (docs/runbooks/bootstrap.md).
# Exits 1 only when BM_ACCESS is set and that mode does not work here.
# Usage: access-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly TAILSCALE_CONTROL_URL=https://controlplane.tailscale.com/
readonly ACCESS_CHECK_TIMEOUT_SECONDS=8
readonly CURL_EXIT_DNS=6
readonly CURL_EXIT_TIMEOUT=28

# url_state URL -> "reachable (HTTP <code>)" when any HTTP answer comes back (404 included: the network let the TLS
# connection through), otherwise "blocked (<reason>)".
url_state() {
  local code rc=0
  code="$(curl -sS -o /dev/null --max-time "$ACCESS_CHECK_TIMEOUT_SECONDS" -w '%{http_code}' "$1" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) printf 'reachable (HTTP %s)\n' "$code" ;;
    "$CURL_EXIT_DNS") printf 'blocked (dns)\n' ;;
    "$CURL_EXIT_TIMEOUT") printf 'blocked (timeout)\n' ;;
    *) printf 'blocked (curl exit %s)\n' "$rc" ;;
  esac
}

# recommendation TAILSCALE_OK TUNNEL_OK -> the mode to choose on this network (each argument is yes or no).
recommendation() {
  case "$1 $2" in
    "yes yes") echo "both work here; choose tailscale unless another network your clients use blocks it" ;;
    "no yes") echo "ssh" ;;
    "yes no") echo "tailscale" ;;
    *) echo "neither works here: ask the network admin" ;;
  esac
}

main() {
  local mode chosen="${BM_ACCESS:-}" state tailscale_ok=no tunnel_ok=no ssh_ok=no
  mode="$(access_mode)" || exit 1
  require_cmd curl
  log "this network only: run it on every network your clients use"

  state="$(url_state "$TAILSCALE_CONTROL_URL")"
  log "tailscale control plane: $state"
  if [[ "$state" == reachable* ]]; then
    tailscale_ok=yes
  fi

  if [[ -n "${BM_ACCESS_CHECK_URL:-}" ]]; then
    state="$(url_state "$BM_ACCESS_CHECK_URL")"
    log "tunnel endpoint $BM_ACCESS_CHECK_URL: $state"
    if [[ "$state" == reachable* ]]; then
      tunnel_ok=yes
    fi
  else
    log "tunnel endpoint: not set (BM_ACCESS_CHECK_URL in .env)"
  fi

  if [[ "$mode" == ssh ]]; then
    require_cmd ssh
    require_env BM_VM_HOST BM_VM_USER
    if remote true; then
      ssh_ok=yes
      log "ssh $BM_VM_USER@$BM_VM_HOST: ok"
    else
      log "ssh $BM_VM_USER@$BM_VM_HOST: failed: $(access_hint)"
    fi
  fi

  log "recommendation for this network: $(recommendation "$tailscale_ok" "$tunnel_ok")"
  case "$chosen" in
    tailscale) [[ "$tailscale_ok" == yes ]] || die "BM_ACCESS=tailscale does not work on this network" ;;
    ssh) [[ "$ssh_ok" == yes ]] || die "BM_ACCESS=ssh does not work on this network: $(access_hint)" ;;
  esac
}

main "$@"
