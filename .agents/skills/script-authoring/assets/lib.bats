#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/{{name}}.sh
  . "$REPO_DIR/scripts/lib/{{name}}.sh"
}

@test "{{function}} {{what it prints or does for valid input}}" {
  run "{{function}}" "{{valid input}}"
  assert_success
  # {{assert_output with the exact result}}
}

@test "{{function}} {{which input it refuses}}" {
  run "{{function}}" "{{bad input}}"
  assert_failure
}
