#!/usr/bin/env bash
# First-time VM setup over the VM's public IP, before Tailscale SSH exists. Safe to rerun.
# Usage: bootstrap-vm.sh PUBLIC_IP   (Tailscale auth key from $TS_AUTHKEY or a hidden prompt)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly REMOTE_SCRIPT=/tmp/bm-bootstrap.sh
readonly TS_HOSTNAME=bm-node

ssh_public() {
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "$@"
}

read_auth_key() {
  local key="${TS_AUTHKEY:-}"
  if [[ -z "$key" ]]; then
    read -r -s -p "Tailscale auth key (leave empty if the VM is already on the tailnet): " key || true
    printf '\n' >&2
  fi
  printf '%s' "$key"
}

main() {
  local host="${1:-}" user="${BM_VM_USER:-ubuntu}" key remote_env
  [[ -n "$host" ]] || die "usage: make vm-bootstrap HOST=<public-ip>"
  require_cmd ssh
  key="$(read_auth_key)" || exit 1
  if [[ -n "$key" ]]; then
    log "using auth key $(mask "$key")"
  fi

  step "upload bootstrap script to $user@$host"
  ssh_public "$user@$host" "cat > $REMOTE_SCRIPT" <"$SCRIPT_DIR/remote/bootstrap.sh" \
    || die "upload failed: check the public IP, your SSH key, and the OCI ingress rule for port 22"

  step "run bootstrap on the VM (docker, tailscale, data dirs, serve)"
  remote_env="BM_PORT=${BM_PORT:-8737} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
  remote_env="$remote_env ADMIN_USER=$user TS_HOSTNAME=$TS_HOSTNAME"
  printf '%s\n' "$key" | ssh_public "$user@$host" "sudo $remote_env bash $REMOTE_SCRIPT" \
    || die "bootstrap failed on the VM: rerun 'make vm-bootstrap HOST=$host' (it is safe to repeat)"
  ssh_public "$user@$host" "rm -f $REMOTE_SCRIPT" || log "WARNING: could not remove $REMOTE_SCRIPT on the VM"

  log "Next steps:"
  log "  1. ssh $user@$TS_HOSTNAME true    # must succeed over Tailscale SSH"
  log "  2. only then delete the OCI ingress rule for port 22 (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  log "  3. make deploy verify status"
}

main "$@"
