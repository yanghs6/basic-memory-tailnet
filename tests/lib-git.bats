#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/git.sh
  . "$REPO_DIR/scripts/lib/git.sh"
}

@test "report_problems is silent without problems and lists every problem under its heading with exit 1" {
  [[ -z "${BM_CONTAINER_UID+x}" ]] || fail "git.sh must not load the VM settings"
  run report_problems "git policy violations"
  assert_success
  assert_output ""
  add_problem "first"
  add_problem "second"
  run report_problems "git policy violations"
  assert_failure 1
  assert_output "$(printf 'git policy violations:\n  - first\n  - second')"
}

@test "PLAN_PATTERN and BRANCH_PATTERN accept ids, and reject the two-digit forms and other lengths, capitals and i, l, o, u" {
  local value
  for value in k7m2x9qa none; do
    [[ "$value" =~ $PLAN_PATTERN ]] || fail "Plan: $value must be accepted"
  done
  for value in K7M2X9QA k7m2x9q k7m2x9qai k7m2x9qi k7m2x9ql k7m2x9qo k7m2x9qu 26 2 026; do
    [[ ! "$value" =~ $PLAN_PATTERN ]] || fail "Plan: $value must be rejected"
  done
  for value in plan/k7m2x9qa-x work/anything-x; do
    [[ "$value" =~ $BRANCH_PATTERN ]] || fail "branch $value must be accepted"
  done
  for value in plan/26-x plan/K7M2X9QA-x plan/k7m2x9q-x plan/k7m2x9qai-x plan/k7m2x9qi-x feature/x; do
    [[ ! "$value" =~ $BRANCH_PATTERN ]] || fail "branch $value must be rejected"
  done
}

@test "add_public_text_problems returns 0 on clean text, adds each hit with the hint and no value and returns 1, and dies when the check fails without a hit" {
  local cgnat case root
  # A CGNAT (tailnet range) address never sits in a repo file, so build it here.
  cgnat="$(printf '%s.%s' 100.101 102.103)"
  (
    rc=0 && { add_public_text_problems "PR body" "fix it" "Summary." || rc=$?; } \
      && ((rc == 0)) && [[ -z "$PROBLEMS" ]] || exit 1
  ) || fail "clean text was not passed without a problem"
  (
    rc=0 && { add_public_text_problems "PR body" "fix it" "Summary."$'\n'"Reach $cgnat." || rc=$?; } \
      && ((rc == 1)) && [[ "$PROBLEMS" == "  - PR body:2: IPv4 address (fix it)"* ]] && [[ "$PROBLEMS" != *"$cgnat"* ]] \
      || exit 1
  ) || fail "a hit was not added with the hint and without its value"
  # PUBLIC_TEXT_CHECK is readonly and follows the lib's own place, so a copy of the lib next to a broken checker (or
  # none) stands in for a checker that fails without a hit. The copy runs from a script file (kcov PS4 gotcha).
  for case in failing missing; do
    (
      root="$BATS_TEST_TMPDIR/$case" && mkdir -p "$root/scripts/lib" \
        && cp "$REPO_DIR/scripts/lib/common.sh" "$REPO_DIR/scripts/lib/git.sh" "$root/scripts/lib/" || exit 1
      if [[ "$case" == failing ]]; then
        printf '#!/usr/bin/env bash\necho broken >&2\nexit 2\n' >"$root/scripts/check-public-text.sh" \
          && chmod +x "$root/scripts/check-public-text.sh" || exit 1
      fi
      printf '#!/usr/bin/env bash\nset -euo pipefail\n. "%s/scripts/lib/git.sh"\nadd_public_text_problems "PR body" "fix it" "Summary." || true\necho survived\n' \
        "$root" >"$root/run.sh" || exit 1
      run bash "$root/run.sh"
      assert_failure && assert_output --partial "the public text check of PR body failed" \
        && refute_output --partial survived || exit 1
    ) || fail "a $case checker did not stop the caller"
  done
}

@test "review_report_prefix puts slug, round and reviewer in REVIEW_OUT_DIR, else in the main checkout's .review-out" {
  make_worktree_fixture
  cd "$LINKED_WT"
  REVIEW_OUT_DIR=/tmp/out run review_report_prefix plan/p6t4s2cg-script-cleanup 2 codex
  assert_output "/tmp/out/plan-p6t4s2cg-script-cleanup-r2-codex"
  unset REVIEW_OUT_DIR
  run review_report_prefix plan/p6t4s2cg-script-cleanup 1 claude
  assert_output "$MAIN_REPO/.review-out/plan-p6t4s2cg-script-cleanup-r1-claude"
}
