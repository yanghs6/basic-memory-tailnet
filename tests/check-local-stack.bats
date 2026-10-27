#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs docker
  SCRIPT="$REPO_DIR/scripts/check-local-stack.sh"
}

@test "check-local-stack passes with no stack, this repo through a symlink or a deleted directory, refuses another existing directory, and only lists containers" {
  local link="$BATS_TEST_TMPDIR/repo-link" other="$BATS_TEST_TMPDIR/other-worktree" gone="$BATS_TEST_TMPDIR/gone-worktree"
  local case dirs expect message
  ln -s "$REPO_DIR" "$link"
  mkdir -p "$other"
  # Each case: the working_dir labels of the project's containers | success or failure | a message that tells which
  # check decided, or empty.
  for case in \
    "|success|" \
    "$link|success|" \
    "$other|failure|$other" \
    "$gone|success|WARNING"; do
    IFS='|' read -r dirs expect message <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      export DOCKER_STUB_STACK_DIRS="$dirs"
      run "$SCRIPT"
      "assert_$expect" \
        && { [[ -z "$message" ]] || assert_output --partial "$message"; } \
        && { [[ "$expect" == success ]] || assert_output --partial "make local-down"; } \
        && assert_stub_called -F 'docker ps -a --filter label=com.docker.compose.project=basic-memory ' \
        && refute_stub_called -v '^docker ps '
    ) || fail "check-local-stack with the stack started in '$dirs'"
  done
}
