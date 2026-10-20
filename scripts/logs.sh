#!/usr/bin/env bash
# Print recent Basic Memory container logs from the VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly LOG_TAIL_LINES=200

main() {
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  remote_compose "logs --tail=$LOG_TAIL_LINES" || die "could not read logs from $BM_VM_HOST"
}

main "$@"
