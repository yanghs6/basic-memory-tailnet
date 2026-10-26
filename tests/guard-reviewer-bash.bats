#!/usr/bin/env bats
load helpers

setup() {
  GUARD="$REPO_DIR/scripts/guard-reviewer-bash.sh"
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
    "git log --format=fuller review-base/plan-k7m2x9qa-x-r2..HEAD" \
    "git log --author=agent@example.com -n 3" \
    "git diff -U5 HEAD^ HEAD -- a,b+c" \
    "git show HEAD:AGENTS.md" \
    "git show --stat HEAD~1" \
    "git diff --text main...HEAD"; do
    run guard "$cmd"
    [[ "$status" -eq 0 ]] || fail "expected '$cmd' to be allowed; got $status: $output"
    assert_output ""
  done
}

@test "blocks shell operators, file-writing and helper options with their abbreviations, anything but plain single-spaced tokens and every other command" {
  local cmd commands
  # shellcheck disable=SC2016 # the commands are the literal text the guard must refuse, not run here
  commands=(
    # Shell operators in an allowed git command.
    "git diff; rm -rf scripts"
    "git diff && touch x"
    "git diff & touch x"
    "git log | sh"
    'git show `touch x`'
    'git show $(touch x)'
    'git show ${HOME}'
    'git show $HOME'
    "git diff > out.txt"
    "git diff >> out.txt"
    "git diff < in.txt"
    "git diff"$'\n'"touch x"
    "git diff"$'\r'"touch x"
    # Git options that write files, including abbreviations.
    "git diff --output=x.patch main...HEAD"
    "git log -p --output x.patch"
    "git diff --outp=/tmp/x"
    "git show --ou=/tmp/x"
    # Git options that run external diff or textconv helpers, including abbreviations.
    "git diff --ext-diff main...HEAD"
    "git diff --ext main...HEAD"
    "git show --textconv HEAD"
    "git log -p --textc"
    # Anything but single-space-separated plain tokens. The first three reproduce a real bypass where the shell stripped
    # quotes/escapes into --output (commit 5a9c7d7); keep them.
    'git diff --o""utput=/tmp/x'
    "git diff --ou''tput=/tmp/x"
    'git diff --outp\ut=/tmp/x'
    "git diff"$'\t'"main"
    "git diff  main"
    "git diff main "
    "git show *.md"
    "git show HEAD:scripts/?.sh"
    "git log [a]"
    "git show 'HEAD:AGENTS.md'"
    'git show "HEAD:AGENTS.md"'
    "git log --format=%h"
    "git log {a,b}"
    # Every other git subcommand and every non-git command.
    "git status"
    "git commit -m x"
    "git checkout main"
    "git switch -c x"
    "git branch -D main"
    "git reset --hard"
    "git worktree remove x"
    "git show-branch"
    "git diff-tree HEAD"
    "git -C /tmp diff"
    "git"
    " git diff"
    "rm -rf scripts"
    "echo hi"
    "make check"
    "cat AGENTS.md"
    "gitdiff"
    ""
  )
  for cmd in "${commands[@]}"; do
    assert_blocked "$cmd"
  done
}

@test "fails closed on bad hook input and without jq" {
  local no_jq="$BATS_TEST_TMPDIR/no-jq" tool case problem input path
  mkdir -p "$no_jq"
  for tool in bash cat dirname; do
    ln -s "$(command -v "$tool")" "$no_jq/$tool"
  done
  # Each case: what is wrong | the hook input. Only the jq case gets a good input, and a PATH without jq.
  for case in "empty input|" "not JSON|not json" 'no command|{"tool_input": {}}' \
    'a number as the command|{"tool_input": {"command": 42}}' 'no tool_input|{"tool_name": "Bash"}' \
    "no jq|$(payload "git diff")"; do
    IFS='|' read -r problem input <<<"$case"
    path="$PATH"
    [[ "$problem" != "no jq" ]] || path="$no_jq"
    (
      run env PATH="$path" "$GUARD" <<<"$input"
      assert_failure 2 || exit 1
      # Without jq the guard would block anyway when jq fails; the message shows that require_cmd stopped it first.
      if [[ "$problem" == "no jq" ]]; then
        assert_output --partial "missing command 'jq'"
      fi
    ) || fail "the guard did not fail closed with exit 2 on: $problem"
  done
}
