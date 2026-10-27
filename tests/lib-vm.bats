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

@test "web_mode prints off for an empty BM_WEB and on or off as given, and stops on any other value, another case included" {
  local case value expected
  # Each case: BM_WEB | what web_mode prints.
  for case in "|off" "on|on" "off|off"; do
    IFS='|' read -r value expected <<<"$case"
    (
      BM_WEB="$value" run web_mode
      assert_success && assert_output "$expected"
    ) || fail "web_mode did not accept BM_WEB='$value'"
  done
  for value in On yes; do
    (
      BM_WEB="$value" run web_mode
      assert_failure && assert_output --partial "BM_WEB must be on or off (got '$value')"
    ) || fail "web_mode accepted BM_WEB='$value'"
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

@test "require_vm stops on an unknown BM_WEB before it runs ssh" {
  BM_WEB=yes run require_vm
  assert_failure
  assert_output --partial "BM_WEB must be on or off (got 'yes')"
  refute_stub_called -F 'ssh '
}

# shellcheck disable=SC2030,SC2031 # the subshells keep their BM_WEB to themselves
@test "require_web_settings does nothing while BM_WEB is off or empty, even with broken web settings" {
  local value
  for value in "" off; do
    (
      export BM_WEB="$value" BM_WEB_HOST=https://bad BM_WEB_JWT_KEY='a b'
      run require_web_settings
      assert_success && assert_output ""
    ) || fail "require_web_settings stopped with BM_WEB='$value'"
  done
}

@test "require_web_settings accepts complete settings" {
  use_web_env
  run require_web_settings
  assert_success
  assert_output ""
}

@test "require_web_settings names only the variable for a bad host, user id, client id or secret, and prints no value" {
  local case name value
  use_web_env
  # Each case: the variable | its bad value (the secrets: empty, then #, $ and a space; the JWT key also one character
  # shorter than the gateway accepts).
  for case in "BM_WEB_HOST|https://mcp.example.com" "BM_WEB_HOST|mcp.example.com/path" "BM_WEB_HOST|mcp.example.com:443" "BM_WEB_HOST|nodots" "BM_WEB_HOST|" \
    "BM_WEB_GITHUB_USER_ID|octocat" "BM_WEB_GITHUB_USER_ID|42x" "BM_WEB_GITHUB_USER_ID|" \
    "BM_WEB_GITHUB_CLIENT_ID|" "BM_WEB_GITHUB_CLIENT_ID|id with space" \
    "BM_WEB_GITHUB_CLIENT_SECRET|" "BM_WEB_GITHUB_CLIENT_SECRET|sec#ret" "BM_WEB_GITHUB_CLIENT_SECRET|sec\$ret" "BM_WEB_GITHUB_CLIENT_SECRET|sec ret" \
    "BM_WEB_JWT_KEY|" "BM_WEB_JWT_KEY|key#0123" "BM_WEB_JWT_KEY|key\$0123" "BM_WEB_JWT_KEY|key 0123" "BM_WEB_JWT_KEY|fake-jwt-key-fake-jwt-key-fake-" \
    "BM_WEB_TUNNEL_TOKEN|" "BM_WEB_TUNNEL_TOKEN|tok#en" "BM_WEB_TUNNEL_TOKEN|tok\$en" "BM_WEB_TUNNEL_TOKEN|tok en"; do
    IFS='|' read -r name value <<<"$case"
    (
      export "$name=$value"
      run require_web_settings
      assert_failure && assert_output --partial "$name" || exit 1
      if [[ -n "$value" ]]; then
        refute_output --partial "$value"
      fi
    ) || fail "require_web_settings did not stop on $name='$value'"
  done
}

# shellcheck disable=SC2030,SC2031 # the subshells keep their BM_WEB to themselves
@test "vm_env with BM_WEB off or empty prints exactly the five lines of a VM without the web connector" {
  local web
  for web in "" off; do
    (
      export BM_WEB="$web"
      run vm_env
      assert_success
      assert_output "$(printf '%s\n' BM_PORT=8737 "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge" "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config" SB_PORT=3000 SB_USER=admin:test-password)"
    ) || fail "vm_env changed with BM_WEB='$web'"
  done
}

@test "vm_env with BM_WEB on adds the profiles, the gateway data dir and the web settings after the five lines" {
  use_web_env
  run vm_env
  assert_success
  assert_line --index 0 "BM_PORT=8737"
  assert_line --index 4 "SB_USER=admin:test-password"
  assert_line --index 5 "COMPOSE_PROFILES=web,tunnel"
  assert_line "BM_WEB_PORT=8738"
  assert_line "BM_WEB_DATA_DIR=$BM_REMOTE_DATA_ROOT/gateway"
  assert_line "BM_WEB_BASE_URL=https://mcp.example.com"
  assert_line "BM_WEB_GITHUB_USER_ID=4242"
  assert_line "BM_WEB_GITHUB_CLIENT_ID=test-client-id"
  assert_line "BM_WEB_GITHUB_CLIENT_SECRET=test-client-secret"
  assert_line "BM_WEB_JWT_KEY=fake-jwt-key-fake-jwt-key-fake-jwt-key"
  assert_line "BM_WEB_TUNNEL_TOKEN=test-tunnel-token"
}

@test "vm_env with BM_WEB on uses the default gateway port when BM_WEB_PORT is unset" {
  use_web_env
  unset BM_WEB_PORT
  run vm_env
  assert_line "BM_WEB_PORT=8738"
}

@test "vm_env with BM_WEB on writes the sha256 of the gateway runtime files, which changes when any one of them changes" {
  local hash file
  use_web_env
  run vm_env
  assert_success
  hash="$(sed -n 's/^BM_WEB_CODE_SHA256=//p' <<<"$output")"
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || fail "vm_env printed no BM_WEB_CODE_SHA256 line"
  run gateway_code_sha256 "$REPO_DIR/gateway"
  assert_output "$hash"
  for file in $GATEWAY_RUNTIME_FILES; do
    (
      rm -rf "$BATS_TEST_TMPDIR/gateway" && cp -R "$REPO_DIR/gateway" "$BATS_TEST_TMPDIR/gateway" || exit 1
      printf '\n' >>"$BATS_TEST_TMPDIR/gateway/$file" || exit 1
      run gateway_code_sha256 "$BATS_TEST_TMPDIR/gateway"
      assert_success && assert_output --regexp '^[0-9a-f]{64}$' && refute_output "$hash"
    ) || fail "the gateway code hash did not change with gateway/$file"
  done
}

@test "upload_gateway_files uploads boot.py, gateway.py and requirements.txt when BM_WEB is on and nothing when it is off" {
  local file
  run upload_gateway_files
  assert_success
  [[ ! -e "$BM_REMOTE_APP_DIR/gateway" ]] || fail "upload_gateway_files wrote files with BM_WEB unset"
  use_web_env
  run upload_gateway_files
  assert_success
  for file in boot.py gateway.py requirements.txt; do
    assert_same_file "$REPO_DIR/gateway/$file" "$BM_REMOTE_APP_DIR/gateway/$file"
    assert_stub_called -F "cat > $BM_REMOTE_APP_DIR/gateway/$file"
  done
}

@test "upload_gateway_files fails with an actionable message when an upload fails" {
  use_web_env
  SSH_STUB_FAIL_MATCH="gateway/gateway.py" run upload_gateway_files
  assert_failure
  assert_output --partial "gateway/gateway.py"
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
