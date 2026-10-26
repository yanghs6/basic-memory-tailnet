#!/usr/bin/env bash
# First-time VM setup before the access path exists (public SSH), or over the SSH host alias in ssh mode. Safe to rerun.
# Usage: make vm-bootstrap HOST=<public-ip, or the SSH host alias in ssh mode>   (in tailscale mode the Tailscale auth
#        key comes from $TS_AUTHKEY or a hidden prompt)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly REMOTE_SCRIPT_TEMPLATE=/tmp/bm-bootstrap.XXXXXX
readonly TS_HOSTNAME=agent-hub

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

# print_next_steps MODE USER -> what to do after a successful bootstrap.
print_next_steps() {
  log "Next steps:"
  if [[ "$1" == ssh ]]; then
    log "  1. make deploy verify status"
    log "  2. make tunnel, then connect the agents (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md)"
    return 0
  fi
  log "  1. ssh $2@$TS_HOSTNAME true    # must succeed over Tailscale SSH"
  log "  2. only then delete the firewall rule that opens port 22 (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  log "  3. make deploy verify status"
}

main() {
  local remote_script host="${1:-}" user="${BM_VM_USER:-ubuntu}" key="" remote_env mode upload_hint
  [[ -n "$host" ]] || die "usage: make vm-bootstrap HOST=<public-ip, or the SSH host alias in ssh mode>"
  mode="$(access_mode)" || exit 1
  require_cmd ssh
  if [[ "$mode" == tailscale ]]; then
    key="$(read_auth_key)" || exit 1
    if [[ -n "$key" ]]; then
      log "using auth key $(mask "$key")"
    fi
    upload_hint="check the public IP, your SSH key, and that a firewall rule allows port 22 from your IP (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md)"
  else
    upload_hint="check the ProxyCommand for $host in ~/.ssh/config, its login and the firewall rule for the tunnel range (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md)"
  fi

  step "upload bootstrap script to $user@$host"
  # mktemp gives an unpredictable path and mode 0600, so no other VM user can swap the file root runs.
  remote_script="$(ssh_public "$user@$host" "mktemp $REMOTE_SCRIPT_TEMPLATE")" || die "upload failed: $upload_hint"
  # The path is spliced into later remote commands, so accept only what mktemp should print.
  [[ "$remote_script" =~ ^/tmp/bm-bootstrap\.[A-Za-z0-9]{6}$ ]] \
    || die "unexpected temp path from mktemp on the VM: '$remote_script'"
  ssh_public "$user@$host" "cat > $remote_script" <"$SCRIPT_DIR/remote/provision-vm.sh" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "upload failed: $upload_hint"
    }

  step "run bootstrap on the VM (access: $mode)"
  remote_env="BM_ACCESS=$mode BM_PORT=${BM_PORT:-$DEFAULT_BM_PORT} SB_PORT=${SB_PORT:-$DEFAULT_SB_PORT} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
  remote_env="$remote_env ADMIN_USER=$user TS_HOSTNAME=$TS_HOSTNAME"
  printf '%s\n' "$key" | ssh_public "$user@$host" "sudo $remote_env bash $remote_script" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "bootstrap failed on the VM: rerun 'make vm-bootstrap HOST=$host' (it is safe to repeat)"
    }
  remove_remote_script "$user@$host" "$remote_script"
  print_next_steps "$mode" "$user"
}

main "$@"
