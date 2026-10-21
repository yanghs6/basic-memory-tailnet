#!/usr/bin/env bash
# Create a script and its pair test from the templates of the script-authoring skill: scripts/<name>.sh,
# scripts/remote/<name>.sh or scripts/lib/<name>.sh, and the test pair_test names. Script and remote names start with a
# verb from the table under "## Verbs" in that skill. Writes nothing when either file already exists, and leaves
# neither file when a write fails.
# Prints both paths on stdout. Spec: docs/specs/spec-2026-10-15-script-test-layout.md, section 8.3.
# Usage: make new-script NAME=<name> [KIND=script|remote|lib]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/layout.sh
. "$SCRIPT_DIR/lib/layout.sh"

readonly USAGE="usage: make new-script NAME=<name> [KIND=script|remote|lib]"
# Source guard variable of the library template; it becomes _BM_LIB_<NAME> with - turned into _.
readonly LIB_GUARD_PLACEHOLDER="_BM_LIB_NAME"

# check_name KIND NAME ROOT -> dies unless NAME fits KIND: a topic for lib, else <verb>-<object> with a verb from the
# skill's table in the repo at ROOT.
check_name() {
  local kind="$1" name="$2" root="$3" verbs verb
  if [[ "$kind" == lib ]]; then
    [[ "$name" =~ $LIB_NAME_PATTERN ]] || die "library name '$name' must be lowercase letters and digits joined by single hyphens"
    return 0
  fi
  [[ "$name" =~ $SCRIPT_NAME_PATTERN ]] \
    || die "script name '$name' must be <verb>-<object>: lowercase words joined by single hyphens, the verb first"
  verbs="$(script_verbs "$root/$SCRIPT_AUTHORING_SKILL")" || exit 1
  verb="${name%%-*}"
  grep -qxF "$verb" <<<"$verbs" \
    || die "'$verb' is not a verb of the table under '$VERBS_HEADING' in $SCRIPT_AUTHORING_SKILL: pick one, or add a row there"
}

main() {
  local name="${1:-}" kind="${2:-script}" root dir script pair path guard
  [[ -n "$name" ]] || die "$USAGE"
  dir="$(script_dir "$kind")" || die "$USAGE"
  script="$dir/$name.sh"
  require_cmd git
  root="$(git rev-parse --show-toplevel)" || die "run make new-script inside a checkout of this repo"
  check_name "$kind" "$name" "$root"
  pair="$(pair_test "$script")" || exit 1
  # Check both files before writing either, so a half-made pair never hides the existing file.
  for path in "$script" "$pair"; do
    [[ ! -e "$root/$path" ]] || die "$path already exists: edit it, or pick another name (nothing was written)"
  done
  for path in "$SCRIPT_TEMPLATES_DIR/$kind.sh" "$SCRIPT_TEMPLATES_DIR/$kind.bats"; do
    [[ -f "$root/$path" ]] || die "missing template $path (the script-authoring skill)"
  done
  guard="_BM_LIB_$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
  mkdir -p "$root/$dir" "$root/${pair%/*}"
  # Until both files are written, the EXIT trap removes them, so a failed write never leaves half a pair.
  # shellcheck disable=SC2064 # expand the paths now: the trap may run after main has returned
  trap "rm -f -- $(printf '%q ' "$root/$script" "$root/$pair")" EXIT
  sed -e "s/{{name}}/$name/g" -e "s/$LIB_GUARD_PLACEHOLDER/$guard/g" "$root/$SCRIPT_TEMPLATES_DIR/$kind.sh" >"$root/$script" \
    || die "could not write $script (nothing was written)"
  sed -e "s/{{name}}/$name/g" "$root/$SCRIPT_TEMPLATES_DIR/$kind.bats" >"$root/$pair" \
    || die "could not write $pair (nothing was written)"
  [[ "$kind" == lib ]] || chmod +x "$root/$script"
  trap - EXIT
  printf '%s\n%s\n' "$script" "$pair"
  log "created $script and $pair: write the test first and fill every {{...}} blank or delete its line"
  log "add a Make target with a ## description and .PHONY if people run it"
}

main "$@"
