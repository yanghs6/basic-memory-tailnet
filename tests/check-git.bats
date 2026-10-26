#!/usr/bin/env bats
load helpers

setup() {
  init_git_repo
  CHECK="$REPO_DIR/scripts/check-git.sh"
}

@test "passes plan and work branches whose commits carry every trailer, with a merge from main and as an explicit branch from a detached HEAD" {
  local case
  # Each case rebuilds the repo of setup in its own subshell, so the test leaves it first.
  cd "$BATS_TEST_TMPDIR" || return
  for case in "work branch with Plan none and Task review" "plan branch with a merge from main" \
    "explicit branch from a detached HEAD" "id-named plan branch with an id Plan trailer"; do
    (
      rm -rf "$WORK" && init_git_repo || exit 1
      case "$case" in
        "work branch"*)
          git switch -q -c work/fix-docs \
            && git commit -q --allow-empty -m "docs: record review" \
              --trailer "Assisted-by: codex gpt-5-codex" --trailer "Plan: none" --trailer "Task: review" \
            || exit 1
          run "$CHECK"
          ;;
        "plan branch"*)
          git switch -q -c plan/k7m2x9qa-merge && agent_commit claude-code "feat: on branch" \
            && git switch -q main && git commit -q --allow-empty -m "chore: on main" \
            && git switch -q plan/k7m2x9qa-merge && git merge -q --no-ff main -m "Merge main" || exit 1
          run "$CHECK"
          ;;
        "id-named"*)
          git switch -q -c plan/k7m2x9qa-x && PLAN_TRAILER=k7m2x9qa agent_commit claude-code "feat: id branch" || exit 1
          run "$CHECK"
          ;;
        "explicit branch"*)
          git switch -q -c plan/k7m2x9qa-git-review-tooling && agent_commit claude-code "feat: add check" \
            && git checkout -q --detach main || exit 1
          run "$CHECK" main plan/k7m2x9qa-git-review-tooling
          ;;
      esac
      # One commit each: the merge commit and the commit it brings from main are not counted.
      assert_success && assert_output --partial "OK: git policy (1 commits since main)"
    ) || fail "check-git did not pass the $case"
  done
}

@test "fails on main, a detached HEAD and a branch outside plan/ and work/, also as an explicit branch" {
  local case place message
  cd "$BATS_TEST_TMPDIR" || return
  # Each case: where check-git.sh runs | the branch problem it reports.
  for case in "main|on main: agents never commit to main" \
    "detached HEAD|detached HEAD: create a branch first" \
    "feature/x|branch 'feature/x' must look like plan/<id>-slug or work/slug" \
    "plan/26-x|branch 'plan/26-x' must look like" \
    "plan/K7M2X9QA-x|branch 'plan/K7M2X9QA-x' must look like" \
    "plan/k7m2x9q-x|branch 'plan/k7m2x9q-x' must look like" \
    "plan/k7m2x9qai-x|branch 'plan/k7m2x9qai-x' must look like" \
    "explicit feature/x|branch 'feature/x' must look like plan/<id>-slug or work/slug"; do
    IFS='|' read -r place message <<<"$case"
    (
      rm -rf "$WORK" && init_git_repo || exit 1
      case "$place" in
        main) run "$CHECK" ;;
        "detached HEAD")
          git checkout -q --detach || exit 1
          run "$CHECK"
          ;;
        feature/x | plan/*)
          git switch -q -c "$place" || exit 1
          run "$CHECK"
          ;;
        "explicit feature/x")
          git switch -q -c feature/x && agent_commit claude-code "feat: on a badly named branch" \
            && git checkout -q --detach main || exit 1
          run "$CHECK" main feature/x
          ;;
      esac
      assert_failure && assert_output --partial "$message"
    ) || fail "check-git did not refuse to run on: $place"
  done
}

@test "lists every missing, malformed and forbidden trailer with its commit" {
  local case problem subject problems line
  cd "$BATS_TEST_TMPDIR" || return
  # Each case: the trailers' problem | the commit subject | what check-git.sh lists after that subject, |-separated.
  for case in "missing|feat: no trailers|missing trailer 'Assisted-by:|missing trailer 'Plan:|missing trailer 'Task:" \
    "malformed|feat: bad values|trailer 'Assisted-by: Claude' must be|trailer 'Plan: 26' must be|trailer 'Task: first' must be" \
    "forbidden|feat: attributed|agents never add 'Co-authored-by'|agents never add 'Signed-off-by'"; do
    IFS='|' read -r problem subject problems <<<"$case"
    (
      rm -rf "$WORK" && init_git_repo && git switch -q -c "work/$problem-trailers" || exit 1
      case "$problem" in
        missing) git commit -q --allow-empty -m "$subject" || exit 1 ;;
        malformed)
          git commit -q --allow-empty -m "$subject" \
            --trailer "Assisted-by: Claude" --trailer "Plan: 26" --trailer "Task: first" || exit 1
          ;;
        forbidden)
          agent_commit claude-code "$subject" --trailer "Co-authored-by: Bot <bot@example.com>" --signoff || exit 1
          ;;
      esac
      run "$CHECK"
      assert_failure || exit 1
      while IFS= read -r line; do
        assert_output --partial "\"$subject\": $line" || exit 1
      done <<<"$(tr '|' '\n' <<<"$problems")"
    ) || fail "check-git did not list the $problem trailers"
  done
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

@test "fails instead of passing when the base or the explicit branch does not exist" {
  local case missing message
  cd "$BATS_TEST_TMPDIR" || return
  # Each case: the ref that does not exist | the problem check-git.sh reports.
  for case in "base|base branch 'nope' not found" "explicit branch|branch 'plan/n3q8d5vb-nope' not found"; do
    IFS='|' read -r missing message <<<"$case"
    (
      rm -rf "$WORK" && init_git_repo || exit 1
      if [[ "$missing" == base ]]; then
        git switch -q -c work/x || exit 1
        run "$CHECK" nope
      else
        run "$CHECK" main plan/n3q8d5vb-nope
      fi
      assert_failure && assert_output --partial "$message"
    ) || fail "check-git did not fail on a missing $missing"
  done
}
