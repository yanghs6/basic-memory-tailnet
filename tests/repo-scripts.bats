#!/usr/bin/env bats
load helpers

# Script rules: strict mode, bash 3.2, no Funnel, no template blank left by make new-script, and the layout checks of
# the script-test layout spec section 9 (pair tests, names, sources, the scripts/...sh paths the docs name). ADR 0007
# allows the layout and blank checks; the verbs come from the table in the script-authoring skill.

# A scripts/...sh path; example paths with < or { do not match it.
SCRIPT_PATH_PATTERN='scripts/[A-Za-z0-9_./-]+\.sh'
# A command that sources a .sh file (. FILE or source FILE), at the start of a line or after ;, &, |, (, {, $( or one of
# the words then, do, else.
SOURCES_SH='(^|[;&|({]|\$\(|(^|[[:space:]])(then|do|else))[[:space:]]*(\.|source)[[:space:]][^#]*\.sh'
# A line that sources common.sh: the sourced path ends in common.sh before any comment, so a comment naming
# common.sh does not count.
SOURCES_COMMON='^[[:space:]]*(\.|source)[[:space:]]+[^#]*[/"[:space:]]common\.sh"?[[:space:]]*(#.*)?$'
# A template blank: two opening braces, a letter, then text up to two closing braces. A generator's sed pattern for a
# blank ends in the sed delimiter (s/<blank>/<value>/), so a blank followed by / does not count. A test that checks a
# blank is gone escapes the braces in its pattern, so its file holds no two braces in a row and does not count either.
TEMPLATE_BLANK='\{\{[A-Za-z][^}]*\}\}([^/]|$)'

setup() {
  # shellcheck source=../scripts/lib/layout.sh
  . "$REPO_DIR/scripts/lib/layout.sh"
}

shell_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*'
}

# require_shell_files: set $files to the tracked shell files; fail loudly if git is unusable (no vacuous passes).
require_shell_files() {
  files="$(shell_files)" || fail "git ls-files failed inside the test container (see Makefile GIT_COMMON_DIR mount)"
  [[ "$files" == *tests/stubs/ssh* ]] || fail "git returned no files (expected at least tests/stubs/ssh)"
}

# script_path_refs: one "file:line:path" line per scripts/...sh path, code blocks included, in the maintained files
# (tracked and new): AGENTS.md, README.md, docs/ARCHITECTURE.md, the runbooks, the skills, the Makefile, .github and
# .claude/agents. Records (plans, specs, ADRs, reviews) keep old names and are left out (spec section 4).
script_path_refs() {
  git -C "$REPO_DIR" grep --untracked -I -n -o -E "$SCRIPT_PATH_PATTERN" -- AGENTS.md README.md docs/ARCHITECTURE.md \
    'docs/runbooks/*.md' .agents/skills Makefile .github .claude/agents
}

