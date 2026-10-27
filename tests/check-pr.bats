#!/usr/bin/env bats
load helpers

setup() {
  CHECK="$REPO_DIR/scripts/check-pr.sh"
  GOOD_BODY="Summary of the change.

Assisted-by: claude-code claude-opus-5-5
Plan: h8j3m5rx"
}

@test "passes a conventional title and a body ending in the trailers" {
  PR_TITLE="feat: add the pull request rules" PR_BODY="$GOOD_BODY" run "$CHECK"
  assert_success
  assert_output --partial "OK: PR title and trailers"
}

@test "accepts Plan as an id or none, and rejects the two-digit number and ids outside the alphabet or length" {
  local value
  for value in k7m2x9qa none; do
    PR_TITLE="feat: x" PR_BODY="Summary.

Assisted-by: claude-code claude-opus-5-5
Plan: $value" run "$CHECK"
    assert_success
  done
  for value in 26 K7M2X9QA k7m2x9q k7m2x9qai k7m2x9qi; do
    PR_TITLE="feat: x" PR_BODY="Summary.

Assisted-by: claude-code claude-opus-5-5
Plan: $value" run "$CHECK"
    assert_failure 1
    assert_output --partial "trailer 'Plan: $value' must be"
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
    "a second Plan line|trailer 'Plan: h8j3m5rx,n3q8d5vb' must be" \
    "forbidden trailers and a session link|must not carry 'Co-authored-by'|must not carry 'Signed-off-by'|PR body:7: session link"; do
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
Plan: n3q8d5vb"
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

@test "fails on an address in the body or the title, also with CRLF line ends, and echoes neither" {
  local case input problems cgnat title body line
  # A CGNAT (tailnet range) address never sits in a repo file, so build it here. Every kind of hit is tested in
  # tests/check-public-text.bats; these cases show only which text check-pr.sh checks and that it echoes none of it.
  cgnat="$(printf '%s.%s' 100.101 102.103)"
  # Each case: the input's problem | what check-pr.sh must list for it, |-separated. The case block builds the input.
  # In the last case the title and both trailers also break their formats, and those messages must not echo them.
  for case in "an IP in the body|PR body:1: IPv4 address" \
    "an IP in a CRLF body|PR body:1: IPv4 address" \
    "an IP in a malformed title and the trailers|PR title:1: IPv4 address|PR body:3: IPv4 address|the title must be '<type>: <description>'|trailer 'Assisted-by' must be|trailer 'Plan' must be"; do
    IFS='|' read -r input problems <<<"$case"
    (
      title="feat: x"
      case "$input" in
        "an IP in the body")
          body="Reach $cgnat.

$GOOD_BODY"
          ;;
        "an IP in a CRLF body")
          body="$(printf 'Reach %s.\r\n\r\nAssisted-by: claude-code claude-opus-5-5\r\nPlan: none\r\n' "$cgnat")"
          ;;
        "an IP in a malformed title"*)
          title="Reach $cgnat"
          body="Summary.

Assisted-by: $cgnat
Plan: $cgnat"
          ;;
      esac
      PR_TITLE="$title" PR_BODY="$body" run "$CHECK"
      assert_failure 1 || exit 1
      while IFS= read -r line; do
        assert_output --partial "$line" || exit 1
      done <<<"$(tr '|' '\n' <<<"$problems")"
      refute_output --partial "$cgnat" || exit 1
    ) || fail "check-pr did not list the public text without its value: $input"
  done
}
