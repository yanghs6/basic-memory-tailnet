#!/usr/bin/env bash
# Check a pull request's title and body (docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, sections 5 and 6).
# The squash merge makes the title the commit subject and the body the commit message, so the title follows
# the commit format and the body's last paragraph carries the Assisted-by and Plan trailers.
# Usage: PR_TITLE=<title> PR_BODY=<body> check-pr.sh   (the pr-rules workflow passes both from the event)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly TITLE_PATTERN='^(feat|fix|refactor|docs|test|chore|perf|ci): [^ ]'
readonly ASSISTED_BY_PATTERN='^(claude-code|codex|antigravity|gemini-cli) [^ ]+$'
readonly PLAN_PATTERN='^([0-9]{2}|none)$'
readonly FORBIDDEN_TRAILERS="Co-authored-by Signed-off-by"
readonly SESSION_LINK_PATTERN='claude.ai/code/session'

PROBLEMS=""

add_problem() {
  PROBLEMS="${PROBLEMS}  - $*
"
}

# trailer_values KEY TRAILERS -> the values of KEY (matched case-insensitively, like git), one per line.
trailer_values() {
  awk -v key="$1" 'BEGIN { key = tolower(key) }
    { i = index($0, ":"); if (i && tolower(substr($0, 1, i - 1)) == key) { v = substr($0, i + 1); sub(/^ +/, "", v); print v } }' <<<"$2"
}

check_assisted_by() {
  local value count=0
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    count=$((count + 1))
    [[ "$value" =~ $ASSISTED_BY_PATTERN ]] \
      || add_problem "trailer 'Assisted-by: $value' must be 'Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>'"
  done <<<"$(trailer_values Assisted-by "$1")"
  ((count > 0)) || add_problem "missing trailer 'Assisted-by: <tool> <model>' in the last paragraph of the PR body"
}

check_plan() {
  local value
  value="$(trailer_values Plan "$1" | tr '\n' ',' | sed 's/,$//')"
  if [[ -z "$value" ]]; then
    add_problem "missing trailer 'Plan: <NN|none>' in the last paragraph of the PR body"
  elif [[ ! "$value" =~ $PLAN_PATTERN ]]; then
    add_problem "trailer 'Plan: $value' must be 'Plan: <NN|none>'"
  fi
}

main() {
  local title="${PR_TITLE:-}" trailers key
  require_cmd git
  [[ -n "$title" ]] || die "PR_TITLE is empty: pass the pull request title and body in PR_TITLE and PR_BODY"
  # The squash commit is the PR title, a blank line and the body, and git log reads its trailers without the
  # '---' divider rule, so parse the same text the same way. GitHub sends bodies with CRLF line ends, which
  # git interpret-trailers does not parse.
  trailers="$(printf '%s\n\n%s\n' "$title" "${PR_BODY:-}" | tr -d '\r' | git interpret-trailers --parse --no-divider)" \
    || die "git interpret-trailers could not parse the PR body"
  [[ "$title" =~ $TITLE_PATTERN ]] \
    || add_problem "title '$title' must be '<type>: <description>' with type feat, fix, refactor, docs, test, chore, perf or ci"
  check_assisted_by "$trailers"
  check_plan "$trailers"
  for key in $FORBIDDEN_TRAILERS; do
    [[ -z "$(trailer_values "$key" "$trailers")" ]] \
      || add_problem "the PR body must not carry '$key': the squash commit would carry it"
  done
  [[ "${PR_BODY:-}" != *"$SESSION_LINK_PATTERN"* ]] \
    || add_problem "the PR body must not carry a Claude Code session link: the squash commit would publish it"
  if [[ -n "$PROBLEMS" ]]; then
    printf 'PR rule violations:\n%s' "$PROBLEMS" >&2
    exit 1
  fi
  log "OK: PR title and trailers"
}

main "$@"
