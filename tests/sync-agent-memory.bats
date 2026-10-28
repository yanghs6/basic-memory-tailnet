#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs curl sleep
  use_mcp_fixtures sse
  export HOME="$BATS_TEST_TMPDIR/home" BM_MEMORY_DEVICE=mac-test BM_MEMORY_MCP_URL=http://127.0.0.1:18737/mcp
  unset XDG_STATE_HOME BM_MEMORY_EXCLUDE CODEX_HOME CLAUDE_CONFIG_DIR
  # shellcheck source=../scripts/lib/agent-memory.sh
  . "$REPO_DIR/scripts/lib/agent-memory.sh"
  WIDGET="$BATS_TEST_TMPDIR/work/widget"
  git init -q "$WIDGET" && git -C "$WIDGET" remote add origin git@github.com:acme/widget.git
  CLAUDE_MEM="$HOME/.claude/projects/$(claude_folder_name "$WIDGET")"
  CODEX_MEM="$HOME/.codex/memories"
  mkdir -p "$CLAUDE_MEM/memory" "$HOME/.claude/projects/-private-tmp-x/memory" "$CODEX_MEM/rollout_summaries" "$CODEX_MEM/.git" \
    "$HOME/.codex/memories_v2"
  echo v2 >"$HOME/.codex/memories_v2/MEMORY.md"
  printf '{"cwd":"%s"}\n' "$WIDGET" >"$CLAUDE_MEM/s1.jsonl"
  printf -- '---\nname: m\n---\nindex\n' >"$CLAUDE_MEM/memory/MEMORY.md"
  echo note >"$CLAUDE_MEM/memory/회의 메모.md"
  echo tmp >"$HOME/.claude/projects/-private-tmp-x/memory/t.md"
  echo summary >"$CODEX_MEM/memory_summary.md"
  echo rollout >"$CODEX_MEM/rollout_summaries/r1.md"
  echo ref >"$CODEX_MEM/.git/HEAD.md"
  echo diff >"$CODEX_MEM/phase2_workspace_diff.md"
  echo hidden >"$CODEX_MEM/.hidden.md"
  SYNC="$REPO_DIR/scripts/sync-agent-memory.sh"
  STATE_DIR="$HOME/.local/state/bm-agent-memory"
}

# written_notes -> "directory/title" of every write_note request, sorted.
written_notes() {
  jq -r 'select(.params.name == "write_note") | .params.arguments | "\(.directory)/\(.title)"' "$STUB_LOG.requests" | LC_ALL=C sort
}

# tool_calls NAME -> how many requests called the tool NAME.
tool_calls() { jq -r --arg name "$1" 'select(.params.name == $name) | .id' "$STUB_LOG.requests" | wc -l | tr -d ' '; }

@test "mirrors Claude and Codex (v1 and v2) memory under agent-memory/<key>/<agent>/<device>/ with the mirror metadata, skips temp folders, Codex .git, phase2_workspace_diff.md and hidden files, and a rerun sends nothing" {
  run "$SYNC"
  assert_success
  assert_equal "$(written_notes)" "$(printf '%s\n' agent-memory/_global/codex/mac-test/memory_summary \
    agent-memory/_global/codex/mac-test/rollout_summaries/r1 agent-memory/_global/codex/mac-test/v2/MEMORY \
    agent-memory/acme-widget/claude-code/mac-test/MEMORY "agent-memory/acme-widget/claude-code/mac-test/회의 메모" | LC_ALL=C sort)"
  # shellcheck disable=SC2088 # source_path holds a literal ~ for the home folder
  assert_equal "$(jq -cS 'select(.params.arguments.directory == "agent-memory/acme-widget/claude-code/mac-test" and .params.arguments.title == "MEMORY")
    | .params.arguments | {project, note_type, overwrite, metadata}' "$STUB_LOG.requests")" \
    "$(jq -cnS --arg src "~/.claude/projects/${CLAUDE_MEM##*/}/memory/MEMORY.md" '{project: "main", note_type: "agent_memory", overwrite: true,
      metadata: {project: "acme-widget", repo: "github.com/acme/widget", agent: "claude-code", device: "mac-test", source_path: $src, mirror: true}}')"
  : >"$STUB_LOG"
  run "$SYNC"
  assert_success
  refute_stub_called '^curl '
}

