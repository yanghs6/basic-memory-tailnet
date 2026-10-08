#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs codex claude
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  cd "$WORK"
  git config user.email agent@example.com
  git config user.name agent
  git commit -q --allow-empty -m "chore: init"
  git switch -q -c plan/02-git-review-tooling
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out" REVIEW_WORKTREE_PARENT="$BATS_TEST_TMPDIR/wt"
  REVIEW="$REPO_DIR/scripts/review.sh"
  OUT="$REVIEW_OUT_DIR/plan-02-git-review-tooling"
}

# author_commit TOOL: a commit authored by TOOL (claude-code, codex, ...).
author_commit() {
  git commit -q --allow-empty -m "feat: change by $1" \
    --trailer "Assisted-by: $1 model-x" --trailer "Plan: 02" --trailer "Task: 1"
}

worktree_count() {
  git worktree list | wc -l | tr -d ' '
}

@test "codex reviews a claude-authored branch in a detached worktree and writes both reports" {
  author_commit claude-code
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  run cat "$OUT-r1-codex-diff.md"
  assert_output "codex diff review"
  run cat "$OUT-r1-codex-plan.md"
  assert_output "codex plan review"
  run grep -F 'codex exec review -c sandbox_mode="read-only" --base main :: cwd='"$REVIEW_WORKTREE_PARENT"'/review-plan-02-git-review-tooling-r1' "$STUB_LOG"
  assert_success
  run grep -F "codex exec --sandbox read-only -o $OUT-r1-codex-plan.md" "$STUB_LOG"
  assert_success
  run worktree_count
  assert_output 1
}

@test "claude reviews a codex-authored branch with the read-only reviewer agent" {
  author_commit codex
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run cat "$OUT-r1-claude-plan.md"
  assert_output "claude review"
}

@test "both claude reviews run as the guarded branch-reviewer agent in plan mode" {
  author_commit codex
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run grep -c "^claude " "$STUB_LOG"
  assert_output 2
  run grep -c "^claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence " "$STUB_LOG"
  assert_output 2
}

@test "the claude change review asks for git diff against the base instead of a slash command" {
  author_commit codex
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run grep -F "claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence Review the changes in git diff main...HEAD" "$STUB_LOG"
  assert_success
  run grep -F "branch-review skill" "$STUB_LOG"
  assert_success
  run grep -F "/code-review" "$STUB_LOG"
  assert_failure 1
}

@test "refuses a reviewer from the same vendor as the author" {
  author_commit claude-code
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_failure
  assert_output --partial "reviewer claude (claude-code) also authored commits on plan/02-git-review-tooling"
  run worktree_count
  assert_output 1
}

@test "allows a same-vendor review only when explicitly requested" {
  author_commit claude-code
  REVIEW_ALLOW_SAME_VENDOR=1 run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  assert_output --partial "WARNING: claude-code also authored commits"
}

@test "tells the reviewer only when the human allowed a same-vendor review" {
  author_commit claude-code
  REVIEW_ALLOW_SAME_VENDOR=1 run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run grep -F "The human set REVIEW_ALLOW_SAME_VENDOR=1" "$STUB_LOG"
  assert_success
  : >"$STUB_LOG"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  run grep -F "REVIEW_ALLOW_SAME_VENDOR" "$STUB_LOG"
  assert_failure 1
}

@test "round 2 reviews only commits after the reviewed head and leaves no temporary branch" {
  author_commit codex
  local reviewed
  reviewed="$(git rev-parse HEAD)"
  author_commit codex
  REVIEW_BASE="$reviewed" run "$REVIEW" plan/02-git-review-tooling claude 2
  assert_success
  run grep -F "Review the changes in git diff review-base/plan-02-git-review-tooling-r2...HEAD" "$STUB_LOG"
  assert_success
  run test -f "$OUT-r2-claude-diff.md"
  assert_success
  run git branch --list 'review-base/*'
  assert_output ""
}

@test "removes the worktree even when the reviewer fails" {
  author_commit claude-code
  CODEX_STUB_EXIT=1 run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "codex change review failed"
  run worktree_count
  assert_output 1
}

@test "refuses to reuse a stale review worktree and leaves it alone" {
  author_commit claude-code
  mkdir -p "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "a review worktree already exists"
  run test -d "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  assert_success
}

@test "refuses a leftover review-base branch and never deletes it" {
  author_commit codex
  local reviewed
  reviewed="$(git rev-parse HEAD)"
  author_commit codex
  git branch review-base/plan-02-git-review-tooling-r2 "$reviewed"
  REVIEW_BASE="$reviewed" run "$REVIEW" plan/02-git-review-tooling claude 2
  assert_failure
  assert_output --partial "review-base/plan-02-git-review-tooling-r2 already exists"
  run git rev-parse --verify --quiet refs/heads/review-base/plan-02-git-review-tooling-r2
  assert_success
  run worktree_count
  assert_output 1
}

@test "a failed review removes this round's earlier reports" {
  author_commit claude-code
  mkdir -p "$REVIEW_OUT_DIR"
  echo stale >"$OUT-r1-codex-diff.md"
  echo stale >"$OUT-r1-codex-plan.md"
  CODEX_STUB_EXIT=1 run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  run test -e "$OUT-r1-codex-diff.md"
  assert_failure
  run test -e "$OUT-r1-codex-plan.md"
  assert_failure
}

@test "a failed plan review leaves no half pair of reports" {
  author_commit claude-code
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

@test "a successful review leaves only the final pair of reports" {
  author_commit claude-code
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  run ls "$REVIEW_OUT_DIR"
  assert_output "plan-02-git-review-tooling-r1-codex-diff.md
plan-02-git-review-tooling-r1-codex-plan.md"
}

@test "rejects a relative REVIEW_OUT_DIR" {
  author_commit claude-code
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

@test "rejects a branch that does not exist" {
  run "$REVIEW" plan/09-nope codex
  assert_failure
  assert_output --partial "branch 'plan/09-nope' not found"
}
