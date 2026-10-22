#!/usr/bin/env bash
# Git, pull request and review helpers for scripts/*.sh: the trailer rules check-git.sh and check-pr.sh share, a
# problem list both report, and where make review writes its reports. Sources common.sh.
# Must stay compatible with macOS bash 3.2.
#   add_problem MESSAGE... -> add one line to PROBLEMS
#   report_problems HEADING -> print PROBLEMS under HEADING and exit 1; nothing when there are none
#   branch_slug BRANCH -> BRANCH with every / replaced by -
#   review_out_dir -> REVIEW_OUT_DIR, else the main checkout's .review-out
#   review_report_prefix BRANCH ROUND REVIEWER -> the path prefix of that review round's report files
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_GIT:-}" ] && return 0
readonly _BM_LIB_GIT=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

readonly ASSISTED_BY_PATTERN='^(claude-code|codex|antigravity|gemini-cli) [^ ]+$'
readonly PLAN_PATTERN='^([0-9]{2}|none)$'
readonly TASK_PATTERN='^([0-9]+|review|none)$'
readonly FORBIDDEN_TRAILERS="Co-authored-by Signed-off-by"

PROBLEMS=""

add_problem() {
  PROBLEMS="${PROBLEMS}  - $*
"
}

# report_problems HEADING -> when add_problem collected anything, print "HEADING:" and the list on stderr and exit 1.
report_problems() {
  [[ -n "$PROBLEMS" ]] || return 0
  printf '%s:\n%s' "$1" "$PROBLEMS" >&2
  exit 1
}

# branch_slug BRANCH -> the branch name as one path component (plan/16-x -> plan-16-x).
branch_slug() {
  printf '%s\n' "${1//\//-}"
}

# review_out_dir -> REVIEW_OUT_DIR when set, else .review-out in the main checkout of the current directory's repo,
# so reports written from any worktree land in one place.
review_out_dir() {
  local root
  if [[ -n "${REVIEW_OUT_DIR:-}" ]]; then
    printf '%s\n' "$REVIEW_OUT_DIR"
    return 0
  fi
  root="$(main_checkout_root "$PWD")" \
    || die "cannot find the main checkout from $PWD: run it inside a checkout of this repo, or set REVIEW_OUT_DIR"
  printf '%s/.review-out\n' "$root"
}

# review_report_prefix BRANCH ROUND REVIEWER -> <review_out_dir>/<branch_slug>-r<ROUND>-<REVIEWER>; the report files
# add -diff.md, -plan.md and -meta.txt.
review_report_prefix() {
  local dir
  dir="$(review_out_dir)" || exit 1
  printf '%s/%s-r%s-%s\n' "$dir" "$(branch_slug "$1")" "$2" "$3"
}
