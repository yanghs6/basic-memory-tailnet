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

@test "review_report_prefix puts slug, round and reviewer in REVIEW_OUT_DIR, else in the main checkout's .review-out" {
  make_worktree_fixture
  cd "$LINKED_WT"
  REVIEW_OUT_DIR=/tmp/out run review_report_prefix plan/16-script-cleanup 2 codex
  assert_output "/tmp/out/plan-16-script-cleanup-r2-codex"
  unset REVIEW_OUT_DIR
  run review_report_prefix plan/16-script-cleanup 1 claude
  assert_output "$MAIN_REPO/.review-out/plan-16-script-cleanup-r1-claude"
}
