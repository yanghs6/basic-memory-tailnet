#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker
  use_vm_env
}

@test "logs prints the last 200 lines from the VM" {
  run "$REPO_DIR/scripts/show-logs.sh"
  assert_success
  assert_stub_called -F 'docker compose logs --tail=200'
}
