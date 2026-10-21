#!/usr/bin/env bash
# Verify the VM end to end: MCP round trip over the tailnet URL, the SilverBullet login on https port 8443,
# loopback-only binding of both ports, tailnet-only Serve that sends 443 to Basic Memory and 8443 to SilverBullet
# (no Funnel on either), and that the public IP refuses common ports. With --read-only it writes no notes and does
# not log in. Firewall rules and the tailnet policy cannot be read from here; audit them by hand
# (docs/runbooks/rbk-2026-10-12-operations.md, Exposure audit).
# In the ssh access mode it runs the same checks through a temporary SSH tunnel on 127.0.0.1 and, instead of Serve,
# checks that Tailscale does not expose the VM and that sshd accepts keys only.
# Usage: make verify, or make probe (read-only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly PUBLIC_PROBE_TIMEOUT_SECONDS=5
readonly SB_HTTPS_PORT=8443
readonly PUBLIC_PROBE_PORTS="22 80 443 $SB_HTTPS_PORT"

# ssh access mode: local ends of the verify tunnel, apart from make tunnel's DEFAULT_TUNNEL_MCP_PORT and
# DEFAULT_TUNNEL_WEB_PORT (scripts/open-tunnel.sh) so both can run at once.
readonly VERIFY_TUNNEL_MCP_PORT=28737
readonly VERIFY_TUNNEL_WEB_PORT=23000
readonly TUNNEL_READY_TIMEOUT_SECONDS=20
readonly VERIFY_TUNNEL_PORT_HINT="another 'make verify' or a leftover verify tunnel? stop it and rerun"

# Global so the EXIT trap can still see it.
tunnel_pid=""

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

# serve_proxy CONFIG_JSON PORT -> the proxy target of path / on https port PORT in `tailscale serve status --json`,
# without a trailing slash (empty when there is none).
serve_proxy() {
  jq -r --arg suffix ":$2" \
    '[(.Web // {}) | to_entries[] | select(.key | endswith($suffix)) | .value.Handlers["/"].Proxy // empty] | join(" ") | rtrimstr("/")' <<<"$1"
}

check_serve() {
  local bm_port="$1" sb_port="$2" serve funnel pair https_port local_port target
  step "check tailscale serve: tailnet only, 443 -> Basic Memory, $SB_HTTPS_PORT -> SilverBullet"
  serve="$(remote "sudo -n tailscale serve status --json")" || die "could not read tailscale serve status on $BM_VM_HOST"
  funnel="$(jq -r '[(.AllowFunnel // {})[] | select(. == true)] | length' <<<"$serve")" \
    || die "unexpected tailscale serve status (not JSON): $serve"
  ((funnel == 0)) \
    || die "Funnel is on for this node: the unauthenticated endpoint is public; turn it off (docs/runbooks/rbk-2026-10-12-operations.md, Exposure audit)"
  for pair in "443 $bm_port" "$SB_HTTPS_PORT $sb_port"; do
    read -r https_port local_port <<<"$pair"
    target="$(serve_proxy "$serve" "$https_port")" || die "unexpected tailscale serve status (not JSON): $serve"
    [[ "$target" == "http://127.0.0.1:$local_port" ]] \
      || die "tailscale serve must proxy https port $https_port to http://127.0.0.1:$local_port (found '${target:-nothing}'): rerun 'make vm-bootstrap HOST=$BM_VM_HOST'"
  done
  log "OK: tailscale serve is tailnet only: 443 -> 127.0.0.1:$bm_port, $SB_HTTPS_PORT -> 127.0.0.1:$sb_port"
}

close_verify_tunnel() {
  if [[ -n "$tunnel_pid" ]]; then
    kill "$tunnel_pid" 2>/dev/null || true
    wait "$tunnel_pid" 2>/dev/null || true
  fi
}

