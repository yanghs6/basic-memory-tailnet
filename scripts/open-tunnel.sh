#!/usr/bin/env bash
# ssh access mode: forward Basic Memory and the web UI on the VM to 127.0.0.1 on this machine over the SSH host alias,
# in the foreground (Ctrl-C stops it). It does not reconnect: when ssh ends, it fails with ssh's exit code; rerun it.
# Usage: make tunnel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly DEFAULT_TUNNEL_MCP_PORT=18737
readonly DEFAULT_TUNNEL_WEB_PORT=13000
readonly SERVER_ALIVE_INTERVAL_SECONDS=30
readonly SERVER_ALIVE_COUNT_MAX=3
# Exit code when ssh ended with 0: a tunnel that ends is still a failure.
readonly TUNNEL_ENDED_EXIT=1

main() {
  local mode status=0
  local mcp_port="${BM_TUNNEL_MCP_PORT:-$DEFAULT_TUNNEL_MCP_PORT}" web_port="${BM_TUNNEL_WEB_PORT:-$DEFAULT_TUNNEL_WEB_PORT}"
  mode="$(access_mode)" || exit 1
  [[ "$mode" == ssh ]] \
    || die "make tunnel is for BM_ACCESS=ssh; in tailscale mode clients use https://<host>.<tailnet>.ts.net/mcp (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md)"
  require_vm nc
  require_free_port BM_TUNNEL_MCP_PORT "$mcp_port"
  require_free_port BM_TUNNEL_WEB_PORT "$web_port"

  tunnel_args "$mcp_port" "$web_port" -o "ServerAliveInterval=$SERVER_ALIVE_INTERVAL_SECONDS" \
    -o "ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX"
  log "running: ssh ${TUNNEL_ARGS[*]}"
  log "MCP: http://127.0.0.1:$mcp_port/mcp  web UI: http://127.0.0.1:$web_port  (Ctrl-C stops the tunnel)"
  ssh "${TUNNEL_ARGS[@]}" || status=$?
  # Not die: the exit code of ssh is the point, so scripts and callers can tell why the tunnel ended.
  printf "ERROR: tunnel closed (exit %s): rerun 'make tunnel'; %s\n" "$status" "$(access_hint)" >&2
  exit "$((status == 0 ? TUNNEL_ENDED_EXIT : status))"
}

main "$@"
