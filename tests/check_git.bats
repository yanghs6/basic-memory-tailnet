#!/usr/bin/env bats
load helpers

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  cd "$WORK"
  git config user.email agent@example.com
  git config user.name agent
  git commit -q --allow-empty -m "chore: init"
  CHECK="$REPO_DIR/scripts/check-git.sh"
}

# agent_commit SUBJECT [extra git commit args...]: a policy-compliant agent commit.
agent_commit() {
  local subject="$1"
  shift
  git commit -q --allow-empty -m "$subject" \
    --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 02" --trailer "Task: 1" "$@"
}

@test "passes on a plan branch whose commits carry every trailer" {
  git switch -q -c plan/02-git-review-tooling
  agent_commit "feat: add check"
  run "$CHECK"
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "accepts work branches with Plan none and Task review" {
  git switch -q -c work/fix-docs
  git commit -q --allow-empty -m "docs: record review" \
    --trailer "Assisted-by: codex gpt-5-codex" --trailer "Plan: none" --trailer "Task: review"
  run "$CHECK"
  assert_success
}

@test "fails on main because agents never commit to main" {
  run "$CHECK"
  assert_failure
  assert_output --partial "on main: agents never commit to main"
}

@test "fails in detached HEAD" {
  git checkout -q --detach
  run "$CHECK"
  assert_failure
  assert_output --partial "detached HEAD: create a branch first"
}

@test "fails on a branch name outside plan/ and work/" {
  git switch -q -c feature/x
  run "$CHECK"
  assert_failure
  assert_output --partial "branch 'feature/x' must look like plan/NN-slug or work/slug"
}

@test "lists every missing trailer with the commit" {
  git switch -q -c work/no-trailers
  git commit -q --allow-empty -m "feat: no trailers"
  run "$CHECK"
  assert_failure
  assert_output --partial '"feat: no trailers": missing trailer '"'"'Assisted-by:'
  assert_output --partial "missing trailer 'Plan:"
  assert_output --partial "missing trailer 'Task:"
}

@test "rejects malformed trailer values" {
  git switch -q -c work/bad-values
  git commit -q --allow-empty -m "feat: bad values" \
    --trailer "Assisted-by: Claude" --trailer "Plan: 1" --trailer "Task: first"
  run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Assisted-by: Claude' must be"
  assert_output --partial "trailer 'Plan: 1' must be"
  assert_output --partial "trailer 'Task: first' must be"
}

@test "rejects Co-authored-by and Signed-off-by" {
  git switch -q -c work/attribution
  agent_commit "feat: attributed" --trailer "Co-authored-by: Bot <bot@example.com>" --signoff
  run "$CHECK"
  assert_failure
  assert_output --partial "agents never add 'Co-authored-by'"
  assert_output --partial "agents never add 'Signed-off-by'"
}

@test "flags extensions.worktreeConfig because it breaks Antigravity" {
  git switch -q -c work/config
  git config extensions.worktreeConfig true
  run "$CHECK"
  assert_failure
  assert_output --partial "git config --unset extensions.worktreeConfig"
}

@test "ignores merge commits brought into the branch" {
  git switch -q -c plan/02-merge
  agent_commit "feat: on branch"
  git switch -q main
  git commit -q --allow-empty -m "chore: on main"
  git switch -q plan/02-merge
  git merge -q --no-ff main -m "Merge main"
  run "$CHECK"
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "fails clearly when the base branch does not exist" {
  git switch -q -c work/x
  run "$CHECK" nope
  assert_failure
  assert_output --partial "base branch 'nope' not found"
}

@test "checks an explicit branch from a detached HEAD" {
  git switch -q -c plan/02-git-review-tooling
  agent_commit "feat: add check"
  git checkout -q --detach main
  run "$CHECK" main plan/02-git-review-tooling
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "reports the explicit branch's commits, not HEAD's, from a detached HEAD" {
  git switch -q -c work/no-trailers
  git commit -q --allow-empty -m "feat: no trailers"
  git checkout -q --detach main
  run "$CHECK" main work/no-trailers
  assert_failure
  assert_output --partial '"feat: no trailers": missing trailer'
  refute_output --partial "detached HEAD"
}

@test "applies the branch-name rule to an explicit branch" {
  git switch -q -c feature/x
  agent_commit "feat: on a badly named branch"
  git checkout -q --detach main
  run "$CHECK" main feature/x
  assert_failure
  assert_output --partial "branch 'feature/x' must look like plan/NN-slug or work/slug"
}

@test "fails clearly when the explicit branch does not exist" {
  run "$CHECK" main plan/09-nope
  assert_failure
  assert_output --partial "branch 'plan/09-nope' not found"
}
