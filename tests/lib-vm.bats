#!/usr/bin/env bats
load helpers

setup() {
  # The consumer loops below run scripts, so every command they could reach is a stub.
  setup_stubs ssh docker sudo curl nc tailscale
  use_vm_env
  # shellcheck source=../scripts/lib/vm.sh
  . "$REPO_DIR/scripts/lib/vm.sh"
}

@test "remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST" {
  run remote "echo hi"
  assert_success
  assert_output "hi"
  run cat "$STUB_LOG"
  assert_output "ssh -o BatchMode=yes -o ConnectTimeout=10 ubuntu@agent-hub echo hi"
}

@test "require_vm stops on an unknown BM_ACCESS in any case, a missing command or a missing VM setting, before any ssh" {
  local case setting arg expected
  for case in "BM_ACCESS=SSH||BM_ACCESS must be tailscale or ssh (got 'SSH')" \
    "BM_ACCESS=Ssh||BM_ACCESS must be tailscale or ssh (got 'Ssh')" \
    "BM_ACCESS=tailscale|no-such-command|missing command 'no-such-command'" \
    "BM_VM_HOST=||missing env BM_VM_HOST" \
    "BM_VM_USER=||missing env BM_VM_USER"; do
    IFS='|' read -r setting arg expected <<<"$case"
    (
      export "${setting?}"
      run require_vm ${arg:+"$arg"}
      assert_failure && assert_output --partial "$expected"
    ) || fail "require_vm did not stop as expected for: $case"
  done
  refute_stub_called -F 'ssh '
  BM_ACCESS=ssh run require_vm
  assert_success
}

@test "deploy, verify and logs stop on an unknown BM_ACCESS before they run ssh, curl or nc" {
  local case script value
  for case in "deploy-stack.sh SSH" "verify-vm.sh SSH" "verify-vm.sh Ssh" "show-logs.sh Ssh"; do
    read -r script value <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      BM_ACCESS="$value" run "$REPO_DIR/scripts/$script"
      assert_failure \
        && assert_output --partial "BM_ACCESS must be tailscale or ssh (got '$value')" \
        && refute_stub_called -E '^(ssh|curl|nc) '
    ) || fail "$script went on with BM_ACCESS=$value"
  done
}

@test "require_free_port refuses a privileged port and a port in use, so both tunnels stop before ssh" {
  local case script arg setting expected
  use_ssh_mode
  # A tunnel started by mistake ends at once instead of holding the test.
  export BM_VM_PUBLIC_IP=203.0.113.10 SSH_STUB_TUNNEL_EXIT=255
  for case in "open-tunnel.sh||BM_TUNNEL_MCP_PORT=80|BM_TUNNEL_MCP_PORT must be a port number from 1024 to 65535 (got '80')" \
    "open-tunnel.sh||NC_STUB_OPEN_MATCH=13000|port 13000 is in use on 127.0.0.1" \
    "verify-vm.sh|--read-only|NC_STUB_OPEN_MATCH=28737|port 28737 is in use on 127.0.0.1"; do
    IFS='|' read -r script arg setting expected <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      run env "$setting" "$REPO_DIR/scripts/$script" ${arg:+"$arg"}
      assert_failure && assert_output --partial "$expected" && refute_stub_called -F 'ssh -N'
    ) || fail "$script${arg:+ $arg} with $setting did not stop before its tunnel"
  done
}

@test "remote_exists and remote_compose --if-deployed follow what is on the VM, and remote_exists fails when the VM does not answer" {
  local file="$BM_REMOTE_APP_DIR/compose.yaml"
  run remote_exists "$file"
  assert_success
  assert_output absent
  run remote_compose --if-deployed stop
  assert_success
  refute_stub_called '^docker '
  touch "$file"
  run remote_exists "$file"
  assert_output present
  run remote_compose --if-deployed stop
  assert_success
  assert_stub_called -Fx 'docker compose stop'
  SSH_STUB_FAIL_MATCH="-e $file" run remote_exists "$file"
  assert_failure
  refute_line absent
}

@test "vm_env prints the loopback ports, the absolute data paths and SB_USER" {
  run vm_env
  assert_success
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  assert_line "SB_PORT=3000"
  assert_line "SB_USER=admin:test-password"
}

@test "manifest_cmd lists every file's sha256 sorted by path" {
  setup_stubs sudo
  mkdir -p "$BATS_TEST_TMPDIR/d/b"
  printf 'abc' >"$BATS_TEST_TMPDIR/d/b/z.md"
  printf 'abc' >"$BATS_TEST_TMPDIR/d/a.md"
  run bash -c "$(manifest_cmd "$BATS_TEST_TMPDIR/d")"
  assert_success
  assert_line --index 0 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  ./a.md"
  assert_line --index 1 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  ./b/z.md"
}
