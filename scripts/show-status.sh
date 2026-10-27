#!/usr/bin/env bash
# Show VM container state, memory and swap use, and how the VM is reached: tailscale serve config, or in the ssh
# access mode whether Tailscale is still logged in on the VM.
# Usage: make status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

# memory_swap_summary -> "<memory used %> <swap used MB> <swap total MB>" from one `free -m` run on the VM.
# Memory used is total minus available. Exits 1 when free prints no Mem: or no Swap: line, or a zero memory total.
memory_swap_summary() {
  remote "free -m" | awk '/^Mem:/ { if ($2 > 0) mem = int(($2 - $7) * 100 / $2) } /^Swap:/ { swap_total = $2; swap_used = $3 } END { if (mem == "" || swap_total == "") exit 1; printf "%d %d %d\n", mem, swap_used, swap_total }'
}

# gateway_store_summary -> "<KiB> <registrations>": the size of the gateway store on the VM and the number of files in its
# mcp-oauth-proxy-clients folders (one per registered client). "0 0" while the gateway has not run yet.
# The store is the one thing a client without a login can grow (spec web-connector, section 3.4).
gateway_store_summary() {
  local dir="$BM_REMOTE_DATA_ROOT/gateway"
  remote "set -o pipefail; if [ -d $dir ]; then kib=\$(sudo -n du -sk $dir | cut -f1) && clients=\$(sudo -n find $dir -type f -path '*mcp-oauth-proxy-clients*' | wc -l | tr -d ' ') && echo \"\$kib \$clients\"; else echo '0 0'; fi"
}

# show_access MODE -> the Serve config (tailscale), or whether Tailscale is still logged in on the VM (ssh).
show_access() {
  if [[ "$1" == ssh ]]; then
    step "access: ssh"
    require_cmd jq
    if vm_tailscale_logged_in; then
      log "WARNING: Tailscale is still logged in on the VM; BM_ACCESS=ssh expects it off (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Access mode change)"
    else
      log "tailscale: not installed or logged out"
    fi
    return 0
  fi
  step "tailscale serve"
  remote "sudo -n tailscale serve status" \
    || die "tailscale serve is not configured: rerun 'make vm-bootstrap HOST=<public-ip>' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
}

main() {
  local summary used swap_used swap_total mode web store_kib store_clients
  require_vm
  mode="$(access_mode)" || exit 1
  web="$(web_mode)" || exit 1

  step "containers"
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST: $(access_hint)"

  step "memory and swap"
  summary="$(memory_swap_summary)" \
    || die "could not read memory usage on $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST free -m' and check its Mem: and Swap: lines; if SSH fails, $(access_hint)"
  read -r used swap_used swap_total <<<"$summary"
  log "memory used: ${used}%"
  log "swap used: ${swap_used}/${swap_total} MB"
  if ((swap_total == 0)); then
    log "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  fi

  if [[ "$web" == on ]]; then
    step "web connector"
    summary="$(gateway_store_summary)" \
      || die "could not read the gateway store on $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST sudo -n du -sk $BM_REMOTE_DATA_ROOT/gateway' and check it; if SSH fails, $(access_hint)"
    read -r store_kib store_clients <<<"$summary"
    log "gateway store: ${store_kib} KiB, ${store_clients} client registrations"
  fi

  show_access "$mode"
}

main "$@"
