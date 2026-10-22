#!/usr/bin/env bats
load helpers

setup() {
  # {{setup_stubs COMMAND... for every external command the script runs, use_vm_env when it reaches the VM; or delete this line}}
  SCRIPT="$REPO_DIR/scripts/{{name}}.sh"
}

@test "{{what the script does on its success path}}" {
  run "$SCRIPT"
  assert_success
  # {{assert what shows it worked: assert_output, assert_stub_called}}
}

@test "{{which input or state it refuses, and that it changes nothing}}" {
  run "$SCRIPT" "{{bad input}}"
  assert_failure
  # {{refute_stub_called for every command that must not run}}
}
