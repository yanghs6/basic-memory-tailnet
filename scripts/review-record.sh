#!/usr/bin/env bash
# Create or update the single "Review record" comment of a pull request from a findings file
# (docs/specs/spec-2026-10-13-github-pr-workflow.md, section 8; table format: docs/reviews/README.md).
# Usage: review-record.sh PR FILE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# The first line of the record comment; this script finds the record again by it.
readonly MARKER='<!-- review-record -->'

usage() {
  die "usage: make review-record PR=<number> FILE=<findings file>"
}

main() {
  local pr="${1:-}" file="${2:-}" me body ids count
  [[ "$pr" =~ ^[0-9]+$ && -n "$file" ]] || usage
  [[ -f "$file" ]] || die "findings file '$file' not found"
  require_cmd gh
  # On a public repo anyone can post a comment that starts with the marker; only the machine account's count.
  me="$(gh api user --jq .login)" || die "could not read the gh login; run gh auth status"
  [[ -n "$me" ]] || die "gh returned no login; run gh auth status"
  body="$(mktemp "${TMPDIR:-/tmp}/review-record.XXXXXX")" || exit 1
  # shellcheck disable=SC2064  # expand $body now: it is local to main
  trap "rm -f '$body'" EXIT
  {
    printf '%s\n' "$MARKER"
    cat "$file"
  } >"$body"
  ids="$(gh api "repos/{owner}/{repo}/issues/$pr/comments" --paginate --jq ".[] | select(.user.login == \"$me\" and (.body | startswith(\"$MARKER\"))) | .id")" \
    || die "could not list the comments of PR #$pr"
  count="$(grep -c . <<<"$ids" || true)"
  case "$count" in
    0)
      gh api -X POST "repos/{owner}/{repo}/issues/$pr/comments" -F "body=@$body" >/dev/null \
        || die "could not create the Review record on PR #$pr"
      log "created the Review record on PR #$pr"
      ;;
    1)
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$ids" -F "body=@$body" >/dev/null \
        || die "could not update the Review record comment $ids on PR #$pr"
      log "updated the Review record on PR #$pr (comment $ids)"
      ;;
    *)
      die "PR #$pr has $count Review record comments ($(tr '\n' ' ' <<<"$ids")); delete the extras on GitHub, then rerun"
      ;;
  esac
}

main "$@"
