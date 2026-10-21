#!/usr/bin/env bash
# {{What this script does and what it changes, in one or two sentences.}}
# Usage: {{make <target> [ARG=<value>], the command people run}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# {{Source the scripts/lib/ library whose function index lists the helpers you need instead; each one sources common.sh.}}
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

main() {
  die "not implemented: write tests/{{name}}.bats first"
}

main "$@"
