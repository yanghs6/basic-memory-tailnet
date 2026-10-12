#!/usr/bin/env bash
# Copy compose.yaml and a generated .env to the VM, then pull and start Basic Memory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

main() {
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "upload compose.yaml to $BM_VM_HOST:$BM_REMOTE_APP_DIR"
  remote "cat > $BM_REMOTE_APP_DIR/compose.yaml" <"$REPO_DIR/compose.yaml" \
    || die "upload failed: is $BM_VM_HOST reachable over Tailscale SSH? (ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "write $BM_REMOTE_APP_DIR/.env"
  vm_env | remote "cat > $BM_REMOTE_APP_DIR/.env" || die "could not write $BM_REMOTE_APP_DIR/.env on the VM"

  step "pull image and start (waits up to ${HEALTH_TIMEOUT_SECONDS}s for healthy)"
  remote_compose "pull -q" || die "image pull failed on the VM: check its network, then 'make logs'"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "container did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"

  log "deployed. Next: make verify"
}

main "$@"
