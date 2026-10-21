#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out"
  mkdir -p "$REVIEW_OUT_DIR"
  POST="$REPO_DIR/scripts/post-review.sh"
  PREFIX="$REVIEW_OUT_DIR/plan-09-review-posting-r1-codex"
  echo "Verdict: mergeable" >"$PREFIX-diff.md"
  echo "Verdict: blocked (1 P0/P1)" >"$PREFIX-plan.md"
  printf 'base %s\nhead %s\n' 1111111 2222222 >"$PREFIX-meta.txt"
}

@test "posts the change and plan reviews as two PR comments headed by round, reviewer, model and the reviewed SHAs" {
  REVIEW_MODEL=gpt-6.1-sol run "$POST" 12 plan/09-review-posting codex
  assert_success
  run grep -c '^gh pr comment 12 --body-file ' "$STUB_LOG"
  assert_output 2
  run cat "$STUB_LOG.body"
  assert_line "## Agent review R1: codex (gpt-6.1-sol)"
  # shellcheck disable=SC2016 # the backticks are literal Markdown, not a command substitution
  assert_line 'Base `1111111`, reviewed head `2222222`.'
  assert_line "### Change review"
  assert_line "Verdict: mergeable"
  assert_line "### Plan review"
  assert_line "Verdict: blocked (1 P0/P1)"
}

@test "posts nothing when a file of the round is missing" {
  rm "$PREFIX-plan.md"
  run "$POST" 12 plan/09-review-posting codex
  assert_failure
  assert_output --partial "missing $PREFIX-plan.md"
  refute_stub_called '^gh '
}

@test "posts nothing when either report is too long for one GitHub comment" {
  head -c 70000 /dev/zero | tr '\0' x >"$PREFIX-plan.md"
  run "$POST" 12 plan/09-review-posting codex
  assert_failure
  assert_output --partial "over GitHub's 65536 limit"
  refute_stub_called '^gh '
}
