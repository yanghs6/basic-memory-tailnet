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
  # The test image's jq -e passes on empty input, so an empty answer must fail here first.
  [[ -n "$output" ]] || fail "expected an ask decision for: $1; got no output"
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

@test "asks before a direct call of a VM-changing or posting script, script or expect around restore, and gcloud create or delete" {
  local cmd commands
  commands=(
    "scripts/restore-notes.sh backups/x"
    "bash scripts/deploy-stack.sh"
    "./scripts/bootstrap-vm.sh"
    "sh -c 'scripts/upload-sb-fonts.sh'"
    "scripts/restore-notes.sh x"
    "cd scripts && ./restore-notes.sh"
    "scripts/post-review.sh 1 plan/x codex"
    "bash scripts/post-review-record.sh 1 f"
    "sh -c './scripts/post-review.sh 1 b codex'"
    "cd scripts && ./post-review-record.sh 1 f"
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

@test "asks when a make call passes an option, a quoted, escaped or expanded argument, an undocumented variable or a command in a redirection, also as an assignment in front of make, inside sh -c or in a later call" {
  local cmd commands
  commands=(
    "make probe \"deploy\""
    "make probe 'deploy'"
    'make probe dep\loy'
    "make probe -f x.mk"
    "make probe --file=x.mk"
    "make probe -C /tmp/x"
    "make probe --eval=x"
    "make probe SHELL=./x.sh"
    "make probe MAKEFILES=x.mk"
    "make probe BASH_ENV=./x.sh"
    "make probe DOCKER_RUN=x"
    "make check-git BRANCH=\$(id)"
    "make probe HOST=\`id\`"
    "BASH_ENV=./x.sh make probe"
    "make probe ';x:=\$(shell id)'"
    "make probe <(id)"
    "make probe >\`id\`"
    "sh -c 'make probe BASH_ENV=./x.sh'"
    "make check && make probe SHELL=./x.sh"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks when an assignment, env, a wrapper with its options, a shell keyword or a backtick stands before a VM-changing, posting or gh or cloud CLI write call" {
  local cmd commands
  commands=(
    "BM_WEB=on make deploy"
    "env BM_WEB=on make deploy"
    "time make restore"
    "GH_REPO=a/b gh pr create"
    "nohup scripts/deploy-stack.sh"
    "nice -n 5 make deploy"
    "sudo -E make restore"
    "xargs -0 make deploy"
    "exec scripts/bootstrap-vm.sh"
    "command make deploy"
    "bash -lc 'make deploy'"
    "if make deploy; then echo ok; fi"
    "{ make deploy; }"
    "echo \`gh pr merge 1\`"
    "echo \`make deploy\`"
    "X=1 gcloud compute instances start x"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks before gh writes: api with a non-GET method or fields, gist, issue, release, repo and pr create, edit, comment, ready, close, merge, review, reopen" {
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
    "gh pr create --draft --title t"
    "gh pr edit 1 --body-file b.md"
    "gh pr comment 1 --body b"
    "gh pr ready 1"
    "sh -c 'gh issue create --title t'"
    "gh -R a/b pr merge 3"
    "gh -R a/b pr comment 3 --body b"
    "gh --repo a/b pr ready 3"
    "gh --repo=a/b pr edit 3 --title t"
    "gh -R a/b pr create --title t"
    "gh --repo a/b pr merge 3"
    "gh --repo=a/b issue close 1"
    "gh -R a/b release delete v1"
    "gh -R a/b api -X POST repos/a/b/issues -f title=t"
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

@test "asks before every cloud CLI call that is not a read-only form: other verbs, ssh, scp, IAM, services, configuration switches, tokens, a read verb as a resource name or after a flag, quoted or expanded words before the verb, a later call and sh -c" {
  local cmd commands
  commands=(
    "gcloud compute instances start x"
    "gcloud compute ssh agent-hub --command \"sudo docker compose down\""
    "gcloud compute scp a agent-hub:b"
    "gcloud projects add-iam-policy-binding p --member m --role r"
    "gcloud services enable x"
    "gcloud compute instances update-from-file x --source f"
    "gcloud config configurations activate x"
    "gcloud auth print-access-token"
    "gcloud compute instances start list"
    "gcloud compute instances --quiet start list"
    'gcloud compute instances --f="a\" list" start x'
    "gcloud --project=\$(echo p) compute instances start x"
    "gcloud compute instances list && gcloud compute instances start x"
    "sh -c 'gcloud compute instances start x'"
  )
  for cmd in "${commands[@]}"; do
    assert_asks "$cmd"
  done
}

@test "asks before every gh call that is not a read-only form: run, workflow, secret, variable, label, alias, extension, auth token, checkout, clone, an expanded repo flag and a later call" {
  local cmd commands
  commands=(
    "gh run cancel 1"
    "gh run rerun 1"
    "gh workflow run x"
    "gh workflow disable x"
    "gh secret set X"
    "gh variable set X"
    "gh label create x"
    "gh alias set co 'pr checkout' --shell"
    "gh extension install x"
    "gh extension exec x"
    "gh auth token"
    "gh auth status --show-token"
    "gh pr checkout 1"
    "gh repo clone x"
    "gh -R \${R:-a;b} pr merge 1"
    "gh pr view 1 && gh pr merge 1"
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
    "cat scripts/post-review.sh"
    "shellcheck scripts/post-review-record.sh"
    "git add scripts/post-review.sh"
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
    "gh -R a/b pr view 3"
    "gh --repo a/b issue list"
    "gh --repo=a/b pr list"
    "gh -R a/b api repos/a/b/issues/1/comments"
    "gh issue view 3"
    "gh release list"
    "gcloud compute instances describe x"
    "gcloud --version"
    "gh --version"
    "gcloud --configuration=bm-personal compute instances describe agent-hub-01 --zone z --format='value(status)'"
    "gcloud config configurations list"
    "gcloud config list"
    "gcloud auth list"
    "gcloud info"
    "grep -rn gcloud docs"
    "sh -c 'gcloud compute instances list'"
    "gh pr diff 1"
    "gh pr checks 1"
    "gh run view 1 --log"
    "gh auth status"
    "gh search prs x"
    "gh api --paginate repos/x/y/issues/1/comments --jq '.[] | .body'"
    "make check 2>&1"
    "make check-git BRANCH=plan/abcdefgh-x"
    "make review BRANCH=plan/abcdefgh-x REVIEWER=codex ROUND=2"
    "make new-doc TYPE=plan SLUG=a-b ID=abcdefgh"
    "make export-logs SINCE=24h"
    "make memory-sync FULL=1"
    "cd x && make backup"
    "sh -c 'make probe'"
    "nice -n 5 make check"
    "x=\`make help\`"
    "time gcloud compute instances list"
    "echo time make restore"
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
