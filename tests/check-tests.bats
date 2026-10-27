#!/usr/bin/env bats
load helpers

readonly TRAILERS="Assisted-by: claude-code claude-opus-5-5
Plan: m97w7hqe"

setup() {
  CHECK="$REPO_DIR/scripts/check-tests.sh"
  # Every case builds its repo (new_repo) in its own subshell, so the tests start outside it.
  WORK="$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR" || return
}

# new_repo: a repo whose main holds tests/a.bats with two tests (lines 2-4 and 5-7), on a new branch work/x.
new_repo() {
  rm -rf "$WORK" && init_git_repo && mkdir tests \
    && printf '#!/usr/bin/env bats\n@test "one" {\n  true\n}\n@test "two" {\n  true\n}\n' >tests/a.bats \
    && git add tests && git commit -q -m "test: two tests" && git switch -q -c work/x
}

# commit_all SUBJECT: commit every change in the work tree.
commit_all() {
  git add -A && git commit -q -m "$1"
}

# drop_second_test: tests/a.bats keeps only its first test.
drop_second_test() {
  sed -i.bak '5,7d' tests/a.bats && rm tests/a.bats.bak
}

@test "passes when the branch keeps or adds tests, also when main moved on or the branch merged a main that removed one" {
  local case
  for case in "keeps them|2 -> 2" "adds one|2 -> 3" "main added one the branch has not merged|2 -> 2" \
    "merges a main that removed one|1 -> 1"; do
    (
      new_repo || exit 1
      case "${case%%|*}" in
        "keeps them") git commit -q --allow-empty -m "docs: x" || exit 1 ;;
        "adds one")
          printf '@test "three" {\n  true\n}\n' >>tests/a.bats && commit_all "test: add one" || exit 1
          ;;
        "main added one"*)
          git commit -q --allow-empty -m "docs: x" && git switch -q main \
            && printf '@test "three" {\n  true\n}\n' >>tests/a.bats && commit_all "test: add one" \
            && git switch -q work/x || exit 1
          ;;
        "merges a main"*)
          git commit -q --allow-empty -m "docs: x" && git switch -q main && drop_second_test \
            && commit_all "test: drop one" && git switch -q work/x && git merge -q --no-ff main -m "Merge main" || exit 1
          ;;
      esac
      PR_TITLE="test: x" PR_BODY="$TRAILERS" run "$CHECK" main
      assert_success && assert_output --partial "OK:" && assert_output --partial "${case#*|}" || exit 1
    ) || fail "check-tests did not pass a branch that ${case%%|*}"
  done
}

@test "fails when the branch removes a @test or adds a skip unless the PR body's trailer paragraph carries Tests-Removed with a reason" {
  local case word input expected shown body
  # The skip lines are built from a variable so this file adds no skip line itself.
  word=skip
  # Each case: the change and the PR body | pass or fail | what the output must show.
  for case in "removes one|fail|2 -> 1" "adds a skip|fail|tests/a.bats:9" "adds a skip after &&|fail|tests/helpers.bash:3" \
    "removes one with a reason|pass|2 -> 1" "removes one with an empty reason|fail|2 -> 1" \
    "removes one with the marker in a middle paragraph|fail|2 -> 1"; do
    IFS='|' read -r input expected shown <<<"$case"
    (
      new_repo || exit 1
      body="$TRAILERS"
      case "$input" in
        "adds a skip")
          printf '@test "three %ss" {\n  %s "x"\n}\n' "$word" "$word" >>tests/a.bats || exit 1
          ;;
        "adds a skip after &&")
          # shellcheck disable=SC2016 # the $(id -u) is literal text of the helper file, not run here
          printf 'note() {\n  echo "%sping"\n  [ "$(id -u)" -eq 0 ] && %s "root"\n}\n' "$word" "$word" >tests/helpers.bash || exit 1
          ;;
        *) drop_second_test || exit 1 ;;
      esac
      case "$input" in
        *"with a reason") body="Summary.

$TRAILERS
Tests-Removed: merged into a loop" ;;
        *"empty reason") body="$TRAILERS
Tests-Removed:" ;;
        *"middle paragraph") body="Summary.

Tests-Removed: merged into a loop

$TRAILERS" ;;
      esac
      commit_all "test: change" && PR_TITLE="test: x" PR_BODY="$body" run "$CHECK" main || exit 1
      if [[ "$expected" == pass ]]; then
        assert_success && assert_output --partial "OK:" || exit 1
      else
        assert_failure 1 && refute_output --partial "OK:" || exit 1
      fi
      assert_output --partial "$shown" || exit 1
      # Only the skip line counts, not a test name or a string that contains the word.
      refute_output --partial "tests/a.bats:8" && refute_output --partial "tests/helpers.bash:2" || exit 1
    ) || fail "check-tests misjudged a branch that $input"
  done
}
