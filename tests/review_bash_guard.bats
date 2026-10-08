#!/usr/bin/env bats
load helpers

setup() {
  GUARD="$REPO_DIR/scripts/review-bash-guard.sh"
}

# payload COMMAND: the PreToolUse hook input Claude Code sends for a Bash call.
payload() {
  jq -cn --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}'
}

# guard COMMAND: run the guard on the hook input for COMMAND.
guard() {
  "$GUARD" <<<"$(payload "$1")"
}

# assert_blocked COMMAND: the guard blocks COMMAND with exit 2 (the only exit code that blocks) and says why.
assert_blocked() {
  run guard "$1"
  [[ "$status" -eq 2 ]] || fail "expected exit 2 (blocked) for: $1; got $status: $output"
  [[ "$output" == *"blocked by the review Bash guard"* ]] || fail "no reason given for: $1; got: $output"
}

@test "allows read-only git diff, git log and git show" {
  local cmd
  for cmd in \
    "git diff main...HEAD" \
    "git diff --stat main...HEAD -- scripts/review.sh" \
    "git log" \
    "git log --oneline main..HEAD" \
    "git log --format=fuller review-base/plan-02-x-r2..HEAD" \
    "git log --author=agent@example.com -n 3" \
    "git diff -U5 HEAD^ HEAD -- a,b+c" \
    "git show HEAD:AGENTS.md" \
    "git show --stat HEAD~1"; do
    run guard "$cmd"
    [[ "$status" -eq 0 ]] || fail "expected '$cmd' to be allowed; got $status: $output"
    assert_output ""
  done
}

@test "blocks shell operators in an allowed git command" {
  local cmd
  for cmd in \
    "git diff; rm -rf scripts" \
    "git diff && touch x" \
    "git diff & touch x" \
    "git log | sh" \
    'git show `touch x`' \
    'git show $(touch x)' \
    'git show ${HOME}' \
    'git show $HOME' \
    "git diff > out.txt" \
    "git diff >> out.txt" \
    "git diff < in.txt" \
    "git diff"$'\n'"touch x" \
    "git diff"$'\r'"touch x"; do
    assert_blocked "$cmd"
  done
}

@test "blocks git options that write files, including abbreviations" {
  assert_blocked "git diff --output=x.patch main...HEAD"
  assert_blocked "git log -p --output x.patch"
  assert_blocked "git diff --outp=/tmp/x"
  assert_blocked "git show --ou=/tmp/x"
}

@test "blocks quoting and escapes that the shell would strip into --output" {
  assert_blocked 'git diff --o""utput=/tmp/x'
  assert_blocked "git diff --ou''tput=/tmp/x"
  assert_blocked 'git diff --outp\ut=/tmp/x'
}

@test "blocks anything but single-space-separated plain tokens" {
  local cmd
  for cmd in \
    "git diff"$'\t'"main" \
    "git diff  main" \
    "git diff main " \
    "git show *.md" \
    "git show HEAD:scripts/?.sh" \
    "git log [a]" \
    "git show 'HEAD:AGENTS.md'" \
    'git show "HEAD:AGENTS.md"' \
    "git log --format=%h" \
    "git log {a,b}"; do
    assert_blocked "$cmd"
  done
}

@test "blocks every other git subcommand" {
  local cmd
  for cmd in \
    "git status" \
    "git commit -m x" \
    "git checkout main" \
    "git switch -c x" \
    "git branch -D main" \
    "git reset --hard" \
    "git worktree remove x" \
    "git show-branch" \
    "git diff-tree HEAD" \
    "git -C /tmp diff" \
    "git" \
    " git diff"; do
    assert_blocked "$cmd"
  done
}

@test "blocks commands other than git" {
  local cmd
  for cmd in "rm -rf scripts" "echo hi" "make check" "cat AGENTS.md" "gitdiff" ""; do
    assert_blocked "$cmd"
  done
}

@test "fails closed on empty, invalid or incomplete hook input" {
  local input
  for input in "" "not json" '{"tool_input": {}}' '{"tool_input": {"command": 42}}' '{"tool_name": "Bash"}'; do
    run "$GUARD" <<<"$input"
    [[ "$status" -eq 2 ]] || fail "expected exit 2 for input '$input'; got $status: $output"
  done
}

@test "fails closed when jq is missing" {
  local bin="$BATS_TEST_TMPDIR/no-jq" tool
  mkdir -p "$bin"
  for tool in bash cat dirname; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  run env PATH="$bin" "$GUARD" <<<"$(payload "git diff")"
  assert_failure 2
  assert_output --partial "missing command 'jq'"
}