@test "every executable shell file enables strict mode" {
  local file files missing=""
  require_shell_files
  while IFS= read -r file; do
    # Libraries and the library template are sourced by scripts that already run in strict mode.
    case "$file" in
      *.bash | scripts/lib/* | "$SCRIPT_TEMPLATES_DIR/lib.sh") continue ;;
    esac
    grep -qx 'set -euo pipefail' "$REPO_DIR/$file" || missing="$missing $file"
  done <<<"$files"
  [[ -z "$missing" ]] || fail "add 'set -euo pipefail' right after the shebang in:$missing"
}

@test "scripts avoid bash 4+ features (macOS ships bash 3.2)" {
  refute_matches "$REPO_DIR/scripts" 'mapfile|readarray|declare -[Ann]|local -[Ann]|inherit_errexit|coproc|wait -n|\|&|&>>|\$\{[A-Za-z_][A-Za-z0-9_]*(\^|,)|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]'
}

@test "no script enables Tailscale Funnel" {
  refute_matches "$REPO_DIR/scripts" 'tailscale[[:space:]]+funnel' -i
}

@test "every script and library has its pair test, and every test that is not repo-*.bats pairs an existing script" {
  local kind dir path pair pairs="" scripts=0 tests=0 problems=""
  # shellcheck disable=SC2086 # SCRIPT_KINDS is a list of words
  for kind in $SCRIPT_KINDS; do
    dir="$(script_dir "$kind")" || fail "script_dir refused $kind"
    for path in "$REPO_DIR/$dir"/*.sh; do
      [[ -f "$path" ]] || continue
      path="${path#"$REPO_DIR"/}"
      pair="$(pair_test "$path")" || fail "pair_test refused $path"
      scripts=$((scripts + 1))
      pairs="$pairs$pair"$'\n'
      [[ -f "$REPO_DIR/$pair" ]] \
        || problems="$problems"$'\n'"  $path: no $pair; write it from $SCRIPT_TEMPLATES_DIR/$kind.bats"
    done
  done
  # A test must be the pair of some script. The map is many-to-one (scripts/remote-x.sh and scripts/remote/x.sh both
  # pair tests/remote-x.bats), so it is never inverted.
  for path in "$REPO_DIR"/tests/*.bats; do
    [[ -f "$path" ]] || continue
    path="${path#"$REPO_DIR"/}"
    case "$path" in tests/repo-*.bats) continue ;; esac
    tests=$((tests + 1))
    grep -qxF "$path" <<<"$pairs" \
      || problems="$problems"$'\n'"  $path: pairs no script; git mv it to the pair of the script it tests, or to tests/repo-<topic>.bats for a repo-wide rule"
  done
  ((scripts > 0 && tests > 0)) || fail "found $scripts scripts and $tests pair tests; expected some of each"
  [[ -z "$problems" ]] || fail "each script needs its pair test and each other test file a script (pair_test in scripts/lib/layout.sh: scripts/<name>.sh -> tests/<name>.bats, scripts/remote/<name>.sh -> tests/remote-<name>.bats, scripts/lib/<name>.sh -> tests/lib-<name>.bats; make new-script NAME=<name> [KIND=remote|lib] creates both for a new script):$problems"
}

@test "scripts in scripts/remote source no library" {
  refute_matches "$REPO_DIR/scripts/remote" "$SOURCES_SH" \
    || fail "scripts in scripts/remote run alone on the VM and source no .sh file: copy what they need into the script (see $SCRIPT_TEMPLATES_DIR/remote.sh)"
}

@test "every topic library sources common.sh" {
  local lib libs=0 missing=""
  for lib in "$REPO_DIR"/scripts/lib/*.sh; do
    [[ -f "$lib" && "${lib##*/}" != common.sh ]] || continue
    libs=$((libs + 1))
    grep -qE "$SOURCES_COMMON" "$lib" || missing="$missing"$'\n'"  ${lib#"$REPO_DIR"/}"
  done
  ((libs > 0)) || fail "found no library under scripts/lib other than common.sh"
  [[ -z "$missing" ]] || fail "add a line that sources common.sh, such as . \"\${BASH_SOURCE[0]%/*}/common.sh\" in $SCRIPT_TEMPLATES_DIR/lib.sh, to:$missing"
}

@test "every executable script is named <verb>-<object>.sh with a verb from the script-authoring table" {
  local verbs path name scripts=0 bad=""
  verbs="$(script_verbs "$REPO_DIR/$SCRIPT_AUTHORING_SKILL")" && [[ -n "$verbs" ]] \
    || fail "read no verbs from the table under '$VERBS_HEADING' in $SCRIPT_AUTHORING_SKILL"
  for path in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/remote/*.sh; do
    [[ -f "$path" ]] || continue
    scripts=$((scripts + 1))
    name="${path##*/}"
    name="${name%.sh}"
    if [[ ! "$name" =~ $SCRIPT_NAME_PATTERN ]]; then
      bad="$bad"$'\n'"  ${path#"$REPO_DIR"/}: '$name' is not <verb>-<object>"
    elif ! grep -qxF "${name%%-*}" <<<"$verbs"; then
      bad="$bad"$'\n'"  ${path#"$REPO_DIR"/}: '${name%%-*}' is not a verb of the table"
    fi
  done
  ((scripts > 0)) || fail "found no script under scripts or scripts/remote"
  [[ -z "$bad" ]] || fail "git mv each script and its pair test to <verb>-<object>.sh with a verb from the table under '$VERBS_HEADING' in $SCRIPT_AUTHORING_SKILL (${verbs//$'\n'/ }), or add a row there when no verb fits:$bad"
}

@test "scripts and tests hold no unfilled template blank" {
  local dir
  for dir in scripts tests; do
    refute_matches "$REPO_DIR/$dir" "$TEMPLATE_BLANK" \
      || fail "fill each blank that make new-script left in $dir/ (two braces around a phrase) or delete its line"
  done
}

@test "every scripts/…sh path in the maintained docs, skills, Makefile, .github and .claude/agents names an existing file" {
  local refs file line path broken=""
  refs="$(script_path_refs)" || fail "git grep found no scripts/...sh path in the maintained files, or failed"
  while IFS=: read -r file line path; do
    [[ -f "$REPO_DIR/$path" ]] || broken="$broken"$'\n'"  $file:$line: $path"
  done <<<"$refs"
  [[ -z "$broken" ]] || fail "these scripts/...sh paths name no file; point each at the current script (scripts/, scripts/remote/, scripts/lib/) or remove it:$broken"
}
