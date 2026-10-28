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
    "git push -fu origin x"
    "git push -uf origin x"
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
    "scripts/restore-notes.sh x"
    "cd scripts && ./restore-notes.sh"
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

@test "asks when a make call names a VM-changing or posting target in any argument position" {
  local cmd commands
  commands=(
    "make deploy"
    "make restore"
    "make backup deploy"
    "make status deploy"
    "make probe vm-bootstrap"
    "make verify sb-fonts"
    "make review review-post PR=1"
    "make check review-record"
    "make logs memory-hooks"
    "make -C . deploy"
    "cd x && make backup deploy"
    "sh -c 'make status restore'"
    "env make probe deploy"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks before gh writes: api with a non-GET method or fields, gist, issue, release, repo and pr close, merge, review, reopen" {
  local cmd commands
  commands=(
    "gh api -X POST repos/x/y/issues/1/comments -f body=hi"
    "gh api --method PATCH repos/x/y"
    "gh api -XDELETE repos/x/y"
    "gh api --method=PUT repos/x/y"
    "gh api repos/x/y/issues -f title=t"
    "gh api repos/x/y/issues -F title=t"
    "gh api repos/x/y --field a=b"
    "gh api repos/x/y --raw-field a=b"
    "gh api repos/x/y --input body.json"
    "gh gist create notes.txt"
    "gh gist edit abc"
    "gh gist delete abc"
    "gh issue create --title t"
    "gh issue comment 1 --body b"
    "gh issue edit 1"
    "gh issue close 1"
    "gh issue delete 1"
    "gh issue reopen 1"
    "gh issue transfer 1 x/y"
    "gh issue lock 1"
    "gh release create v1"
    "gh release upload v1 f"
    "gh release edit v1"
    "gh release delete v1"
    "gh repo create x"
    "gh repo edit x"
    "gh repo delete x"
    "gh repo rename y"
    "gh repo archive x"
    "gh repo fork x"
    "gh repo sync x"
    "gh pr close 1"
    "gh pr merge 1"
    "gh pr review 1"
    "gh pr reopen 1"
    "sh -c 'gh issue create --title t'"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks before cloud CLI metadata, update, stop, reset and resize changes" {
  local cmd commands
  commands=(
    "gcloud compute instances add-metadata x --metadata a=b"
    "gcloud compute instances remove-metadata x --keys a"
    "gcloud compute firewall-rules update y --allow tcp:22"
    "gcloud compute instances stop x"
    "gcloud compute instances reset x"
    "gcloud compute instances set-machine-type x --machine-type e2-small"
    "gcloud --configuration=bm-personal compute disks resize d --size 20"
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
    "ls backups"
    "cat docs/README.md"
    "gcloud compute instances list"
    "gcloud compute instances describe x"
    "grep -rn script scripts"
    "scripts/show-status.sh"
    "cat scripts/deploy-stack.sh"
    "git add scripts/restore-notes.sh"
    "shellcheck scripts/bootstrap-vm.sh"
    "grep -n confirm scripts/restore-notes.sh"
    "git push origin fix-f"
    "git push origin feat/-f"
    "git commit -m \"add +x flag\""
    "echo format term"
    "make check"
    "make test"
    "make backup"
    "make review"
    "make backup-latest"
    "make memory-sync"
    "make check; echo deploy"
    "git log --grep deploy"
    "cat docs/deploy.md"
    "gh pr view 1"
    "gh pr list"
    "gh api repos/x/y/issues/1/comments"
    "gh api -X GET repos/x/y"
    "gh api --method get repos/x/y"
    "gh issue list"
    "gh issue view 3"
    "gh release list"
    "gcloud compute instances describe x"
    "gcloud --version"
    "gh --version"
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