@test "sends only a changed file again, and deletes the note of a removed file and every note of a newly excluded project" {
  "$SYNC" 2>/dev/null
  rm -f "$STUB_LOG.requests"
  echo changed >>"$CLAUDE_MEM/memory/MEMORY.md"
  rm "$CLAUDE_MEM/memory/회의 메모.md"
  run "$SYNC"
  assert_success
  assert_equal "$(written_notes)" agent-memory/acme-widget/claude-code/mac-test/MEMORY
  assert_equal "$(jq -r 'select(.params.name == "delete_note") | .params.arguments.identifier' "$STUB_LOG.requests")" main/verify/bm-verify-test1
  rm -f "$STUB_LOG.requests"
  export BM_MEMORY_EXCLUDE=_global
  run "$SYNC"
  assert_success
  assert_equal "$(tool_calls write_note)" 0
  assert_equal "$(tool_calls delete_note)" 3
  ! grep -q /codex/ "$STATE_DIR/state.tsv" || fail "the state still lists Codex notes"
}

@test "keeps the state when the endpoint is down or one write fails, and the next run sends only what was missed" {
  export CURL_STUB_EXIT=7
  run "$SYNC"
  assert_failure
  assert_output --partial "basic-memory unreachable (run make tunnel); sync skipped"
  [[ ! -e "$STATE_DIR/state.tsv" ]] || fail "state written while the endpoint was down"
  unset CURL_STUB_EXIT
  export CURL_STUB_FAIL_MATCH='"title":"MEMORY"'
  run "$SYNC"
  assert_failure
  assert_equal "$(cut -f2 "$STATE_DIR/state.tsv" | LC_ALL=C sort | tr '\n' ' ')" \
    "agent-memory/_global/codex/mac-test/memory_summary agent-memory/_global/codex/mac-test/rollout_summaries/r1 agent-memory/acme-widget/claude-code/mac-test/회의 메모 "
  unset CURL_STUB_FAIL_MATCH
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(written_notes)" \
    "$(printf '%s\n' agent-memory/_global/codex/mac-test/v2/MEMORY agent-memory/acme-widget/claude-code/mac-test/MEMORY)"
}

@test "keeps the old state line when an update fails, so removing the file afterwards still deletes its note" {
  "$SYNC" 2>/dev/null
  echo changed >>"$CLAUDE_MEM/memory/MEMORY.md"
  export CURL_STUB_FAIL_MATCH='"title":"MEMORY"'
  run "$SYNC"
  assert_failure
  assert_equal "$(grep -c 'claude-code/mac-test/MEMORY' "$STATE_DIR/state.tsv")" 1
  unset CURL_STUB_FAIL_MATCH
  rm "$CLAUDE_MEM/memory/MEMORY.md"
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(tool_calls delete_note)" 1
}

@test "counts a write_note result with action conflict as a failure and keeps that file out of the state" {
  sed 's/\\"action\\":\\"created\\"/\\"action\\":\\"conflict\\"/; s/"action":"created"/"action":"conflict"/' \
    "$CURL_FIXTURES/call_write_note.body" >"$CURL_FIXTURES/conflict.body"
  mv "$CURL_FIXTURES/conflict.body" "$CURL_FIXTURES/call_write_note.body"
  run "$SYNC"
  assert_failure
  assert_output --partial "failed 5"
  [[ ! -s "$STATE_DIR/state.tsv" ]] || fail "a conflicting write reached the state"
}

@test "--hook on a Mac without a state folder yet prints nothing, exits 0 and logs to a new state folder when the endpoint is down" {
  [[ ! -e "$STATE_DIR" ]] || fail "the test needs a fresh HOME without a state folder"
  local i
  export CURL_STUB_EXIT=7
  run "$SYNC" --hook
  assert_success
  assert_output ""
  # shellcheck disable=SC2034 # i only counts the tries
  for i in $(seq 50); do
    grep -q 'sync skipped' "$STATE_DIR/sync.log" 2>/dev/null && break
    /bin/sleep 0.1
  done
  grep -q 'basic-memory unreachable (run make tunnel); sync skipped' "$STATE_DIR/sync.log" || fail "no skip line in sync.log"
}

