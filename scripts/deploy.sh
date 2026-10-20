#!/usr/bin/env bash
# Copy compose.yaml, a generated .env and the SilverBullet space files to the VM, then pull and start Basic Memory
# and SilverBullet. While sb-space.sh reports the notes .gitignore as changed it has written only .gitignore: Basic
# Memory reads it only at start, so it is recreated first, the marker is cleared only after that succeeds (a failed
# run asks again), and sb-space.sh runs again to write the pages the recreated Basic Memory now ignores.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

main() {
  local gitignore_state env_file="$BM_REMOTE_APP_DIR/.env"
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  require_sb_user

  step "upload compose.yaml to $BM_VM_HOST:$BM_REMOTE_APP_DIR"
  remote "cat > $BM_REMOTE_APP_DIR/compose.yaml" <"$REPO_DIR/compose.yaml" \
    || die "upload failed: $(access_hint)"

  step "write $env_file (owner only: it holds SB_USER)"
  # umask covers only new files, so an existing .env is made owner-only before the login goes in.
  vm_env | remote "touch $env_file && chmod 600 $env_file && cat > $env_file" \
    || die "could not write $env_file on the VM"

  step "write the SilverBullet space files"
  gitignore_state="$("$SCRIPT_DIR/sb-space.sh")" || die "could not write the SilverBullet space files on the VM"

  step "pull images"
  remote_compose "pull -q" || die "image pull failed on the VM: check its network, then 'make logs'"
  if [[ "$gitignore_state" == changed ]]; then
    step "recreate Basic Memory so it loads the new notes .gitignore (waits up to ${HEALTH_TIMEOUT_SECONDS}s)"
    remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS --force-recreate basic-memory" \
      || die "Basic Memory did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"
    in_notes_dir "" "rm -f $SB_GITIGNORE_PENDING" </dev/null \
      || die "could not remove $SB_GITIGNORE_PENDING on the VM: the next deploy recreates Basic Memory again"
    step "write the SilverBullet pages now that Basic Memory ignores them"
    gitignore_state="$("$SCRIPT_DIR/sb-space.sh")" || die "could not write the SilverBullet pages on the VM"
    [[ "$gitignore_state" == unchanged ]] \
      || die "the notes .gitignore changed again during the deploy, so the SilverBullet pages were not written: run 'make deploy' again"
  fi
  step "start Basic Memory and SilverBullet (waits up to ${HEALTH_TIMEOUT_SECONDS}s for healthy)"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "containers did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"

  log "deployed. Next: make verify"
}

main "$@"
