#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out"
  POST="$REPO_DIR/scripts/post-review.sh"
  PREFIX="$REVIEW_OUT_DIR/plan-n3q8d5vb-review-posting-r1-codex"
  write_reports
}

# write_reports: the three files make review writes for round 1 of plan/n3q8d5vb-review-posting by codex, and nothing else in
# REVIEW_OUT_DIR. The meta file names the reviewer model, the reasoning effort and the make check result.
write_reports() {
  rm -rf "$REVIEW_OUT_DIR" && mkdir -p "$REVIEW_OUT_DIR" \
    && echo "Verdict: mergeable" >"$PREFIX-diff.md" \
    && echo "Verdict: blocked (1 P0/P1)" >"$PREFIX-plan.md" \
    && printf 'base %s\nhead %s\nmodel %s\neffort %s\ncheck %s\n' 1111111 2222222 gpt-6.1-sol high 'failed (exit 2)' \
      >"$PREFIX-meta.txt"
}

@test "posts the change and plan reviews as two PR comments headed by the round, reviewer and the meta file's model, effort, SHAs and check result" {
  # REVIEW_MODEL from the environment must not reach the header: the meta file records what the reviewer ran with.
  REVIEW_MODEL=other-model run "$POST" 12 plan/n3q8d5vb-review-posting codex
  assert_success
  run grep -c '^gh pr comment 12 --body-file ' "$STUB_LOG"
  assert_output 2
  run cat "$STUB_LOG.body"
  assert_line "## Agent review R1: codex (gpt-6.1-sol, effort high)"
  # shellcheck disable=SC2016 # the backticks are literal Markdown, not a command substitution
  assert_line 'Base `1111111`, reviewed head `2222222`. make check on the reviewed head: failed (exit 2).'
  assert_line "### Change review"
  assert_line "Verdict: mergeable"
  assert_line "### Plan review"
  assert_line "Verdict: blocked (1 P0/P1)"
  # The pull request is public: the posted bodies never name the local report directory.
  run grep -c -F "$REVIEW_OUT_DIR" "$STUB_LOG.body"
  assert_output 0
}

@test "posts nothing when a file of the round is missing, too long, carries public text or comes from an older make review" {
  local case problem message cgnat
  # A CGNAT (tailnet range) address never sits in a repo file, so build it here; tests/lib-git.bats covers the check.
  cgnat="$(printf '%s.%s' 100.101 102.103)"
  # Each case: what is wrong with the plan report | the message of the check that stops before any gh call.
  for case in "missing|missing $PREFIX-plan.md" "too long|over GitHub's 65536 limit" \
    "public text|$PREFIX-plan.md:2: IPv4 address" "old meta|names no model"; do
    IFS='|' read -r problem message <<<"$case"
    (
      write_reports && : >"$STUB_LOG" || exit 1
      case "$problem" in
        missing) rm "$PREFIX-plan.md" || exit 1 ;;
        "too long") head -c 70000 /dev/zero | tr '\0' x >"$PREFIX-plan.md" || exit 1 ;;
        "public text") printf 'Reach %s.\n' "$cgnat" >>"$PREFIX-plan.md" || exit 1 ;;
        "old meta") printf 'base %s\nhead %s\n' 1111111 2222222 >"$PREFIX-meta.txt" || exit 1 ;;
      esac
      run "$POST" 12 plan/n3q8d5vb-review-posting codex
      assert_failure && assert_output --partial "$message" && refute_stub_called '^gh ' \
        && refute_output --partial "$cgnat"
    ) || fail "post-review did not stop before gh on a plan report: $problem"
  done
}
