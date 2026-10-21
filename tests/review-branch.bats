#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs codex claude
  init_git_repo
  git switch -q -c plan/02-git-review-tooling
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out" REVIEW_WORKTREE_PARENT="$BATS_TEST_TMPDIR/wt"
  REVIEW="$REPO_DIR/scripts/review-branch.sh"
  OUT="$REVIEW_OUT_DIR/plan-02-git-review-tooling"
  REVIEW_WT="$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
}

worktree_count() {
  git worktree list | wc -l | tr -d ' '
}

# review_repo [TOOL...]: a new repo in place of the one setup made, on plan/02-git-review-tooling with one commit per TOOL
# (its Assisted-by tool), and no reports, review worktrees or stub log lines of an earlier case. It removes the repo
# setup made, so a test that calls it leaves that directory first and calls it in a subshell.
review_repo() {
  local tool
  rm -rf "$WORK" "$REVIEW_OUT_DIR" "$REVIEW_WORKTREE_PARENT" && : >"$STUB_LOG" \
    && init_git_repo && git switch -q -c plan/02-git-review-tooling || return 1
  for tool in "$@"; do
    agent_commit "$tool" "feat: change by $tool" || return 1
  done
}

@test "codex and claude review another vendor's branch in a detached worktree and write both reports; claude runs as the guarded branch-reviewer in plan mode without user or system git config" {
  local case reviewer author diff_report plan_report
  cd "$BATS_TEST_TMPDIR" || return
  # Each case: the reviewer | the tool that authored the branch | what the reviewer's stub writes as the change and
  # the plan report.
  for case in "codex|claude-code|codex diff review|codex plan review" "claude|codex|claude review|claude review"; do
    IFS='|' read -r reviewer author diff_report plan_report <<<"$case"
    (
      review_repo "$author" || exit 1
      run "$REVIEW" plan/02-git-review-tooling "$reviewer"
      assert_success || exit 1
      run cat "$OUT-r1-$reviewer-diff.md"
      assert_output "$diff_report" || exit 1
      run cat "$OUT-r1-$reviewer-plan.md"
      assert_output "$plan_report" || exit 1
      # Both reviewer calls run in the review worktree, which is gone afterwards.
      run grep -c -F ":: cwd=$REVIEW_WT" "$STUB_LOG"
      assert_output 2 || exit 1
      run worktree_count
      assert_output 1 || exit 1
      run ls "$REVIEW_OUT_DIR"
      assert_output "plan-02-git-review-tooling-r1-$reviewer-diff.md
plan-02-git-review-tooling-r1-$reviewer-meta.txt
plan-02-git-review-tooling-r1-$reviewer-plan.md" || exit 1
      run cat "$OUT-r1-$reviewer-meta.txt"
      assert_line "base $(git rev-parse main)" && assert_line "head $(git rev-parse plan/02-git-review-tooling)" || exit 1
      if [[ "$reviewer" == codex ]]; then
        assert_stub_called -F 'codex exec review -c sandbox_mode="read-only" --base main :: cwd='"$REVIEW_WT" \
          && assert_stub_called -F "codex exec --sandbox read-only -o $OUT-r1-codex-plan.md"
      else
        run grep -c "^claude " "$STUB_LOG"
        assert_output 2 || exit 1
        run grep -c "^claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence " "$STUB_LOG"
        assert_output 2 || exit 1
        # No user or system git config, so no external diff or textconv helper loads.
        run grep -c " git_config_global=/dev/null git_config_nosystem=1$" "$STUB_LOG"
        assert_output 2
      fi
    ) || fail "$reviewer review of a branch by $author"
  done
}

@test "refuses a same-vendor reviewer unless the human allowed it, and tells only that reviewer" {
  local case reviewer allowed outcome
  cd "$BATS_TEST_TMPDIR" || return
  # The branch has one claude-code commit. Each case: the reviewer | REVIEW_ALLOW_SAME_VENDOR | refused, told (the
  # prompt carries the human's consent) or untold (another vendor's review, whose prompt does not, with or without it).
  for case in "claude||refused" "claude|1|told" "codex||untold" "codex|1|untold"; do
    IFS='|' read -r reviewer allowed outcome <<<"$case"
    (
      review_repo claude-code || exit 1
      REVIEW_ALLOW_SAME_VENDOR="$allowed" run "$REVIEW" plan/02-git-review-tooling "$reviewer"
      case "$outcome" in
        refused)
          assert_failure \
            && assert_output --partial "reviewer claude (claude-code) also authored commits on plan/02-git-review-tooling" \
            || exit 1
          run worktree_count
          assert_output 1
          ;;
        told)
          assert_success && assert_output --partial "WARNING: claude-code also authored commits" \
            && assert_stub_called -F "The human set REVIEW_ALLOW_SAME_VENDOR=1"
          ;;
        untold) assert_success && refute_stub_called -F "REVIEW_ALLOW_SAME_VENDOR" ;;
      esac
    ) || fail "$reviewer review with REVIEW_ALLOW_SAME_VENDOR='$allowed' was not $outcome"
  done
}

