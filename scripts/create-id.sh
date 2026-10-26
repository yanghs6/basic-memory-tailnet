#!/usr/bin/env bash
# Print one random document id that no file name under docs/ uses on any local or remote-tracking branch or in the
# working tree, so run git fetch origin first. Use it to name a plan branch before its document exists.
# Usage: make new-id
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/docs.sh
. "$SCRIPT_DIR/lib/docs.sh"

main() {
  local root
  require_cmd git
  root="$(git rev-parse --show-toplevel)" || die "run make new-id inside a checkout of this repo"
  new_doc_id "$root"
}

main "$@"