# open_verify_tunnel -> forwards VERIFY_TUNNEL_MCP_PORT and VERIFY_TUNNEL_WEB_PORT on 127.0.0.1 to Basic Memory and
# SilverBullet on the VM's loopback over the SSH alias, in the background until this script exits.
open_verify_tunnel() {
  local waited=0 port
  # A listener already on these ports would pass the readiness check below while ssh is still connecting.
  for port in "$VERIFY_TUNNEL_MCP_PORT" "$VERIFY_TUNNEL_WEB_PORT"; do
    require_free_port "verify tunnel port" "$port" "$VERIFY_TUNNEL_PORT_HINT"
  done
  step "open a verify tunnel to $BM_VM_USER@$BM_VM_HOST on 127.0.0.1:$VERIFY_TUNNEL_MCP_PORT and :$VERIFY_TUNNEL_WEB_PORT"
  tunnel_args "$VERIFY_TUNNEL_MCP_PORT" "$VERIFY_TUNNEL_WEB_PORT" -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS"
  ssh "${TUNNEL_ARGS[@]}" &
  tunnel_pid=$!
  trap close_verify_tunnel EXIT
  while ((waited < TUNNEL_READY_TIMEOUT_SECONDS)); do
    kill -0 "$tunnel_pid" 2>/dev/null \
      || die "verify tunnel exited before it opened (is port $VERIFY_TUNNEL_MCP_PORT or $VERIFY_TUNNEL_WEB_PORT in use?): $(access_hint)"
    if local_port_open "$VERIFY_TUNNEL_MCP_PORT"; then
      log "verify tunnel is open"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  die "verify tunnel did not open within ${TUNNEL_READY_TIMEOUT_SECONDS}s: $(access_hint)"
}

check_tailscale_off() {
  step "check Tailscale does not expose the VM (BM_ACCESS=ssh)"
  if vm_tailscale_logged_in; then
    die "Tailscale is logged in on the VM but BM_ACCESS=ssh: log it out (docs/runbooks/rbk-2026-10-12-operations.md, Access mode change)"
  fi
  log "OK: Tailscale does not expose the VM (not installed, logged out or down)"
}

check_sshd_auth() {
  local config
  step "check sshd accepts keys only (BM_ACCESS=ssh)"
  config="$(remote "sudo -n sshd -T")" || die "could not read the sshd config on $BM_VM_HOST: $(access_hint)"
  grep -qx 'passwordauthentication no' <<<"$config" \
    || die "sshd on the VM accepts passwords: set PasswordAuthentication no (docs/runbooks/rbk-2026-10-12-gcp-vm.md, section 8)"
  grep -qx 'kbdinteractiveauthentication no' <<<"$config" \
    || die "sshd on the VM accepts keyboard-interactive logins: set KbdInteractiveAuthentication no (docs/runbooks/rbk-2026-10-12-gcp-vm.md, section 8)"
  log "OK: sshd accepts keys only"
}

# probe_port PLATFORM HOST PORT -> succeeds when HOST accepts a TCP connection on PORT.
# Assumption (macOS nc(1) as quoted by ss64.com; primary source not checked): on macOS -w only limits an idle
# established connection and -G limits the TCP connect, so without -G a silently dropped SYN waits for the
# OS connect timeout (about 75 s per port). On Linux netcat-openbsd -G means something else, so Darwin only.
# shellcheck disable=SC2069  # intentional: send stderr to the capture, drop stdout
probe_port() {
  if [[ "$1" == Darwin ]]; then
    nc -z -G "$PUBLIC_PROBE_TIMEOUT_SECONDS" -w "$PUBLIC_PROBE_TIMEOUT_SECONDS" "$2" "$3" 2>&1 >/dev/null
  else
    nc -z -w "$PUBLIC_PROBE_TIMEOUT_SECONDS" "$2" "$3" 2>&1 >/dev/null
  fi
}

# validate_public_ip IP -> dies unless IP is a dotted IPv4 (octets 0-255) outside loopback, private,
# link-local and unspecified ranges (probing those would say nothing about the VM's public side).
validate_public_ip() {
  local ip="$1" a b c d hint
  hint="look up the VM's public IP as described in docs/runbooks/rbk-2026-10-12-gcp-vm.md"
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] \
    || die "BM_VM_PUBLIC_IP must be the VM's public IPv4 (got '$ip'): $hint"
  a=$((10#${BASH_REMATCH[1]})) b=$((10#${BASH_REMATCH[2]})) c=$((10#${BASH_REMATCH[3]})) d=$((10#${BASH_REMATCH[4]}))
  if ((a > 255 || b > 255 || c > 255 || d > 255)); then
    die "BM_VM_PUBLIC_IP must be the VM's public IPv4 (octets 0-255, got '$ip'): $hint"
  fi
  if ((a == 0 || a == 127 || a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254))); then
    die "BM_VM_PUBLIC_IP '$ip' is loopback, private, link-local or unspecified: $hint"
  fi
}

