#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs codex claude
  init_git_repo
  git switch -q -c plan/02-git-review-tooling
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out" REVIEW_WORKTREE_PARENT="$BATS_TEST_TMPDIR/wt"
  REVIEW="$REPO_DIR/scripts/review-branch.sh"
  OUT="$REVIEW_OUT_DIR/plan-02-git-review-tooling"
}

worktree_count() {
  git worktree list | wc -l | tr -d ' '
}

@test "codex reviews a claude-authored branch in a detached worktree and writes both reports" {
  agent_commit claude-code "feat: change by claude-code"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  run cat "$OUT-r1-codex-diff.md"
  assert_output "codex diff review"
  run cat "$OUT-r1-codex-plan.md"
  assert_output "codex plan review"
  assert_stub_called -F 'codex exec review -c sandbox_mode="read-only" --base main :: cwd='"$REVIEW_WORKTREE_PARENT"'/review-plan-02-git-review-tooling-r1'
  assert_stub_called -F "codex exec --sandbox read-only -o $OUT-r1-codex-plan.md"
  run worktree_count
  assert_output 1
  run ls "$REVIEW_OUT_DIR"
  assert_output "plan-02-git-review-tooling-r1-codex-diff.md
plan-02-git-review-tooling-r1-codex-meta.txt
plan-02-git-review-tooling-r1-codex-plan.md"
  run cat "$OUT-r1-codex-meta.txt"
  assert_line "base $(git rev-parse main)"
  assert_line "head $(git rev-parse plan/02-git-review-tooling)"
}

@test "both claude reviews run as the guarded branch-reviewer agent in plan mode" {
  agent_commit codex "feat: change by codex"
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run cat "$OUT-r1-claude-plan.md"
  assert_output "claude review"
  run grep -c "^claude " "$STUB_LOG"
  assert_output 2
  run grep -c "^claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence " "$STUB_LOG"
  assert_output 2
}

@test "claude reviews run without user or system git config, so no external diff or textconv helper loads" {
  agent_commit codex "feat: change by codex"
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run grep -c " git_config_global=/dev/null git_config_nosystem=1$" "$STUB_LOG"
  assert_output 2
}

@test "refuses a reviewer from the same vendor as the author" {
  agent_commit claude-code "feat: change by claude-code"
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_failure
  assert_output --partial "reviewer claude (claude-code) also authored commits on plan/02-git-review-tooling"
  run worktree_count
  assert_output 1
}

@test "tells the reviewer only when the human allowed a same-vendor review" {
  agent_commit claude-code "feat: change by claude-code"
  REVIEW_ALLOW_SAME_VENDOR=1 run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  assert_output --partial "WARNING: claude-code also authored commits"
  assert_stub_called -F "The human set REVIEW_ALLOW_SAME_VENDOR=1"
  : >"$STUB_LOG"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  refute_stub_called -F "REVIEW_ALLOW_SAME_VENDOR"
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

@test "removes the worktree and this round's earlier reports even when the reviewer fails" {
  agent_commit claude-code "feat: change by claude-code"
  mkdir -p "$REVIEW_OUT_DIR"
  echo stale >"$OUT-r1-codex-diff.md"
  echo stale >"$OUT-r1-codex-plan.md"
  CODEX_STUB_EXIT=1 run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "codex change review failed"
  run worktree_count
  assert_output 1
  run test -e "$OUT-r1-codex-diff.md"
  assert_failure
  run test -e "$OUT-r1-codex-plan.md"
  assert_failure
}

@test "refuses to reuse a stale review worktree and leaves it alone" {
  agent_commit claude-code "feat: change by claude-code"
  mkdir -p "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "a review worktree already exists"
  run test -d "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  assert_success
}

@test "refuses a leftover review-base branch and never deletes it" {
  agent_commit codex "feat: change by codex"
  local reviewed
  reviewed="$(git rev-parse HEAD)"
  agent_commit codex "feat: change by codex"
  git branch review-base/plan-02-git-review-tooling-r2 "$reviewed"
  REVIEW_BASE="$reviewed" run "$REVIEW" plan/02-git-review-tooling claude 2
  assert_failure
  assert_output --partial "review-base/plan-02-git-review-tooling-r2 already exists"
  run git rev-parse --verify --quiet refs/heads/review-base/plan-02-git-review-tooling-r2
  assert_success
  run worktree_count
  assert_output 1
}

@test "a failed plan review leaves no half pair of reports" {
  agent_commit claude-code "feat: change by claude-code"
  mkdir -p "$REVIEW_OUT_DIR"
  echo stale >"$OUT-r1-codex-plan.md"
  CODEX_STUB_PLAN_EXIT=1 run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "codex plan review failed"
  run test -e "$OUT-r1-codex-diff.md"
  assert_failure
  run test -e "$OUT-r1-codex-plan.md"
  assert_failure
}

@test "rejects a relative REVIEW_OUT_DIR" {
  agent_commit claude-code "feat: change by claude-code"
  REVIEW_OUT_DIR=out run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "REVIEW_OUT_DIR must be an absolute path"
  run test -e out
  assert_failure
}

@test "rejects an unknown reviewer" {
  run "$REVIEW" plan/02-git-review-tooling gemini
  assert_failure
  assert_output --partial "usage: make review BRANCH="
}