@test "--full writes every file again and deletes this device's notes that no local file backs, although the state says everything is synced" {
  "$SYNC" 2>/dev/null
  rm -f "$STUB_LOG.requests"
  printf 'data: %s\n' "$(jq -cn '{jsonrpc: "2.0", id: 2, result: {isError: false, structuredContent: {result: {has_more: false, results: [
    {title: "MEMORY", permalink: "main/agent-memory/acme-widget/claude-code/mac-test/memory", file_path: "agent-memory/acme-widget/claude-code/mac-test/MEMORY.md"},
    {title: "old", permalink: "main/agent-memory/acme-widget/claude-code/mac-test/old", file_path: "agent-memory/acme-widget/claude-code/mac-test/old.md"},
    {title: "MEMORY", permalink: "main/agent-memory/acme-widget/claude-code/mac-other/memory", file_path: "agent-memory/acme-widget/claude-code/mac-other/MEMORY.md"}]}}}}')" \
    >"$CURL_FIXTURES/call_search_notes.body"
  run "$SYNC" --full
  assert_success
  assert_equal "$(tool_calls write_note)" 5
  assert_equal "$(jq -c 'select(.params.name == "search_notes") | .params.arguments.metadata_filters' "$STUB_LOG.requests")" '{"device":"mac-test","mirror":true}'
  assert_equal "$(jq -r 'select(.params.name == "delete_note") | .params.arguments.identifier' "$STUB_LOG.requests")" \
    main/agent-memory/acme-widget/claude-code/mac-test/old
}

@test "refuses a missing BM_MEMORY_DEVICE before any request" {
  export BM_MEMORY_DEVICE=
  run "$SYNC"
  assert_failure
  assert_output --partial "BM_MEMORY_DEVICE must be"
  refute_stub_called '^curl '
}

