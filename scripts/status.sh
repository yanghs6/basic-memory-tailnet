#!/usr/bin/env bash
# Show VM container state, memory and swap use, and tailscale serve config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# memory_swap_summary -> "<memory used %> <swap used MB> <swap total MB>" from one `free -m` run on the VM.
# Memory used is total minus available. Exits 1 when free prints no Mem: or no Swap: line, or a zero memory total.
memory_swap_summary() {
  remote "free -m" | awk '/^Mem:/ { if ($2 > 0) mem = int(($2 - $7) * 100 / $2) } /^Swap:/ { swap_total = $2; swap_used = $3 } END { if (mem == "" || swap_total == "") exit 1; printf "%d %d %d\n", mem, swap_used, swap_total }'
}

main() {
  local summary used swap_used swap_total
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "containers"
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST (try: ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "memory and swap"
  summary="$(memory_swap_summary)" || die "could not read memory usage on $BM_VM_HOST (try: ssh $BM_VM_USER@$BM_VM_HOST free -m)"
  read -r used swap_used swap_total <<<"$summary"
  log "memory used: ${used}%"
  log "swap used: ${swap_used}/${swap_total} MB"
  if ((swap_total == 0)); then
    log "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  fi

  step "tailscale serve"
  remote "sudo -n tailscale serve status" \
    || die "tailscale serve is not configured: rerun 'make vm-bootstrap HOST=<public-ip>' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
}

main "$@"
