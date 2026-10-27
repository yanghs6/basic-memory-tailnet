#!/usr/bin/env bash
# Copy compose.yaml and a generated .env to the VM, pull the images, write the SilverBullet space files, then start
# Basic Memory and SilverBullet. When the notes .gitignore changed, sb_space_apply (scripts/lib/sb.sh) recreates Basic
# Memory first, because it reads .gitignore only at start, and writes the pages only after that.
# With BM_WEB=on it also uploads the gateway runtime files and the web settings (the VM .env turns on the gateway and
# the tunnel); with BM_WEB off it removes the web containers a former deploy left behind.
# Usage: make deploy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

# Compose services of the web connector: removed after a deploy with BM_WEB off.
readonly WEB_SERVICES="gateway cloudflared"

# recreate_basic_memory -> recreate the Basic Memory container so it loads the new notes .gitignore; waits for healthy.
recreate_basic_memory() {
  step "recreate Basic Memory so it loads the new notes .gitignore (waits up to ${HEALTH_TIMEOUT_SECONDS}s)"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS --force-recreate basic-memory" \
    || die "Basic Memory did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"
}

main() {
  local env_file="$BM_REMOTE_APP_DIR/.env"
  require_vm
  require_sb_user
  require_web_settings

  step "upload compose.yaml to $BM_VM_HOST:$BM_REMOTE_APP_DIR"
  remote "cat > $BM_REMOTE_APP_DIR/compose.yaml" <"$REPO_DIR/compose.yaml" \
    || die "upload failed: $(access_hint)"
  upload_gateway_files

  step "write $env_file (owner only: it holds SB_USER and the web settings)"
  # umask covers only new files, so an existing .env is made owner-only before the login goes in.
  vm_env | remote "touch $env_file && chmod 600 $env_file && cat > $env_file" \
    || die "could not write $env_file on the VM"

  step "pull images"
  remote_compose "pull -q" || die "image pull failed on the VM: check its network, then 'make logs'"

  step "write the SilverBullet space files"
  sb_space_apply vm "run 'make deploy' again" recreate_basic_memory

  step "start Basic Memory and SilverBullet (waits up to ${HEALTH_TIMEOUT_SECONDS}s for healthy)"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "containers did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"

  if [[ "$(web_mode)" == off ]]; then
    step "remove web connector containers left by an earlier deploy"
    remote_compose "rm --stop --force $WEB_SERVICES" || die "could not remove the web connector containers: run 'make logs'"
  fi

  log "deployed. Next: make verify"
}

main "$@"
