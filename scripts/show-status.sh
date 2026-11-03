#!/usr/bin/env bash
# Show VM container state and the note services that are not running, whether Basic Memory answers HTTP on the VM,
# uptime, disk, memory and swap use, and how the VM is reached: tailscale serve config, or in the ssh access mode
# whether Tailscale is still logged in on the VM. Warnings only print: status still exits 0, so `make status probe`
# goes on to the probe, which fails on a server that does not answer.
# Usage: make status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

# The compose services that keep and serve the notes; status warns about each one that is not running.
readonly STATUS_NOTE_SERVICES="basic-memory silverbullet"
# How long the HTTP check waits: a server that takes the connection but never answers must not hang status too.
readonly STATUS_HTTP_TIMEOUT_SECONDS=10
# Warning thresholds. The VM stalled at 84-85% swap use on 2026-10-28 (operations runbook, Incident log).
readonly DISK_WARN_PERCENT=80
readonly SWAP_WARN_PERCENT=80

# memory_swap_summary -> "<memory used %> <swap used MB> <swap total MB>" from one `free -m` run on the VM.
# Memory used is total minus available. Exits 1 when free prints no Mem: or no Swap: line, or a zero memory total.
memory_swap_summary() {
  remote "free -m" | awk '/^Mem:/ { if ($2 > 0) mem = int(($2 - $7) * 100 / $2) } /^Swap:/ { swap_total = $2; swap_used = $3 } END { if (mem == "" || swap_total == "") exit 1; printf "%d %d %d\n", mem, swap_used, swap_total }'
}

# disk_use_percent -> the Capacity of the filesystem that holds the data root on the VM, as a bare number, from one
# `df -P` run. Exits 1 when df fails or its second line has no percentage there.
disk_use_percent() {
  remote "df -P $BM_REMOTE_DATA_ROOT" | awk 'NR == 2 && $5 ~ /^[0-9]+%$/ { print substr($5, 1, length($5) - 1); found = 1 } END { if (!found) exit 1 }'
}

# show_running_services -> the running compose services on one line, and a warning for each of STATUS_NOTE_SERVICES
# that is not among them.
show_running_services() {
  local running list service
  running="$(remote_compose "ps --services --status running")" \
    || die "could not list the running services on $BM_VM_HOST: $(access_hint)"
  list="${running//$'\n'/ }"
  log "running: ${list:-none}"
  for service in $STATUS_NOTE_SERVICES; do
    grep -qxF "$service" <<<"$running" || log "WARNING: $service is not running: run 'make logs' (bm-diagnose)"
  done
}

# show_http_answer PORT -> whether Basic Memory answers HTTP on the VM's 127.0.0.1:PORT within
# STATUS_HTTP_TIMEOUT_SECONDS. Any status code counts as an answer; a stalled server gives none, while the compose
# healthcheck, which only opens a TCP connection, can still call it healthy.
show_http_answer() {
  local code
  if code="$(remote "curl -sS -o /dev/null -m $STATUS_HTTP_TIMEOUT_SECONDS -w '%{http_code}' http://127.0.0.1:$1/mcp")"; then
    log "basic-memory http: answered (HTTP $code)"
  else
    log "WARNING: Basic Memory did not answer HTTP on the VM's 127.0.0.1:$1 within ${STATUS_HTTP_TIMEOUT_SECONDS}s (Docker can still call it healthy): run 'make probe' and follow bm-diagnose"
  fi
}

# show_uptime_disk -> the VM's uptime and how full the data root's filesystem is, with a warning at DISK_WARN_PERCENT.
show_uptime_disk() {
  local uptime_text disk
  uptime_text="$(remote "uptime -p")" \
    || die "could not read the uptime of $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST uptime -p'; if SSH fails, $(access_hint)"
  log "uptime: $uptime_text"
  disk="$(disk_use_percent)" \
    || die "could not read the disk use on $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST df -P $BM_REMOTE_DATA_ROOT' and check its Capacity column; if SSH fails, $(access_hint)"
  log "disk used: ${disk}% of the data root's filesystem"
  if ((disk >= DISK_WARN_PERCENT)); then
    log "WARNING: the data root's filesystem is ${disk}% full (warning at ${DISK_WARN_PERCENT}%): free space before note writes and backups fail (bm-diagnose)"
  fi
}

# show_memory_swap -> memory and swap use, with a warning when no swap is active or swap use reaches SWAP_WARN_PERCENT.
show_memory_swap() {
  local summary used swap_used swap_total swap_percent
  summary="$(memory_swap_summary)" \
    || die "could not read memory usage on $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST free -m' and check its Mem: and Swap: lines; if SSH fails, $(access_hint)"
  read -r used swap_used swap_total <<<"$summary"
  log "memory used: ${used}%"
  if ((swap_total == 0)); then
    log "swap used: ${swap_used}/${swap_total} MB"
    log "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
    return 0
  fi
  swap_percent=$((swap_used * 100 / swap_total))
  log "swap used: ${swap_used}/${swap_total} MB (${swap_percent}%)"
  if ((swap_percent >= SWAP_WARN_PERCENT)); then
    log "WARNING: swap is ${swap_percent}% used (warning at ${SWAP_WARN_PERCENT}%): the 1GB VM stalls near this; run 'make probe' and follow bm-diagnose"
  fi
}

# The files of FastMCP's client registration collection in the gateway store, one per registered client, as find -path
# matches them (its * also matches /): oauth-proxy/<key fingerprint>/S_mcp_oauth_proxy_clients-<8 hex>/<client>.json.
# py-key-value-aio's FileTreeV1 strategy turns the collection name mcp-oauth-proxy-clients into that directory name and
# keeps the collection's metadata next to it as S_mcp_oauth_proxy_clients-<8 hex>-info.json, which this leaves out. Every
# key fingerprint counts, so registrations made under an older BM_WEB_JWT_KEY are included. gateway/test_gateway.py
# states the same pattern (CLIENT_FILES_PATTERN) and checks it against a real registration.
readonly GATEWAY_CLIENT_FILES_PATTERN='*/oauth-proxy/*/S_mcp_oauth_proxy_clients-*/*'

# gateway_store_summary -> "<KiB> <registrations>": the size of the gateway store on the VM and the number of client
# registrations in it (GATEWAY_CLIENT_FILES_PATTERN). "0 0" while the gateway has not run yet; fails when sudo does not
# work on the VM, so a refused sudo never reads as an empty store.
# The store is the one thing a client without a login can grow (spec web-connector, section 3.4).
gateway_store_summary() {
  local dir="$BM_REMOTE_DATA_ROOT/gateway"
  remote "set -o pipefail; if sudo -n test -d $dir; then kib=\$(sudo -n du -sk $dir | cut -f1) && clients=\$(sudo -n find $dir -type f -path '$GATEWAY_CLIENT_FILES_PATTERN' | wc -l | tr -d ' ') && echo \"\$kib \$clients\"; elif sudo -n true; then echo '0 0'; else exit 1; fi"
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
  local summary mode web store_kib store_clients
  require_vm
  mode="$(access_mode)" || exit 1
  web="$(web_mode)" || exit 1

  step "containers"
  # A VM without the app dir yet (not deployed) stops here, as the runbooks and bm-recover expect.
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST: $(access_hint)"
  show_running_services

  step "basic-memory http"
  show_http_answer "${BM_PORT:-$DEFAULT_BM_PORT}"

  step "uptime and disk"
  show_uptime_disk

  step "memory and swap"
  show_memory_swap

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
