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

@test "review_report_prefix puts slug, round and reviewer in REVIEW_OUT_DIR, else in the main checkout's .review-out" {
  make_worktree_fixture
  cd "$LINKED_WT"
  REVIEW_OUT_DIR=/tmp/out run review_report_prefix plan/p6t4s2cg-script-cleanup 2 codex
  assert_output "/tmp/out/plan-p6t4s2cg-script-cleanup-r2-codex"
  unset REVIEW_OUT_DIR
  run review_report_prefix plan/p6t4s2cg-script-cleanup 1 claude
  assert_output "$MAIN_REPO/.review-out/plan-p6t4s2cg-script-cleanup-r1-claude"
}
