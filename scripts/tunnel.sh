#!/usr/bin/env bash
# ssh access mode: forward Basic Memory and the web UI on the VM to 127.0.0.1 on this machine over the SSH host alias,
# in the foreground (Ctrl-C stops it). It does not reconnect: when ssh ends, it fails with ssh's exit code; rerun it.
# Usage: tunnel.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly DEFAULT_TUNNEL_MCP_PORT=18737
readonly DEFAULT_TUNNEL_WEB_PORT=13000
readonly MIN_LOCAL_PORT=1024
readonly MAX_LOCAL_PORT=65535
readonly SERVER_ALIVE_INTERVAL_SECONDS=30
readonly SERVER_ALIVE_COUNT_MAX=3

# require_free_port NAME PORT -> dies unless PORT is an unprivileged port number that nothing on 127.0.0.1 listens on.
require_free_port() {
  local name="$1" port="$2"
  if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || ((port < MIN_LOCAL_PORT || port > MAX_LOCAL_PORT)); then
    die "$name must be a port number from $MIN_LOCAL_PORT to $MAX_LOCAL_PORT (got '$port')"
  fi
  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    die "port $port is in use on 127.0.0.1: another 'make tunnel'? or set $name in .env"
  fi
}

main() {
  local mode status=0
  local mcp_port="${BM_TUNNEL_MCP_PORT:-$DEFAULT_TUNNEL_MCP_PORT}" web_port="${BM_TUNNEL_WEB_PORT:-$DEFAULT_TUNNEL_WEB_PORT}"
  local -a cmd
  mode="$(access_mode)" || exit 1
  [[ "$mode" == ssh ]] \
    || die "make tunnel is for BM_ACCESS=ssh; in tailscale mode clients use https://<host>.<tailnet>.ts.net/mcp (docs/runbooks/operations.md)"
  require_cmd ssh nc
  require_env BM_VM_HOST BM_VM_USER
  require_free_port BM_TUNNEL_MCP_PORT "$mcp_port"
  require_free_port BM_TUNNEL_WEB_PORT "$web_port"

  cmd=(ssh -N -o ExitOnForwardFailure=yes -o "ServerAliveInterval=$SERVER_ALIVE_INTERVAL_SECONDS"
    -o "ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX"
    -L "$(forward_spec "$mcp_port" "${BM_PORT:-8737}")" -L "$(forward_spec "$web_port" "${SB_PORT:-3000}")"
    "$BM_VM_USER@$BM_VM_HOST")
  log "running: ${cmd[*]}"
  log "MCP: http://127.0.0.1:$mcp_port/mcp  web UI: http://127.0.0.1:$web_port  (Ctrl-C stops the tunnel)"
  "${cmd[@]}" || status=$?
  die "tunnel closed (exit $status): rerun 'make tunnel'; $(access_hint)"
}

main "$@"
