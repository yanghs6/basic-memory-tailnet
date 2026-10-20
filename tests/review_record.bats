#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  RECORD="$REPO_DIR/scripts/post-review-record.sh"
  FINDINGS="$BATS_TEST_TMPDIR/findings.md"
  printf '| ID | Sev | Location | Summary | Status |\n|---|---|---|---|---|\n| R1-F1 | P1 | scripts/x.sh:1 | breaks | open |\n' >"$FINDINGS"
}

@test "creates the Review record when the PR has none, with the marker as its first line" {
  run "$RECORD" 12 "$FINDINGS"
  assert_success
  # Only the machine account's comments count: on a public repo anyone can post the marker.
  run grep -F 'select(.user.login == "agent-bot" and (.body | startswith("<!-- review-record -->")))' "$STUB_LOG"
  assert_success
  run grep -F 'gh api -X POST repos/{owner}/{repo}/issues/12/comments -F body=@' "$STUB_LOG"
  assert_success
  run head -n 1 "$STUB_LOG.body"
  assert_output "<!-- review-record -->"
  run grep -F '| R1-F1 | P1 |' "$STUB_LOG.body"
  assert_success
}

@test "updates the existing Review record instead of adding a second one" {
  GH_STUB_JQ_OUTPUT=4242 run "$RECORD" 12 "$FINDINGS"
  assert_success
  run grep -F 'gh api -X PATCH repos/{owner}/{repo}/issues/comments/4242 -F body=@' "$STUB_LOG"
  assert_success
  run grep -c 'POST' "$STUB_LOG"
  assert_output 0
}

@test "refuses to guess when the PR has several Review records" {
  GH_STUB_JQ_OUTPUT=$'1\n2' run "$RECORD" 12 "$FINDINGS"
  assert_failure
  assert_output --partial "has 2 Review record comments"
  run grep -cE 'POST|PATCH' "$STUB_LOG"
  assert_output 0
}

@test "stops instead of creating a second record when gh reports no login" {
  GH_STUB_LOGIN= run "$RECORD" 12 "$FINDINGS"
  assert_failure
  assert_output --partial "gh returned no login"
  run grep -cE 'POST|PATCH' "$STUB_LOG"
  assert_output 0
}
