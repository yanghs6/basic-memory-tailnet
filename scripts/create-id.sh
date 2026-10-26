#!/usr/bin/env bash
# Print one random document id that no file name under docs/ uses on any local or remote-tracking branch or in the
# working tree, so run git fetch origin first. Use it for a draft on the Basic Memory draft board (doc-authoring); a plan branch takes its plan file's id.
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
