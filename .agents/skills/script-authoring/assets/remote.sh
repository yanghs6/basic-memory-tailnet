#!/usr/bin/env bash
# Runs ON the VM. {{What it does there, in one sentence.}}
# It is uploaded alone, so it sources no library and keeps its own log, die and constants.
# Usage: {{uploaded and run by scripts/<caller>.sh (make <target>)}}
set -euo pipefail

log() { printf '[{{name}}] %s\n' "$*" >&2; }

die() {
  printf '[{{name}}] ERROR: %s\n' "$*" >&2
  exit 1
}

main() {
  log "{{what the first step does}}"
  die "not implemented: write tests/remote-{{name}}.bats first"
}

main "$@"
