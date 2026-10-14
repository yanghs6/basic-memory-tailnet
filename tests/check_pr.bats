#!/usr/bin/env bats
load helpers

setup() {
  CHECK="$REPO_DIR/scripts/check-pr.sh"
  GOOD_BODY="Summary of the change.

Assisted-by: claude-code claude-opus-5-5
Plan: 08"
}

@test "passes a conventional title and a body ending in the trailers, also with GitHub CRLF line ends" {
  PR_TITLE="feat: add the pull request rules" PR_BODY="$GOOD_BODY" run "$CHECK"
  assert_success
  assert_output --partial "OK: PR title and trailers"
  local crlf_body
  crlf_body="$(printf 'Summary.\r\n\r\nAssisted-by: claude-code claude-opus-5-5\r\nAssisted-by: codex gpt-6.1-sol\r\nPlan: none\r\n')"
  PR_TITLE="docs: two tools worked here" PR_BODY="$crlf_body" run "$CHECK"
  assert_success
}

@test "rejects titles that are not '<type>: <description>'" {
  local title
  for title in "Add rules" "Feat: add rules" "feature: add rules" "feat:add rules" "feat(ci): add rules"; do
    PR_TITLE="$title" PR_BODY="$GOOD_BODY" run "$CHECK"
    [[ "$status" -eq 1 ]] || fail "expected title '$title' to be rejected; got $status: $output"
    assert_output --partial "title '$title' must be '<type>: <description>'"
  done
}

@test "fails when the trailers are missing or not in the last paragraph" {
  local body
  for body in "" "Summary only." "$GOOD_BODY

Thanks for reviewing."; do
    PR_TITLE="feat: x" PR_BODY="$body" run "$CHECK"
    [[ "$status" -eq 1 ]] || fail "expected the body to be rejected; got $status: $output"
    assert_output --partial "missing trailer 'Assisted-by:"
    assert_output --partial "missing trailer 'Plan:"
  done
}

@test "rejects malformed trailer values, including a second Plan line" {
  PR_TITLE="feat: x" PR_BODY="Summary.

Assisted-by: Claude
Plan: 8" run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Assisted-by: Claude' must be"
  assert_output --partial "trailer 'Plan: 8' must be"
  PR_TITLE="feat: x" PR_BODY="$GOOD_BODY
Plan: 09" run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Plan: 08,09' must be"
}

@test "rejects Co-authored-by and Signed-off-by in the body because the squash commit would carry them" {
  PR_TITLE="feat: x" PR_BODY="$GOOD_BODY
Co-authored-by: Bot <bot@example.com>
Signed-off-by: Bot <bot@example.com>" run "$CHECK"
  assert_failure
  assert_output --partial "must not carry 'Co-authored-by'"
  assert_output --partial "must not carry 'Signed-off-by'"
}

@test "fails instead of passing when CI does not pass the title" {
  PR_BODY="$GOOD_BODY" run "$CHECK"
  assert_failure
  assert_output --partial "PR_TITLE is empty"
}
