#!/usr/bin/env bash
# Check that a pull request keeps its tests: from the merge base with BASE to HEAD, the number of '@test' lines in
# tests/*.bats must not fall and no added line in tests/*.bats or tests/helpers.bash may run skip, unless the PR body's
# last (trailer) paragraph carries 'Tests-Removed: <reason>' (docs/decisions/adr-2026-10-27-y9fxhf7x-test-integrity-guard.md).
# Changes nothing.
# Usage: PR_TITLE=<title> PR_BODY=<body> check-tests.sh BASE   (the pr-rules workflow passes origin/main and both texts)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

readonly TEST_FILES=':(glob)tests/*.bats'
readonly HELPER_FILE='tests/helpers.bash'
readonly TEST_LINE_PATTERN='^@test '
readonly MARKER='Tests-Removed'
readonly GIT_GREP_NO_MATCH=1
readonly FIX_HINT="add '$MARKER: <reason>' to the last paragraph of the PR body; editing the body re-runs pr-rules"

# test_count REV -> the number of '@test' lines in tests/*.bats at REV; 0 when there are none.
test_count() {
  local output status=0
  output="$(git grep -c -e "$TEST_LINE_PATTERN" "$1" -- "$TEST_FILES")" || status=$?
  ((status == 0 || status == GIT_GREP_NO_MATCH)) \
    || die "git grep could not count the tests at $1 (exit $status): check that the commit exists"
  awk -F: '{ sum += $NF } END { print sum + 0 }' <<<"$output"
}

# added_skips FROM TO -> 'path:line' of every line added between FROM and TO that runs skip: skip in command
# position (at the line start or after &&, ||, ;, |, { or (, optionally behind then, else or do) followed by a blank or
# the line end. A test name or a string that only contains the word does not count.
added_skips() {
  git diff -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ "$1" "$2" -- \
    "$TEST_FILES" "$HELPER_FILE" | awk '
    /^diff --git / { header = 1; next }
    header && /^\+\+\+ / { file = substr($0, 7); next }
    /^@@ / { header = 0; match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
    !header && /^\+/ {
      text = substr($0, 2)
      if (text ~ /^[ \t]*((then|else|do)[ \t]+)?skip([ \t]|$)/ ||
        text ~ /(&&|;|[{(|])[ \t]*((then|else|do)[ \t]+)?skip([ \t]|$)/) print file ":" line
      line++
    }'
}

# has_reason -> succeeds when the PR body's trailer paragraph carries a non-empty Tests-Removed value.
has_reason() {
  local trailers values
  trailers="$(pr_trailers "${PR_TITLE:-}" "${PR_BODY:-}")" || exit 1
  values="$(trailer_values "$MARKER" "$trailers")" || exit 1
  [[ "$values" =~ [^[:space:]] ]]
}

main() {
  local base_ref="${1:-}" base before after skips skip_count=0 path reason=""
  require_cmd git
  [[ -n "$base_ref" ]] || die "missing BASE: run check-tests.sh origin/main (or the branch this one grew from)"
  base="$(git merge-base "$base_ref" HEAD)" \
    || die "no merge base of $base_ref and HEAD: fetch the full history (git fetch origin; fetch-depth: 0 in CI) and pass the branch HEAD grew from"
  before="$(test_count "$base")" || exit 1
  after="$(test_count HEAD)" || exit 1
  skips="$(added_skips "$base" HEAD)" || die "git diff could not compare $base and HEAD: check that both commits exist"
  [[ -z "$skips" ]] || skip_count="$(wc -l <<<"$skips" | tr -d ' ')"
  if ((after < before || skip_count > 0)); then
    if has_reason; then
      reason=", with a $MARKER reason"
    else
      ((after >= before)) || add_problem "the number of @test lines in tests/*.bats fell: $before -> $after"
      while IFS= read -r path; do
        [[ -z "$path" ]] || add_problem "new skip at $path"
      done <<<"$skips"
      report_problems "Tests removed or skipped since the merge base ${base:0:12} ($FIX_HINT)"
    fi
  fi
  log "OK: tests since the merge base ${base:0:12}: @test $before -> $after, $skip_count new skip line(s)$reason"
}

main "$@"
