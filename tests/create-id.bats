#!/usr/bin/env bats
load helpers

setup() {
  init_git_repo
  SCRIPT="$REPO_DIR/scripts/create-id.sh"
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
}

@test "prints one id and nothing else" {
  run "$SCRIPT"
  assert_success
  assert_equal "${#lines[@]}" 1
  [[ "$output" =~ ^${DOC_ID_PATTERN}$ ]] || fail "'$output' is not an id"
}

@test "fails outside a git checkout and prints no id" {
  cd "$BATS_TEST_TMPDIR" || return
  run "$SCRIPT"
  assert_failure
  assert_output --partial "inside a checkout"
}
