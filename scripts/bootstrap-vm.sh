#!/usr/bin/env bash
# First-time VM setup over the VM's public IP, before Tailscale SSH exists. Safe to rerun.
# Usage: bootstrap-vm.sh PUBLIC_IP   (Tailscale auth key from $TS_AUTHKEY or a hidden prompt)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly REMOTE_SCRIPT_TEMPLATE=/tmp/bm-bootstrap.XXXXXX
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

# remove_remote_script USER@HOST PATH -> best-effort cleanup; never fails the caller.
remove_remote_script() {
  ssh_public "$1" "rm -f $2" || log "WARNING: could not remove $2 on the VM"
}

main() {
  local remote_script host="${1:-}" user="${BM_VM_USER:-ubuntu}" key remote_env
  [[ -n "$host" ]] || die "usage: make vm-bootstrap HOST=<public-ip>"
  require_cmd ssh
  key="$(read_auth_key)" || exit 1
  if [[ -n "$key" ]]; then
    log "using auth key $(mask "$key")"
  fi

  step "upload bootstrap script to $user@$host"
  # mktemp gives an unpredictable path and mode 0600, so no other VM user can swap the file root runs.
  remote_script="$(ssh_public "$user@$host" "mktemp $REMOTE_SCRIPT_TEMPLATE")" \
    || die "upload failed: check the public IP, your SSH key, and the OCI ingress rule for port 22"
  # The path is spliced into later remote commands, so accept only what mktemp should print.
  [[ "$remote_script" =~ ^/tmp/bm-bootstrap\.[A-Za-z0-9]{6}$ ]] \
    || die "unexpected temp path from mktemp on the VM: '$remote_script'"
  ssh_public "$user@$host" "cat > $remote_script" <"$SCRIPT_DIR/remote/bootstrap.sh" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "upload failed: check the public IP, your SSH key, and the OCI ingress rule for port 22"
    }

  step "run bootstrap on the VM (docker, tailscale, data dirs, serve)"
  remote_env="BM_PORT=${BM_PORT:-8737} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
  remote_env="$remote_env ADMIN_USER=$user TS_HOSTNAME=$TS_HOSTNAME"
  printf '%s\n' "$key" | ssh_public "$user@$host" "sudo $remote_env bash $remote_script" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "bootstrap failed on the VM: rerun 'make vm-bootstrap HOST=$host' (it is safe to repeat)"
    }
  remove_remote_script "$user@$host" "$remote_script"

  log "Next steps:"
  log "  1. ssh $user@$TS_HOSTNAME true    # must succeed over Tailscale SSH"
  log "  2. only then delete the OCI ingress rule for port 22 (docs/runbooks/bootstrap.md)"
  log "  3. make deploy verify status"
}

main "$@"
