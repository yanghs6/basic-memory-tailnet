#!/usr/bin/env bash
# Verify the VM end to end: MCP round trip over the tailnet URL (read-only probe with --read-only),
# loopback-only binding, tailnet-only Serve (no Funnel), and that the public IP refuses common ports.
# OCI ingress rules and the tailnet policy cannot be read from here; audit them by hand
# (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Exposure audit).
# Usage: verify-vm.sh [--read-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PUBLIC_PROBE_TIMEOUT_SECONDS=5
readonly PUBLIC_PROBE_PORTS="22 80 443"

check_loopback_binding() {
  local port="$1" listeners
  step "check port $port is bound to loopback only"
  listeners="$(remote "ss -Hltn 'sport = :$port'")" || die "could not list listeners on $BM_VM_HOST"
  [[ -n "$listeners" ]] || die "nothing listens on port $port on the VM: run 'make deploy'"
  if awk '{ print $4 }' <<<"$listeners" | grep -vqE '^127\.0\.0\.1:'; then
    die "port $port is exposed beyond loopback: $listeners"
  fi
  log "OK: port $port listens on 127.0.0.1 only"
}

check_serve_tailnet_only() {
  local serve
  step "check tailscale serve is tailnet only"
  serve="$(remote "sudo -n tailscale serve status")" || die "could not read tailscale serve status on $BM_VM_HOST"
  if grep -qi 'funnel on' <<<"$serve"; then
    die "Funnel is on for this node: the unauthenticated endpoint is public; turn it off (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Exposure audit)"
  fi
  grep -q 'tailnet only' <<<"$serve" || die "unexpected tailscale serve status (expected '(tailnet only)'): $serve"
  log "OK: tailscale serve is tailnet only"
}

# probe_port PLATFORM HOST PORT -> succeeds when HOST accepts a TCP connection on PORT.
# Assumption (macOS nc(1) as quoted by ss64.com; primary source not checked): on macOS -w only limits an idle
# established connection and -G limits the TCP connect, so without -G a silently dropped SYN waits for the
# OS connect timeout (about 75 s per port). On Linux netcat-openbsd -G means something else, so Darwin only.
probe_port() {
  if [[ "$1" == Darwin ]]; then
    nc -z -G "$PUBLIC_PROBE_TIMEOUT_SECONDS" -w "$PUBLIC_PROBE_TIMEOUT_SECONDS" "$2" "$3" >/dev/null 2>&1
  else
    nc -z -w "$PUBLIC_PROBE_TIMEOUT_SECONDS" "$2" "$3" >/dev/null 2>&1
  fi
}

check_public_closed() {
  local port="$1" probe platform
  platform="$(uname -s)" || die "could not detect the local platform with uname -s"
  step "check public IP $BM_VM_PUBLIC_IP refuses ports $PUBLIC_PROBE_PORTS $port"
  for probe in $PUBLIC_PROBE_PORTS "$port"; do
    if probe_port "$platform" "$BM_VM_PUBLIC_IP" "$probe"; then
      die "public IP $BM_VM_PUBLIC_IP accepts connections on port $probe: remove that OCI ingress rule"
    fi
  done
  log "OK: public IP $BM_VM_PUBLIC_IP refuses ports $PUBLIC_PROBE_PORTS $port"
}

main() {
  local port="${BM_PORT:-8737}" url
  case "${1:-}" in
    "" | --read-only) ;;
    *) die "usage: verify-vm.sh [--read-only]" ;;
  esac
  require_cmd ssh curl jq nc
  require_env BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP
  [[ "$BM_TAILNET_DOMAIN" =~ ^[a-z0-9-]+\.ts\.net$ ]] \
    || die "BM_TAILNET_DOMAIN must look like tail1234.ts.net (no https://, no trailing dot): '$BM_TAILNET_DOMAIN'"
  url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}/mcp"

  if [[ "${1:-}" == --read-only ]]; then
    "$SCRIPT_DIR/verify-mcp.sh" --read-only "$url"
  else
    "$SCRIPT_DIR/verify-mcp.sh" "$url"
  fi
  check_loopback_binding "$port"
  check_serve_tailnet_only
  check_public_closed "$port"
  log "OK: automated VM checks passed; audit OCI ingress rules and the tailnet policy by hand (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Exposure audit)"
}

main "$@"
