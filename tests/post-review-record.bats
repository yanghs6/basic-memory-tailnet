#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  RECORD="$REPO_DIR/scripts/post-review-record.sh"
  FINDINGS="$BATS_TEST_TMPDIR/findings.md"
  printf '| ID | Sev | Location | Summary | Status |\n|---|---|---|---|---|\n| R1-F1 | P1 | scripts/x.sh:1 | breaks | open |\n' >"$FINDINGS"
}

@test "creates the Review record when the PR has none and updates the one it has" {
  local case records ids call other
  # Each case: the Review records the PR has | the ids gh finds for them | the call that writes the record | the write
  # method that must not run.
  for case in "none||POST repos/{owner}/{repo}/issues/12/comments|PATCH" \
    "one|4242|PATCH repos/{owner}/{repo}/issues/comments/4242|POST"; do
    IFS='|' read -r records ids call other <<<"$case"
    (
      : >"$STUB_LOG" && rm -f "$STUB_LOG.body" || exit 1
      GH_STUB_JQ_OUTPUT="$ids" run "$RECORD" 12 "$FINDINGS"
      assert_success || exit 1
      # Only the machine account's comments count: on a public repo anyone can post the marker.
      assert_stub_called -F 'select(.user.login == "agent-bot" and (.body | startswith("<!-- review-record -->")))' \
        && assert_stub_called -F "gh api -X $call -F body=@" && refute_stub_called "$other" || exit 1
      run head -n 1 "$STUB_LOG.body"
      assert_output "<!-- review-record -->" || exit 1
      run grep -F '| R1-F1 | P1 |' "$STUB_LOG.body"
      assert_success
    ) || fail "post-review-record when the PR has $records Review record"
  done
}

@test "writes nothing when the PR has several records or gh reports no login" {
  local case problem message
  # Each case: what gh reports | the message of the check that stops before any write.
  for case in "several records|has 2 Review record comments" "no login|gh returned no login"; do
    IFS='|' read -r problem message <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      case "$problem" in
        "several records") export GH_STUB_JQ_OUTPUT=$'1\n2' ;;
        "no login") export GH_STUB_LOGIN='' ;;
      esac || exit 1
      run "$RECORD" 12 "$FINDINGS"
      assert_failure && assert_output --partial "$message" && refute_stub_called -E 'POST|PATCH'
    ) || fail "post-review-record wrote although gh reported $problem"
  done
}
