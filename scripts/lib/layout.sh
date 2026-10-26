#!/usr/bin/env bash
# Script layout helpers for scripts/*.sh and the repo checks: the name rules of scripts and libraries, the verbs a
# script name starts with (the table under "## Verbs" in the script-authoring skill), the folder of each kind of script
# and the pair test of each script.
# Sources common.sh.
# Must stay compatible with macOS bash 3.2. Spec: docs/specs/spec-2026-10-15-d8q0b7bt-script-test-layout.md, sections 4 and 6.
#   script_verbs SKILL_FILE -> the first cell of every row of the table under "## Verbs", one per line
#   script_dir KIND -> the folder of a KIND of script: scripts, scripts/remote or scripts/lib
#   pair_test PATH -> the test file of scripts/<name>.sh, scripts/remote/<name>.sh or scripts/lib/<name>.sh
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_LAYOUT:-}" ] && return 0
readonly _BM_LIB_LAYOUT=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

# The script-authoring skill (its verb table is the canonical verb list) and its templates, relative to the repo root.
readonly SCRIPT_AUTHORING_SKILL=".agents/skills/script-authoring/SKILL.md"
readonly SCRIPT_TEMPLATES_DIR=".agents/skills/script-authoring/assets"
readonly VERBS_HEADING="## Verbs"
# Scripts and remote scripts are named <verb>-<object>: lowercase letters and digits joined by single hyphens, the verb
# first. A library is named after its topic with the same characters.
readonly SCRIPT_NAME_PATTERN='^[a-z0-9]+(-[a-z0-9]+)+$'
readonly LIB_NAME_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# The kinds of script make new-script creates, each with a template pair in SCRIPT_TEMPLATES_DIR; script_dir names the
# folder of each.
readonly SCRIPT_KINDS="script remote lib"

# script_verbs SKILL_FILE -> one line per body row of the table under VERBS_HEADING: its first cell without backticks
# and the spaces around it. The first two table lines are the header and the separator. Dies when the heading or the
# table is missing, the second table line is not a separator row or a first cell is empty, so no check runs against a
# partial verb list.
script_verbs() {
  local skill="$1" verbs status=0
  [[ -f "$skill" ]] || die "missing $skill: its '$VERBS_HEADING' table lists the verbs of script names"
  verbs="$(awk -v heading="$VERBS_HEADING" '
    /^## / { inside = ($0 == heading); if (inside) found = 1; next }
    !inside || !/^\|/ { next }
    { lines++ }
    lines == 2 && $0 !~ /^\|( *:?-+:? *\|)+ *$/ {
      printf "the separator row (|---|) must follow the header, not: %s\n", $0 > "/dev/stderr"; bad = 1
    }
    lines <= 2 { next }
    {
      split($0, cells, "|")
      verb = cells[2]
      gsub(/`/, "", verb)
      gsub(/^ +| +$/, "", verb)
      if (verb == "") { printf "row %d has an empty first cell: %s\n", lines - 2, $0 > "/dev/stderr"; bad = 1; next }
      print verb
    }
    END {
      if (!found) { print "no heading" > "/dev/stderr"; bad = 1 }
      else if (lines <= 2) { print "no verb rows under the heading" > "/dev/stderr"; bad = 1 }
      exit bad
    }
  ' "$skill")" || status=$?
  ((status == 0)) || die "fix the table under '$VERBS_HEADING' in $skill (| verb | meaning | example |, see the lines above)"
  printf '%s\n' "$verbs"
}

# script_dir KIND -> the repo-relative folder of a KIND of script: scripts for script, scripts/remote for remote,
# scripts/lib for lib. Dies on any other KIND.
script_dir() {
  case "$1" in
    script) printf 'scripts\n' ;;
    remote) printf 'scripts/remote\n' ;;
    lib) printf 'scripts/lib\n' ;;
    *) die "KIND must be one of: $SCRIPT_KINDS (not '$1')" ;;
  esac
}

# pair_test PATH -> the repo-relative test file of a repo-relative script path: scripts/<name>.sh -> tests/<name>.bats,
# scripts/remote/<name>.sh -> tests/remote-<name>.bats, scripts/lib/<name>.sh -> tests/lib-<name>.bats. Dies on any
# other path, because scripts and tests stay flat (spec section 6).
pair_test() {
  local path="$1"
  if [[ "$path" =~ ^scripts/remote/([^/]+)\.sh$ ]]; then
    printf 'tests/remote-%s.bats\n' "${BASH_REMATCH[1]}"
  elif [[ "$path" =~ ^scripts/lib/([^/]+)\.sh$ ]]; then
    printf 'tests/lib-%s.bats\n' "${BASH_REMATCH[1]}"
  elif [[ "$path" =~ ^scripts/([^/]+)\.sh$ ]]; then
    printf 'tests/%s.bats\n' "${BASH_REMATCH[1]}"
  else
    die "$path has no pair test: only scripts/<name>.sh, scripts/remote/<name>.sh and scripts/lib/<name>.sh have one"
  fi
}
