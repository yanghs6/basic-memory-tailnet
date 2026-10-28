#!/usr/bin/env bats
load helpers

setup() {
  GUARD="$REPO_DIR/scripts/guard-agent-bash.sh"
}

# payload COMMAND: the PreToolUse hook input Claude Code sends for a Bash call.
payload() {
  jq -cn --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}'
}

# guard COMMAND: run the guard on the hook input for COMMAND.
guard() {
  "$GUARD" <<<"$(payload "$1")"
}

# assert_denied COMMAND: the guard blocks COMMAND with exit 2 and an actionable message.
assert_denied() {
  run guard "$1"
  [[ "$status" -eq 2 ]] || fail "expected exit 2 (deny) for: $1; got $status: $output"
  [[ "$output" == *"blocked by the agent Bash guard"* ]] || fail "no reason given for: $1; got: $output"
}

# assert_asks COMMAND: the guard answers COMMAND with exit 0 and an ask decision.
assert_asks() {
  run guard "$1"
  [[ "$status" -eq 0 ]] || fail "expected exit 0 for: $1; got $status: $output"
  jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "ask" and (.hookSpecificOutput.permissionDecisionReason | length > 0)' <<<"$output" >/dev/null \
    || fail "expected an ask decision for: $1; got: $output"
}

@test "denies deleting backups or the basic-memory.prev directories, also in wrapped forms" {
  local cmd commands
  commands=(
    "rm -rf backups"
    "rm -rf ./backups/2026-10-01"
    "rm -r /srv/basic-memory.prev-20261001"
    "sh -c 'rm -rf backups'"
    "bash -c \"rm -rf basic-memory.prev-1\""
    "cd /x && rm -rf backups/old"
    "/bin/rm -rf backups"
  )
  for cmd in "${commands[@]}"; do
    assert_denied "$cmd"
  done
}

@test "asks before a force-push in every spelling, also in wrapped forms" {
  local cmd commands
  commands=(
    "git push --force"
    "git push origin plan/x --force"
    "git push --force-with-lease origin plan/x"
    "git push -f origin plan/x"
    "git push origin plan/x -f"
    "git push origin +main"
    "git push origin +plan/x:plan/x"
    "sh -c 'git push --force origin plan/x'"
    "bash -c \"git push origin +main\""
    "env git push --force"
    "git -C . push -f"
    "git -C . push origin +main"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks before a direct call of a VM-changing script, script or expect around restore, and gcloud create or delete" {
  local cmd commands
  commands=(
    "scripts/restore-notes.sh backups/x"
    "bash scripts/deploy-stack.sh"
    "./scripts/bootstrap-vm.sh"
    "sh -c 'scripts/upload-sb-fonts.sh'"
    "script -q /dev/null make restore"
    "expect -c 'spawn make restore'"
    "gcloud compute instances create x"
    "gcloud compute instances delete x"
    "gcloud --configuration=bm-personal compute firewall-rules create y"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "passes ordinary commands with exit 0 and no output" {
  local cmd commands
  commands=(
    "git push origin plan/x"
    "git push -u origin work/y"
    "rm -rf .review-out"
    "rm -rf node_modules"
    "git log --oneline"
    "git status"
    "make check"
    "make restore"
    "ls backups"
    "cat docs/README.md"
    "gcloud compute instances list"
    "gcloud compute instances describe x"
    "grep -rn script scripts"
    "scripts/show-status.sh"
  )
  for cmd in "${commands[@]}"; do
    run guard "$cmd"
    [[ "$status" -eq 0 ]] || fail "expected '$cmd' to pass; got $status: $output"
    assert_output ""
  done
}

@test "fails closed on invalid JSON, a missing command, a non-string command and empty input" {
  run "$GUARD" <<<"not json"
  [[ "$status" -eq 2 ]] || fail "invalid JSON: expected 2, got $status: $output"
  run "$GUARD" <<<'{"tool_input":{}}'
  [[ "$status" -eq 2 ]] || fail "missing command: expected 2, got $status: $output"
  run "$GUARD" <<<'{"tool_input":{"command":5}}'
  [[ "$status" -eq 2 ]] || fail "numeric command: expected 2, got $status: $output"
  run "$GUARD" <<<'{"tool_input":{"command":""}}'
  [[ "$status" -eq 2 ]] || fail "empty command: expected 2, got $status: $output"
  run "$GUARD" <<<""
  [[ "$status" -eq 2 ]] || fail "empty input: expected 2, got $status: $output"
}
