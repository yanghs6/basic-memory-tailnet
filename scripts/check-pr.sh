#!/usr/bin/env bash
# Check a pull request's title and body (docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, sections 5 and 6).
# The squash merge makes the title the commit subject and the body the commit message, so the title follows
# the commit format, the body's last paragraph carries the Assisted-by and Plan trailers, and neither carries public
# text (scripts/check-public-text.sh).
# Usage: PR_TITLE=<title> PR_BODY=<body> check-pr.sh   (the pr-rules workflow passes both from the event)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

readonly TITLE_PATTERN='^(feat|fix|refactor|docs|test|chore|perf|ci): [^ ]'
readonly TITLE_FORMAT="'<type>: <description>' with type feat, fix, refactor, docs, test, chore, perf or ci"
readonly ASSISTED_BY_FORMAT="'Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>'"
readonly PUBLIC_TEXT_HINT="the squash commit would publish it: mask it as scripts/check-public-text.sh suggests, then edit the pull request"

# check_assisted_by TRAILERS [HIDE]: with HIDE set, a malformed value is not printed.
check_assisted_by() {
  local hide="${2:-}" value count=0
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    count=$((count + 1))
    if [[ "$value" =~ $ASSISTED_BY_PATTERN ]]; then
      continue
    elif [[ -n "$hide" ]]; then
      add_problem "trailer 'Assisted-by' must be $ASSISTED_BY_FORMAT"
    else
      add_problem "trailer 'Assisted-by: $value' must be $ASSISTED_BY_FORMAT"
    fi
  done <<<"$(trailer_values Assisted-by "$1")"
  ((count > 0)) || add_problem "missing trailer 'Assisted-by: <tool> <model>' in the last paragraph of the PR body"
}

# check_plan TRAILERS [HIDE]: with HIDE set, a malformed value is not printed.
check_plan() {
  local hide="${2:-}" value
  value="$(trailer_values Plan "$1" | tr '\n' ',' | sed 's/,$//')" || exit 1
  if [[ -z "$value" ]]; then
    add_problem "missing trailer 'Plan: <id|none>' in the last paragraph of the PR body"
  elif [[ "$value" =~ $PLAN_PATTERN ]]; then
    return 0
  elif [[ -n "$hide" ]]; then
    add_problem "trailer 'Plan' must be 'Plan: <id|none>'"
  else
    add_problem "trailer 'Plan: $value' must be 'Plan: <id|none>'"
  fi
}

# check_title TITLE [HIDE]: with HIDE set, a malformed title is not printed.
check_title() {
  if [[ "$1" =~ $TITLE_PATTERN ]]; then
    return 0
  elif [[ -n "${2:-}" ]]; then
    add_problem "the title must be $TITLE_FORMAT"
  else
    add_problem "title '$1' must be $TITLE_FORMAT"
  fi
}

main() {
  local title="${PR_TITLE:-}" trailers key hide=""
  require_cmd git
  [[ -n "$title" ]] || die "PR_TITLE is empty: pass the pull request title and body in PR_TITLE and PR_BODY"
  trailers="$(pr_trailers "$title" "${PR_BODY:-}")" || exit 1
  # A hit in either text keeps the title and the trailer values out of every other message.
  add_public_text_problems "PR title" "$PUBLIC_TEXT_HINT" "$title" || hide=1
  add_public_text_problems "PR body" "$PUBLIC_TEXT_HINT" "${PR_BODY:-}" || hide=1
  check_title "$title" "$hide"
  check_assisted_by "$trailers" "$hide"
  check_plan "$trailers" "$hide"
  for key in $FORBIDDEN_TRAILERS; do
    [[ -z "$(trailer_values "$key" "$trailers")" ]] \
      || add_problem "the PR body must not carry '$key': the squash commit would carry it"
  done
  report_problems "PR rule violations"
  log "OK: PR title and trailers"
}

main "$@"