# probe_is_open PLATFORM HOST PORT -> succeeds when the port accepts a connection, fails when it is closed;
# dies on any other nc failure (bad option, bad host) so a broken probe can never read as "closed".
probe_is_open() {
  local err
  if err="$(probe_port "$1" "$2" "$3")"; then
    return 0
  fi
  # "No route to host" is how nc reports an ICMP reject (a host firewall may reject with icmp-host-prohibited).
  if [[ -z "$err" ]] || grep -qiE 'refused|timed out|timeout|no route to host|unreachable|prohibited' <<<"$err"; then
    return 1
  fi
  die "public port probe error on $2:$3: $err"
}

check_public_closed() {
  local ports="$PUBLIC_PROBE_PORTS $*" probe platform
  platform="$(uname -s)" || die "could not detect the local platform with uname -s"
  step "check public IP $BM_VM_PUBLIC_IP refuses ports $ports"
  for probe in $ports; do
    if probe_is_open "$platform" "$BM_VM_PUBLIC_IP" "$probe"; then
      die "public IP $BM_VM_PUBLIC_IP accepts connections on port $probe: remove the firewall rule that allows it"
    fi
  done
  log "OK: public IP $BM_VM_PUBLIC_IP refuses ports $ports"
}

main() {
  local port="${BM_PORT:-$DEFAULT_BM_PORT}" sb_port="${SB_PORT:-$DEFAULT_SB_PORT}" mode url sb_url
  case "${1:-}" in
    "" | --read-only) ;;
    *) die "usage: make verify, or make probe (read-only)" ;;
  esac
  require_vm curl jq nc
  mode="$(access_mode)" || exit 1
  require_env BM_VM_PUBLIC_IP
  validate_public_ip "$BM_VM_PUBLIC_IP"
  if [[ "$mode" == ssh ]]; then
    open_verify_tunnel
    url="http://127.0.0.1:$VERIFY_TUNNEL_MCP_PORT/mcp"
    sb_url="http://127.0.0.1:$VERIFY_TUNNEL_WEB_PORT"
  else
    require_env BM_TAILNET_DOMAIN
    [[ "$BM_TAILNET_DOMAIN" =~ ^[a-z0-9-]+\.ts\.net$ ]] \
      || die "BM_TAILNET_DOMAIN must look like tail1234.ts.net (no https://, no trailing dot): '$BM_TAILNET_DOMAIN'"
    url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}/mcp"
    sb_url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}:$SB_HTTPS_PORT"
  fi

  if [[ "${1:-}" == --read-only ]]; then
    "$SCRIPT_DIR/verify-mcp.sh" --read-only "$url"
    "$SCRIPT_DIR/verify-sb.sh" --read-only "$sb_url"
  else
    "$SCRIPT_DIR/verify-mcp.sh" "$url"
    "$SCRIPT_DIR/verify-sb.sh" "$sb_url"
  fi
  check_loopback_binding "$port"
  check_loopback_binding "$sb_port"
  if [[ "$mode" == ssh ]]; then
    check_tailscale_off
    check_sshd_auth
  else
    check_serve "$port" "$sb_port"
  fi
  check_public_closed "$port" "$sb_port"
  if [[ "$mode" == ssh ]]; then
    log "OK: automated VM checks passed (access: ssh); audit firewall rules by hand (docs/runbooks/rbk-2026-10-12-operations.md, Exposure audit)"
  else
    log "OK: automated VM checks passed; audit firewall rules and the tailnet policy by hand (docs/runbooks/rbk-2026-10-12-operations.md, Exposure audit)"
  fi
}

main "$@"
