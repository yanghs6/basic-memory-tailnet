#!/usr/bin/env bats
load helpers

setup() {
  # The consumer loop below runs scripts, so every command they could reach is a stub.
  setup_stubs ssh sudo curl docker
  use_vm_env
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/notes"
  # shellcheck source=../scripts/lib/sb.sh
  . "$REPO_DIR/scripts/lib/sb.sh"
}

@test "the libraries load in any order and more than once, and common.sh alone holds no VM or SilverBullet settings" {
  # A script file, not bash -c: under make coverage, kcov's exported PS4 reads BASH_SOURCE, which bash -c leaves
  # unset at its top level, so set -u would stop it there.
  cat >"$BATS_TEST_TMPDIR/load.sh" <<'EOF'
set -euo pipefail
. "$1/scripts/lib/common.sh"
[[ -z "${BM_CONTAINER_UID+x}${SB_GITIGNORE_PENDING+x}" ]] || { echo "common.sh loaded VM settings"; exit 1; }
. "$1/scripts/lib/sb.sh"; . "$1/scripts/lib/vm.sh"; . "$1/scripts/lib/common.sh"; . "$1/scripts/lib/sb.sh"
printf '%s|%s\n' "$REPO_DIR" "$SB_REMOTE_NOTES_DIR"
EOF
  run env REPO_DIR=/nowhere bash "$BATS_TEST_TMPDIR/load.sh" "$REPO_DIR"
  assert_success
  assert_output "$REPO_DIR|$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
}

@test "require_sb_user rejects an SB_USER that make or docker compose would change or that differs from its raw line in SB_ENV_FILE, without printing it, and accepts the last line without its CR" {
  local env_file="$BATS_TEST_TMPDIR/main.env" value pair raw passed
  # shellcheck disable=SC2016 # 'admin:pa$ss' is a literal password with a dollar sign
  for value in "" "admin" "admin:pa ss" 'admin:pa$ss' "admin:pa#ss" "admin:pa'ss" 'admin:pa"ss' "ad min:secret123"; do
    (
      SB_USER="$value" run require_sb_user
      assert_failure && assert_output --partial "SB_USER" || exit 1
      if [[ "$value" == *:* ]]; then
        refute_output --partial "${value#*:}"
      fi
    ) || fail "require_sb_user accepted or printed SB_USER '$value'"
  done

  # Each pair: the raw .env value | what GNU make passes on (# starts a comment, $o expands to nothing).
  # shellcheck disable=SC2016 # 'admin:Tr4mp$oline' is a literal .env value with a dollar sign
  for pair in 'admin:Tr4mp#oline|admin:Tr4mp' 'admin:Tr4mp$oline|admin:Tr4mpline'; do
    IFS='|' read -r raw passed <<<"$pair"
    (
      printf 'BM_PORT=8737\nSB_USER=%s\n' "$raw" >"$env_file" || exit 1
      SB_ENV_FILE="$env_file" SB_USER="$passed" run require_sb_user
      assert_failure && assert_output --partial "SB_USER in $env_file" && refute_output --partial "Tr4mp"
    ) || fail "require_sb_user accepted or printed SB_USER '$passed' from the .env line SB_USER=$raw"
  done

  # The last SB_USER line wins, and a CRLF line ending is not part of the value.
  printf 'SB_USER=admin:old-password\nSB_USER=admin:test-password\r\n' >"$env_file"
  SB_ENV_FILE="$env_file" SB_USER=admin:test-password run require_sb_user
  assert_success
}

@test "deploy and verify-sb stop before they contact the VM or SilverBullet on an SB_USER that require_sb_user rejects" {
  local case script url setting words
  for case in "deploy-stack.sh||-u SB_USER" "verify-sb.sh|http://127.0.0.1:3000|SB_USER=admin"; do
    IFS='|' read -r script url setting <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      read -r -a words <<<"$setting"
      run env "${words[@]}" "$REPO_DIR/scripts/$script" ${url:+"$url"}
      assert_failure && assert_output --partial "SB_USER" && refute_stub_called -E '^(ssh|curl) '
    ) || fail "$script went on with env $setting"
  done
}

@test "sb_space_apply recreates Basic Memory between the .gitignore and the pages, and asks again after a failed recreate" {
  local page="$SB_LOCAL_NOTES_DIR/Library/agent-hub/agent-hub.md"
  run sb_space_apply local "rerun 'make local-up'" false
  assert_failure
  assert_output --partial "rerun 'make local-up'"
  [[ -e "$SB_LOCAL_NOTES_DIR/.gitignore.pending" && ! -e "$page" ]] \
    || fail "a failed recreate must keep the marker and write no pages"
  run sb_space_apply local "rerun 'make local-up'" docker compose up -d --force-recreate basic-memory
  assert_success
  [[ ! -e "$SB_LOCAL_NOTES_DIR/.gitignore.pending" && -e "$page" ]] \
    || fail "the retry must recreate, remove the marker and write the pages"
  run sb_space_apply local "rerun 'make local-up'" false
  assert_success
  run grep -c '^docker compose up -d --force-recreate basic-memory$' "$STUB_LOG"
  assert_output 1
}
