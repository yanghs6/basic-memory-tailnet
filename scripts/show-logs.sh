#!/usr/bin/env bash
# Print recent Basic Memory container logs from the VM.
# Usage: make logs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly LOG_TAIL_LINES=200

main() {
  require_vm
  remote_compose "logs --tail=$LOG_TAIL_LINES" || die "could not read logs from $BM_VM_HOST: $(access_hint)"
}

main "$@"
