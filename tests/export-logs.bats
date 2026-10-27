#!/usr/bin/env bats
load helpers

FIXTURES="$REPO_DIR/tests/fixtures/export-logs"

setup() {
  setup_stubs ssh
  use_vm_env
  SCRIPT="$REPO_DIR/scripts/export-logs.sh"
  export LOG_EXPORT_DIR="$BATS_TEST_TMPDIR/log-exports" DOCKER_FIXTURES="$FIXTURES"
  # The VM's docker: compose lists the running services and their container ids, docker logs prints the recorded
  # stdout and stderr of that container.
  # shellcheck disable=SC2016  # the fake expands its own arguments
  fake_cmd docker '
args="$*"
printf "docker %s\n" "$args" >>"$STUB_LOG"
case "$args" in
  "compose ps --services --status running") printf "%s\n" basic-memory silverbullet ;;
  "compose ps -q "*) printf "id-%s\n" "${args##* }" ;;
  "logs "*)
    service="${args##* id-}"
    cat "$DOCKER_FIXTURES/$service.out"
    cat "$DOCKER_FIXTURES/$service.err" >&2
    ;;
  *) exit 1 ;;
esac'
}

@test "export-logs writes every running service's lines since 24h as one JSON Lines file in time order, without the lines ssh printed itself" {
  run "$SCRIPT"
  assert_success
  assert_stub_called -F 'docker logs --timestamps --since 24h id-basic-memory'
  assert_stub_called -F 'docker logs --timestamps --since 24h id-silverbullet'
  local file
  file="$(ls "$LOG_EXPORT_DIR"/logs-*.jsonl)"
  # Only this user may read it: the lines can hold note titles.
  [[ "$(stat -c %a "$file")" == 600 ]] || fail "mode $(stat -c %a "$file")"
  run jq -c '[.service, .stream, .msg]' "$file"
  assert_output - <<'EOF'
["basic-memory","stderr","INFO: Started server process"]
["basic-memory","stdout","INFO:     172.18.0.1:40000 - \"POST /mcp HTTP/1.1\" 200 OK"]
["basic-memory","stderr","ERROR: Exception in ASGI application"]
["basic-memory","stdout","{\"time\": \"2026-10-27T01:00:00+00:00\", \"user\": \"4242\", \"tool\": \"read_note\", \"ms\": 12}"]
["silverbullet","stdout","2026-10-27T01:00:00Z INFO silverbullet: listening"]
EOF
  run jq -c 'select(.data) | [.time, .data.tool]' "$file"
  assert_output '["2026-10-27T01:00:00.000000004Z","read_note"]'
}

@test "export-logs never prints a log line to the terminal" {
  run "$SCRIPT"
  assert_success
  refute_output --partial 'read_note'
  refute_output --partial 'Started server process'
  # The count of dropped ssh lines shows that the ssh notice was not taken for a log line.
  assert_output --partial "skipped 1 line"
}

@test "export-logs refuses a SINCE that is not a number of seconds, minutes or hours, and reaches no VM" {
  local since
  for since in 1d '24h;rm' h; do
    (
      run "$SCRIPT" "$since"
      assert_failure && refute_stub_called -F 'ssh' && [[ ! -e "$LOG_EXPORT_DIR" ]] || exit 1
    ) || fail "SINCE=$since"
  done
}

@test "export-logs leaves no file when the VM stops answering" {
  export SSH_STUB_FAIL_MATCH="docker logs"
  run "$SCRIPT"
  assert_failure
  run ls -A "$LOG_EXPORT_DIR"
  assert_output ''
}
