#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
}

@test "logs prints the last 200 lines from the VM" {
  run "$REPO_DIR/scripts/show-logs.sh"
  assert_success
  run grep -F 'docker compose logs --tail=200' "$STUB_LOG"
  assert_success
}

@test "a VM target that never reads the mode still stops on a BM_ACCESS it does not know before it runs ssh" {
  export BM_ACCESS=Ssh
  run "$REPO_DIR/scripts/show-logs.sh"
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'Ssh')"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
}
