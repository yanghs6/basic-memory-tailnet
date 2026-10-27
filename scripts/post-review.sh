#!/usr/bin/env bash
# Post one review round's raw reports to its pull request: one comment for the change review and one for the
# plan review (docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, section 8). make review writes the reports and
# the meta file whose base and head SHAs, model, reasoning effort and make check result head both comments.
# Usage: make review-post PR=<number> BRANCH=<plan/<ID>-<slug>|work/slug> REVIEWER=codex|claude [ROUND=1]
#   REVIEW_OUT_DIR=<dir>   where make review wrote the reports (default: the main checkout's .review-out)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

# GitHub rejects comment bodies over 65536 characters; counting bytes keeps every accepted body under it.
readonly MAX_COMMENT_BYTES=65536

usage() {
  die "usage: make review-post PR=<number> BRANCH=<plan/<ID>-<slug>|work/slug> REVIEWER=codex|claude [ROUND=1]"
}

# write_comment FILE HEADER TITLE REPORT: FILE gets HEADER, a "### TITLE" heading and the text of REPORT.
write_comment() {
  printf '%s\n\n### %s\n\n' "$2" "$3" >"$1"
  cat "$4" >>"$1"
}

# check_size FILE WHAT: die when FILE is too long for one GitHub comment.
check_size() {
  local bytes
  bytes="$(wc -c <"$1" | tr -d ' ')" || exit 1
  ((bytes <= MAX_COMMENT_BYTES)) \
    || die "$2 is $bytes bytes, over GitHub's $MAX_COMMENT_BYTES limit for one comment; post a shortened copy with gh pr comment and say so in it"
}

main() {
  local pr branch reviewer round prefix file meta base head model effort check header change_body plan_body
  [[ $# -ge 3 ]] || usage
  pr="$1"
  branch="$2"
  reviewer="$3"
  round="${4:-1}"
  [[ "$pr" =~ ^[0-9]+$ && "$round" =~ ^[0-9]+$ ]] || usage
  case "$reviewer" in
    codex | claude) ;;
    *) usage ;;
  esac
  require_cmd git gh
  prefix="$(review_report_prefix "$branch" "$round" "$reviewer")" || exit 1
  for file in "$prefix-diff.md" "$prefix-plan.md" "$prefix-meta.txt"; do
    [[ -f "$file" ]] || die "missing $file: run make review BRANCH=$branch REVIEWER=$reviewer ROUND=$round first"
  done
  meta="$prefix-meta.txt"
  base="$(sed -n 's/^base //p' "$meta")" || exit 1
  head="$(sed -n 's/^head //p' "$meta")" || exit 1
  [[ -n "$base" && -n "$head" ]] || die "$meta names no base or head; rerun make review"
  model="$(sed -n 's/^model //p' "$meta")" || exit 1
  effort="$(sed -n 's/^effort //p' "$meta")" || exit 1
  check="$(sed -n 's/^check //p' "$meta")" || exit 1
  [[ -n "$model" && -n "$effort" && -n "$check" ]] || die "$meta names no model, effort or check result: rerun make review"
  header="## Agent review R$round: $reviewer ($model, effort $effort)

Base \`$base\`, reviewed head \`$head\`. make check on the reviewed head: $check."
  change_body="$prefix-diff.comment.md"
  plan_body="$prefix-plan.comment.md"
  write_comment "$change_body" "$header" "Change review" "$prefix-diff.md"
  write_comment "$plan_body" "$header" "Plan review" "$prefix-plan.md"
  # Check both before posting either, so a failure never leaves half a round on the pull request.
  check_size "$change_body" "the change review comment"
  check_size "$plan_body" "the plan review comment"
  # The pull request is public: refuse to post an address, ts.net name or session link (the header comes from the meta file).
  add_public_text_problems "the comment header" "check $meta" "$header" || true
  add_public_text_problems "$prefix-diff.md" "fix it in that report" "$(cat "$prefix-diff.md")" || true
  add_public_text_problems "$prefix-plan.md" "fix it in that report" "$(cat "$prefix-plan.md")" || true
  report_problems "posted nothing: the round carries public text; replace the host with agent-hub and a tailnet IP with <agent-hub tailnet IP>, delete session links and Generated with lines, then rerun make review-post PR=$pr BRANCH=$branch REVIEWER=$reviewer ROUND=$round"
  gh pr comment "$pr" --body-file "$change_body" || die "gh pr comment failed for the change review of PR #$pr"
  gh pr comment "$pr" --body-file "$plan_body" || die "gh pr comment failed for the plan review of PR #$pr; the change review is already posted, so post only the plan review: gh pr comment $pr --body-file $plan_body"
  rm -f "$change_body" "$plan_body"
  log "posted the R$round $reviewer change and plan reviews to PR #$pr"
}

main "$@"
