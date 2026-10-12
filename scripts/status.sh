#!/usr/bin/env bash
# Show VM container state, memory use against the OCI idle threshold, and tailscale serve config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# OCI may reclaim Always Free A1 VMs when CPU (p95), network and memory all stay below 20% for 7 days.
readonly IDLE_MEMORY_PERCENT=20

memory_used_percent() {
  remote "free -m" | awk '/^Mem:/ { printf "%d\n", ($2 - $7) * 100 / $2 }'
}

main() {
  local used
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "containers"
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST (try: ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "memory (OCI idle threshold ${IDLE_MEMORY_PERCENT}%)"
  used="$(memory_used_percent)" || die "could not read memory usage on $BM_VM_HOST"
  [[ "$used" =~ ^[0-9]+$ ]] || die "unexpected memory reading from free -m: '$used'"
  log "memory used: ${used}%"
  if ((used < IDLE_MEMORY_PERCENT)); then
    log "WARNING: memory below ${IDLE_MEMORY_PERCENT}%; with idle CPU and network OCI may reclaim this VM (docs/runbooks/operations.md, Idle reclamation)"
  fi

  step "tailscale serve"
  remote "sudo -n tailscale serve status" \
    || die "tailscale serve is not configured: rerun 'make vm-bootstrap HOST=<public-ip>' (docs/runbooks/bootstrap.md)"
}

main "$@"
