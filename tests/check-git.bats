#!/usr/bin/env bats
load helpers

setup() {
  init_git_repo
  CHECK="$REPO_DIR/scripts/check-git.sh"
}

@test "passes on a plan branch whose commits carry every trailer" {
  git switch -q -c plan/02-git-review-tooling
  agent_commit claude-code "feat: add check"
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
  agent_commit claude-code "feat: attributed" --trailer "Co-authored-by: Bot <bot@example.com>" --signoff
  run "$CHECK"
  assert_failure
  assert_output --partial "agents never add 'Co-authored-by'"
  assert_output --partial "agents never add 'Signed-off-by'"
}

@test "flags extensions.worktreeConfig whatever its value, including false" {
  git switch -q -c work/config
  local value
  for value in 1 yes false; do
    git config extensions.worktreeConfig "$value"
    run "$CHECK"
    [[ "$status" -eq 1 ]] || fail "expected value '$value' to be flagged; got $status: $output"
    assert_output --partial "extensions.worktreeConfig is set (value '$value')"
    assert_output --partial "git config --unset-all extensions.worktreeConfig"
  done
}

@test "ignores merge commits brought into the branch" {
  git switch -q -c plan/02-merge
  agent_commit claude-code "feat: on branch"
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
  agent_commit claude-code "feat: add check"
  git checkout -q --detach main
  run "$CHECK" main plan/02-git-review-tooling
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "applies the branch-name rule to an explicit branch" {
  git switch -q -c feature/x
  agent_commit claude-code "feat: on a badly named branch"
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
