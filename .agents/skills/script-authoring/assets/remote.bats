#!/usr/bin/env bats
load helpers

setup() {
  # {{setup_stubs COMMAND... for every command the script runs on the VM, and the paths it writes under $BATS_TEST_TMPDIR}}
  SCRIPT="$REPO_DIR/scripts/remote/{{name}}.sh"
}

@test "{{what the script does on the VM on its success path}}" {
  run "$SCRIPT"
  assert_success
  # {{assert what shows it worked: assert_stub_called, assert_log_order, the files it wrote}}
}

@test "{{which input or VM state it refuses, and that it changes nothing}}" {
  run "$SCRIPT" "{{bad input}}"
  assert_failure
  # {{refute_stub_called for every command that must not run}}
}