@test "keeps each Claude folder's repo in keys.tsv: a run with nothing to send reads no session file, a later write sends the repo after the session files are gone, and an older two-column line gets its repo once" {
  "$SYNC" 2>/dev/null
  REAL_FIND="$(command -v find)"
  export REAL_FIND
  # shellcheck disable=SC2016 # the fake expands its arguments when it runs
  fake_cmd find 'case "$*" in *jsonl*) echo "find $*" >>"$STUB_LOG" ;; esac
exec "$REAL_FIND" "$@"'
  : >"$STUB_LOG"
  run "$SYNC"
  assert_success
  refute_stub_called jsonl
  rm "$CLAUDE_MEM/s1.jsonl"
  echo changed >>"$CLAUDE_MEM/memory/MEMORY.md"
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(jq -r 'select(.params.name == "write_note") | .params.arguments.metadata.repo' "$STUB_LOG.requests")" github.com/acme/widget
  printf '{"cwd":"%s"}\n' "$WIDGET" >"$CLAUDE_MEM/s1.jsonl"
  cut -f1,2 "$STATE_DIR/keys.tsv" >"$BATS_TEST_TMPDIR/keys.old"
  cp "$BATS_TEST_TMPDIR/keys.old" "$STATE_DIR/keys.tsv"
  echo again >>"$CLAUDE_MEM/memory/MEMORY.md"
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(jq -r 'select(.params.name == "write_note") | .params.arguments.metadata.repo' "$STUB_LOG.requests")" github.com/acme/widget
  assert_equal "$(cat "$STATE_DIR/keys.tsv")" "$(printf '%s\t%s\t%s' "${CLAUDE_MEM##*/}" acme-widget github.com/acme/widget)"
}

@test "mirrors a Claude memory folder that is a symlink to another folder" {
  mv "$CLAUDE_MEM/memory" "$BATS_TEST_TMPDIR/dotfiles-memory"
  ln -s "$BATS_TEST_TMPDIR/dotfiles-memory" "$CLAUDE_MEM/memory"
  run "$SYNC"
  assert_success
  assert_equal "$(written_notes | grep -c '^agent-memory/acme-widget/claude-code/mac-test/')" 2
}

@test "mirrors nothing new and deletes nothing when the Claude projects folder itself is a symlink" {
  "$SYNC" 2>/dev/null
  cp "$STATE_DIR/state.tsv" "$BATS_TEST_TMPDIR/state.before"
  mv "$HOME/.claude/projects" "$BATS_TEST_TMPDIR/dotfiles-projects"
  ln -s "$BATS_TEST_TMPDIR/dotfiles-projects" "$HOME/.claude/projects"
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(tool_calls delete_note)" 0
  assert_equal "$(tool_calls write_note)" 0
  assert_same_file "$BATS_TEST_TMPDIR/state.before" "$STATE_DIR/state.tsv"
}

@test "does not mirror a file with a token-like secret and deletes its earlier mirror" {
  local secret
  for secret in "tskey-auth-k$(printf 'A%.0s' {1..8})-$(printf 'k%.0s' {1..12})" "gho_$(printf 'a%.0s' {1..36})" \
    "github_pat_$(printf 'b%.0s' {1..82})" "ASIA$(printf 'C%.0s' {1..16})" "xoxb-1234-$(printf 'd%.0s' {1..12})" \
    "sk-ant-api03-$(printf 'e%.0s' {1..24})" "sk-proj-$(printf 'f%.0s' {1..12})T3BlbkFJ" "AIza$(printf 'g%.0s' {1..35})" \
    "-----BEGIN OPENSSH PRIVATE"" KEY-----"; do
    (
      echo note >"$CLAUDE_MEM/memory/회의 메모.md" && "$SYNC" 2>/dev/null && rm -f "$STUB_LOG.requests" \
        && printf 'token %s\n' "$secret" >"$CLAUDE_MEM/memory/회의 메모.md" || exit 1
      run "$SYNC"
      assert_success && assert_output --partial "looks like it holds a secret" \
        && assert_equal "$(tool_calls write_note)" 0 && assert_equal "$(tool_calls delete_note)" 1
    ) || fail "secret pattern ${secret:0:5}"
  done
}

@test "exits quietly while another run holds a fresh lock, and clears a lock older than 10 minutes" {
  mkdir -p "$STATE_DIR/lock"
  run "$SYNC"
  assert_success
  refute_stub_called '^curl '
  touch -t 202001010000 "$STATE_DIR/lock"
  run "$SYNC"
  assert_success
  assert_stub_called '^curl '
  [[ ! -e "$STATE_DIR/lock" ]] || fail "lock left behind"
}

@test "gives a second Claude folder of the same repo the key <key>--<folder name> and a third one a hashed suffix, with a warning, so no two folders share a note path" {
  local clone folder
  for clone in "$BATS_TEST_TMPDIR/work2/widget" "$BATS_TEST_TMPDIR/work3/widget"; do
    git init -q "$clone" && git -C "$clone" remote add origin https://github.com/acme/widget.git
    folder="$HOME/.claude/projects/$(claude_folder_name "$clone")"
    mkdir -p "$folder/memory" && printf '{"cwd":"%s"}\n' "$clone" >"$folder/s1.jsonl" && echo other >"$folder/memory/MEMORY.md"
  done
  run "$SYNC"
  assert_success
  assert_output --partial "project key acme-widget is taken"
  assert_equal "$(written_notes | grep -c '^agent-memory/acme-widget--widget/claude-code/mac-test/MEMORY$')" 1
  assert_equal "$(written_notes | grep -c -E '^agent-memory/acme-widget--widget-[0-9a-f]{6}/claude-code/mac-test/MEMORY$')" 1
}

@test "stops before any request and keeps the state when a Claude or Codex memory folder cannot be listed in full" {
  local root
  mkdir -p "$CLAUDE_MEM/memory/locked" "$CODEX_MEM/locked"
  echo a >"$CLAUDE_MEM/memory/locked/a.md"
  echo b >"$CODEX_MEM/locked/b.md"
  "$SYNC" 2>/dev/null
  cp "$STATE_DIR/state.tsv" "$BATS_TEST_TMPDIR/state.before"
  # The tests run as root, which reads folders of mode 000, so this find fails the way it does for a user on an
  # unreadable subfolder: it lists the other files, reports the folder and exits 1.
  REAL_FIND="$(command -v find)"
  export REAL_FIND
  # shellcheck disable=SC2016 # the fake expands its arguments when it runs
  fake_cmd find 'if [[ "$1" == -H && "$2" == "$LOCKED_ROOT" ]]; then
  "$REAL_FIND" -H "$2" -path "$2/locked" -prune -o "${@:3}"
  echo "find: $2/locked: Permission denied" >&2
  exit 1
fi
exec "$REAL_FIND" "$@"'
  for root in "$CLAUDE_MEM/memory" "$CODEX_MEM"; do
    (
      : >"$STUB_LOG" && export LOCKED_ROOT="$root" || exit 1
      run "$SYNC"
      assert_failure && assert_output --partial "cannot list every file under" && refute_stub_called '^curl ' \
        && assert_same_file "$BATS_TEST_TMPDIR/state.before" "$STATE_DIR/state.tsv"
    ) || fail "unlistable folder ${root#"$HOME"/}"
  done
}

@test "writes a file again on the next run after its --full write failed, although the file did not change" {
  "$SYNC" 2>/dev/null
  printf 'data: %s\n' '{"jsonrpc":"2.0","id":2,"result":{"isError":false,"structuredContent":{"result":{"has_more":false,"results":[]}}}}' \
    >"$CURL_FIXTURES/call_search_notes.body"
  export CURL_STUB_FAIL_MATCH='"title":"MEMORY"'
  run "$SYNC" --full
  assert_failure
  unset CURL_STUB_FAIL_MATCH
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(written_notes)" \
    "$(printf '%s\n' agent-memory/_global/codex/mac-test/v2/MEMORY agent-memory/acme-widget/claude-code/mac-test/MEMORY)"
}

# add_claude_files COUNT -> COUNT more Claude memory files (extra-1.md ...) in the widget folder.
add_claude_files() {
  local i
  for ((i = 1; i <= $1; i++)); do echo "extra $i" >"$CLAUDE_MEM/memory/extra-$i.md"; done
}

@test "sends at most 10 write_note calls per run with a 3 second pause between two of them, says how many wait, and the next run sends the rest" {
  add_claude_files 7
  run "$SYNC"
  assert_success
  assert_output --partial "synced: wrote 10, deleted 0, failed 0, deferred 2"
  assert_output --partial "2 notes wait for the next memory-sync (at most 10 writes per run)"
  assert_equal "$(tool_calls write_note)" 10
  assert_equal "$(grep -c '^sleep 3$' "$STUB_LOG")" 9
  assert_equal "$(grep -c '^sleep ' "$STUB_LOG")" 9
  assert_equal "$(wc -l <"$STATE_DIR/state.tsv" | tr -d ' ')" 10
  rm -f "$STUB_LOG.requests"
  : >"$STUB_LOG"
  run "$SYNC"
  assert_success
  assert_output --partial "synced: wrote 2, deleted 0, failed 0, deferred 0"
  refute_output --partial "wait for the next memory-sync"
  assert_equal "$(tool_calls write_note)" 2
  assert_equal "$(tool_calls delete_note)" 0
  assert_equal "$(grep -c '^sleep 3$' "$STUB_LOG")" 1
  assert_equal "$(wc -l <"$STATE_DIR/state.tsv" | tr -d ' ')" 12
}

@test "stops after 2 failed requests in a row, warns, counts the unsent writes as deferred and exits 1, and the next run writes everything" {
  export CURL_STUB_FAIL_MATCH='"name":"write_note"'
  run "$SYNC"
  assert_failure
  assert_output --partial "WARNING: basic-memory did not answer 2 requests in a row; stopped sending, the next memory-sync continues"
  assert_output --partial "synced: wrote 0, deleted 0, failed 2, deferred 3"
  assert_equal "$(grep -c '"name":"write_note"' "$STUB_LOG")" 2
  unset CURL_STUB_FAIL_MATCH
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(tool_calls write_note)" 5
}

@test "--full writes 10 of 12 files, keeps the others with an empty sha256, and the next normal run writes the rest" {
  add_claude_files 7
  "$SYNC" 2>/dev/null
  "$SYNC" 2>/dev/null
  printf 'data: %s\n' '{"jsonrpc":"2.0","id":2,"result":{"isError":false,"structuredContent":{"result":{"has_more":false,"results":[]}}}}' \
    >"$CURL_FIXTURES/call_search_notes.body"
  rm -f "$STUB_LOG.requests"
  run "$SYNC" --full
  assert_success
  assert_output --partial "2 notes wait for the next memory-sync"
  assert_equal "$(tool_calls write_note)" 10
  assert_equal "$(awk -F'\t' '$3 == ""' "$STATE_DIR/state.tsv" | wc -l | tr -d ' ')" 2
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_success
  assert_equal "$(tool_calls write_note)" 2
  assert_equal "$(awk -F'\t' '$3 == ""' "$STATE_DIR/state.tsv" | wc -l | tr -d ' ')" 0
}

@test "starts the next run's writes at the first note a run did not send, so ten notes that always conflict cannot block the rest, and clears that cursor once a run sends everything" {
  add_claude_files 8
  export CURL_STUB_CONFLICT_MATCH='"directory":"agent-memory/acme-widget'
  run "$SYNC"
  assert_failure
  assert_output --partial "failed 10, deferred 3"
  assert_equal "$(cut -d/ -f1-3 "$STATE_DIR/next-write.txt")" agent-memory/_global/codex
  rm -f "$STUB_LOG.requests"
  run "$SYNC"
  assert_failure
  assert_equal "$(grep -c '/codex/' "$STATE_DIR/state.tsv")" 3
  assert_equal "$(grep -c 'acme-widget' "$STATE_DIR/state.tsv")" 0
  assert_equal "$(cut -d/ -f1-3 "$STATE_DIR/next-write.txt")" agent-memory/acme-widget/claude-code
  unset CURL_STUB_CONFLICT_MATCH
  run "$SYNC"
  assert_success
  assert_equal "$(wc -l <"$STATE_DIR/state.tsv" | tr -d ' ')" 13
  [[ ! -e "$STATE_DIR/next-write.txt" ]] || fail "the cursor is still there after a run that sent every write"
}
