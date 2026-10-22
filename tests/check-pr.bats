#!/usr/bin/env bats
load helpers

setup() {
  CHECK="$REPO_DIR/scripts/check-pr.sh"
  GOOD_BODY="Summary of the change.

Assisted-by: claude-code claude-opus-5-5
Plan: 08"
}

@test "passes a conventional title and a body ending in the trailers, also with CRLF line ends, a horizontal rule above them or only the trailers" {
  local crlf_body rule_body trailers_only_body body
  crlf_body="$(printf 'Summary.\r\n\r\nAssisted-by: claude-code claude-opus-5-5\r\nAssisted-by: codex gpt-6.1-sol\r\nPlan: none\r\n')"
  rule_body="Summary.

---

Assisted-by: claude-code claude-opus-5-5
Plan: 08"
  trailers_only_body="Assisted-by: claude-code claude-opus-5-5
Plan: 08"
  for body in "$GOOD_BODY" "$crlf_body" "$rule_body" "$trailers_only_body"; do
    PR_TITLE="feat: add the pull request rules" PR_BODY="$body" run "$CHECK"
    assert_success
    assert_output --partial "OK: PR title and trailers"
  done
}

@test "rejects an empty title and titles that are not '<type>: <description>'" {
  local title message
  # <unset> stands for no PR_TITLE at all (CI did not pass the title). The title check would also refuse an unset or
  # empty title, so the message tells them apart.
  for title in "<unset>" "" "Add rules" "Feat: add rules" "feature: add rules" "feat:add rules" "feat(ci): add rules"; do
    message="title '$title' must be '<type>: <description>'"
    [[ -n "$title" && "$title" != "<unset>" ]] || message="PR_TITLE is empty"
    (
      if [[ "$title" == "<unset>" ]]; then
        unset PR_TITLE
        PR_BODY="$GOOD_BODY" run "$CHECK"
      else
        PR_TITLE="$title" PR_BODY="$GOOD_BODY" run "$CHECK"
      fi
      assert_failure 1 && assert_output --partial "$message"
    ) || fail "check-pr did not reject the title '$title'"
  done
}

@test "fails on missing, misplaced, malformed, repeated and forbidden trailers and session links in the body" {
  local case input problems body line
  # Each case: the body's problem | what check-pr.sh must list for it, |-separated. The case block builds the body.
  for case in "no body|missing trailer 'Assisted-by:|missing trailer 'Plan:" \
    "a summary only|missing trailer 'Assisted-by:|missing trailer 'Plan:" \
    "text after the trailers|missing trailer 'Assisted-by:|missing trailer 'Plan:" \
    "a rule and text after the trailers|missing trailer 'Assisted-by:|missing trailer 'Plan:" \
    "malformed values|trailer 'Assisted-by: Claude' must be|trailer 'Plan: 8' must be" \
    "a second Plan line|trailer 'Plan: 08,09' must be" \
    "forbidden trailers and a session link|must not carry 'Co-authored-by'|must not carry 'Signed-off-by'|must not carry a Claude Code session link"; do
    IFS='|' read -r input problems <<<"$case"
    (
      case "$input" in
        "no body") body="" ;;
        "a summary only") body="Summary only." ;;
        "text after the trailers")
          body="$GOOD_BODY

Thanks for reviewing."
          ;;
        "a rule and text after the trailers")
          body="$GOOD_BODY

---

Thanks."
          ;;
        "malformed values")
          body="Summary.

Assisted-by: Claude
Plan: 8"
          ;;
        "a second Plan line")
          body="$GOOD_BODY
Plan: 09"
          ;;
        "forbidden trailers and a session link")
          body="$GOOD_BODY
Co-authored-by: Bot <bot@example.com>
Signed-off-by: Bot <bot@example.com>
Claude-Session: https://claude.ai/code/session_0123456789"
          ;;
      esac
      PR_TITLE="feat: x" PR_BODY="$body" run "$CHECK"
      assert_failure 1 || exit 1
      while IFS= read -r line; do
        assert_output --partial "$line" || exit 1
      done <<<"$(tr '|' '\n' <<<"$problems")"
    ) || fail "check-pr did not list every problem of the body: $input"
  done
}