@test "round 2 reviews only commits after the reviewed head and leaves no temporary branch" {
  agent_commit codex "feat: change by codex"
  local reviewed
  reviewed="$(git rev-parse HEAD)"
  agent_commit codex "feat: change by codex"
  REVIEW_BASE="$reviewed" run "$REVIEW" plan/02-git-review-tooling claude 2
  assert_success
  assert_stub_called -F "Review the changes in git diff review-base/plan-02-git-review-tooling-r2...HEAD"
  run test -f "$OUT-r2-claude-diff.md"
  assert_success
  run cat "$OUT-r2-claude-meta.txt"
  assert_line "base $reviewed"
  run git branch --list 'review-base/*'
  assert_output ""
}

@test "leaves no worktree and no report of the round when the change review or the plan review fails" {
  local case review fail_var stale report
  cd "$BATS_TEST_TMPDIR" || return
  # The branch has one claude-code commit. Each case: the codex review that fails | the stub variable that fails it |
  # the reports of this round an earlier run left.
  for case in "change|CODEX_STUB_EXIT|diff plan" "plan|CODEX_STUB_PLAN_EXIT|plan"; do
    IFS='|' read -r review fail_var stale <<<"$case"
    (
      review_repo claude-code && mkdir -p "$REVIEW_OUT_DIR" || exit 1
      for report in $stale; do
        echo stale >"$OUT-r1-codex-$report.md" || exit 1
      done
      export "$fail_var=1" || exit 1
      run "$REVIEW" plan/02-git-review-tooling codex
      assert_failure && assert_output --partial "codex $review review failed" || exit 1
      run worktree_count
      assert_output 1 || exit 1
      run test -e "$OUT-r1-codex-diff.md"
      assert_failure || exit 1
      run test -e "$OUT-r1-codex-plan.md"
      assert_failure
    ) || fail "the failed codex $review review left a worktree or a report"
  done
}

@test "refuses a stale review worktree, a leftover review-base branch, a relative REVIEW_OUT_DIR and an unknown reviewer, and leaves what exists alone" {
  local case input message
  cd "$BATS_TEST_TMPDIR" || return
  # Each case: what is in the way | the message of the check that refuses it. For the unknown reviewer that is the
  # allowlist in the usage text, the last field, so read keeps its |: without the allowlist check the run would still
  # fail, on the missing gemini command.
  for case in "stale review worktree|a review worktree already exists" \
    "leftover review-base branch|review-base/plan-02-git-review-tooling-r2 already exists" \
    "relative REVIEW_OUT_DIR|REVIEW_OUT_DIR must be an absolute path" \
    "unknown reviewer|REVIEWER=codex|claude"; do
    IFS='|' read -r input message <<<"$case"
    (
      case "$input" in
        "stale review worktree")
          review_repo claude-code && mkdir -p "$REVIEW_WT" || exit 1
          run "$REVIEW" plan/02-git-review-tooling codex
          ;;
        "leftover review-base branch")
          review_repo codex codex && git branch review-base/plan-02-git-review-tooling-r2 HEAD~1 || exit 1
          REVIEW_BASE="$(git rev-parse HEAD~1)" run "$REVIEW" plan/02-git-review-tooling claude 2
          ;;
        "relative REVIEW_OUT_DIR")
          review_repo claude-code || exit 1
          REVIEW_OUT_DIR=out run "$REVIEW" plan/02-git-review-tooling codex
          ;;
        "unknown reviewer")
          review_repo || exit 1
          run "$REVIEW" plan/02-git-review-tooling gemini
          ;;
      esac
      assert_failure && assert_output --partial "$message" && refute_stub_called -E '^(codex|claude) ' || exit 1
      run worktree_count
      assert_output 1 || exit 1
      case "$input" in
        "stale review worktree")
          run test -d "$REVIEW_WT"
          assert_success
          ;;
        "leftover review-base branch")
          run git rev-parse --verify --quiet refs/heads/review-base/plan-02-git-review-tooling-r2
          assert_success
          ;;
        "relative REVIEW_OUT_DIR")
          run test -e out
          assert_failure
          ;;
      esac
    ) || fail "review-branch did not refuse the $input or did not leave it alone"
  done
}
