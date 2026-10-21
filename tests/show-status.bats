#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc uname sshd
  use_vm_env
}

@test "status shows containers, memory use and tailscale serve" {
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "basic-memory-server"
  assert_output --partial "memory used: 23%"
  assert_output --partial "swap used: 0/1023 MB"
  assert_output --partial "proxy http://127.0.0.1:8737"
  refute_output --partial "WARNING"
  export FREE_STUB_SWAP_USED_MB=200
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "swap used: 200/1023 MB"
  refute_output --partial "WARNING"
}

@test "status warns to rerun vm-bootstrap when no swap is active" {
  export FREE_STUB_SWAP_TOTAL_MB=0
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "swap used: 0/0 MB"
  assert_output --partial "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/rbk-2026-10-12-bootstrap.md)"
  assert_output --partial "proxy http://127.0.0.1:8737"
}

@test "status points to free -m on the VM when it cannot read the memory use" {
  SSH_STUB_FAIL_MATCH="free -m" run "$REPO_DIR/scripts/show-status.sh"
  assert_failure
  assert_output --partial "could not read memory usage on $BM_VM_HOST: run 'ssh $BM_VM_USER@$BM_VM_HOST free -m' and check its Mem: and Swap: lines"
}

@test "ssh mode: status shows the access mode instead of Serve and warns while Tailscale is logged in on the VM" {
  use_ssh_mode
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "access: ssh"
  assert_output --partial "tailscale: not installed or logged out"
  refute_output --partial "proxy http://127.0.0.1:8737"
  export TS_STUB_BACKEND_STATE=Running
  run "$REPO_DIR/scripts/show-status.sh"
  assert_success
  assert_output --partial "WARNING: Tailscale is still logged in on the VM; BM_ACCESS=ssh expects it off"
}
