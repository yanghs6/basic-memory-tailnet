#!/usr/bin/env bash
# Run an independent, read-only agent review of a branch in a throwaway detached worktree
# (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5). Writes two reports:
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-diff.md   bugs introduced since the base
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-plan.md   plan conformance per AGENTS.md Code Review Rules
# Usage: review.sh BRANCH codex|claude [ROUND]
#   REVIEW_BASE=<ref>            base for the review (default main; the reviewed head for round 2)
#   REVIEW_ALLOW_SAME_VENDOR=1   allow a reviewer from the author's vendor (prints a warning)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
readonly OUT_DIR="${REVIEW_OUT_DIR:-$MAIN_ROOT/.review-out}"
readonly WORKTREE_PARENT="${REVIEW_WORKTREE_PARENT:-$(dirname "$MAIN_ROOT")/$(basename "$MAIN_ROOT")-wt}"
readonly BASE_REF="${REVIEW_BASE:-main}"
readonly PARTIAL_SUFFIX=".partial"

BRANCH=""
REVIEWER=""
BASE_BRANCH=""
TEMP_BASE=""
WT=""
SAME_VENDOR_ALLOWED=""

usage() {
  die "usage: make review BRANCH=<plan/NN-slug|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<reviewed head>]"
}

# shellcheck disable=SC2317  # invoked via trap
cleanup() {
  local exit_code=$?
  if [[ -n "$WT" ]] && ! git worktree remove --force "$WT" >/dev/null 2>&1; then
    log "WARNING: could not remove the review worktree; run: git worktree remove --force $WT"
  fi
  if [[ -n "$TEMP_BASE" ]] && ! git branch -D "$TEMP_BASE" >/dev/null 2>&1; then
    log "WARNING: could not delete the temporary branch $TEMP_BASE"
  fi
  exit "$exit_code"
}

# reviewer_tool REVIEWER -> the Assisted-by tool name of that reviewer's vendor.
reviewer_tool() {
  case "$1" in
    codex) echo codex ;;
    claude) echo claude-code ;;
    *) usage ;;
  esac
}

check_independence() {
  local tool author authors same=""
  tool="$(reviewer_tool "$REVIEWER")" || exit 1
  authors="$(git log --no-merges --format='%(trailers:key=Assisted-by,valueonly)' "$BASE_REF..$BRANCH" \
    | awk 'NF { print $1 }' | sort -u | tr '\n' ' ')"
  for author in $authors; do
    if [[ "$author" == "$tool" ]]; then
      same=1
    fi
  done
  [[ -n "$same" ]] || return 0
  if [[ "${REVIEW_ALLOW_SAME_VENDOR:-}" == 1 ]]; then
    log "WARNING: $tool also authored commits on $BRANCH; same-vendor review allowed by REVIEW_ALLOW_SAME_VENDOR=1"
    SAME_VENDOR_ALLOWED=1
    return 0
  fi
  die "reviewer $REVIEWER ($tool) also authored commits on $BRANCH (authors: $authors); use the other reviewer, or set REVIEW_ALLOW_SAME_VENDOR=1 if no other vendor is available"
}

# prepare_base SLUG ROUND: sets BASE_BRANCH; codex needs a branch name, so a SHA gets a temporary branch.
prepare_base() {
  if git show-ref --verify --quiet "refs/heads/$BASE_REF"; then
    BASE_BRANCH="$BASE_REF"
    return 0
  fi
  git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || die "REVIEW_BASE '$BASE_REF' is not a branch or commit"
  local temp="review-base/$1-r$2"
  # Never take over (and later delete) a branch this run did not create: another review may own it.
  if git show-ref --verify --quiet "refs/heads/$temp"; then
    die "the temporary branch $temp already exists: another review of round $2 may be running; if none is, delete it yourself: git branch -D $temp"
  fi
  git branch "$temp" "$BASE_REF" || die "could not create the temporary branch $temp"
  TEMP_BASE="$temp"
  BASE_BRANCH="$TEMP_BASE"
}

plan_prompt() {
  cat <<EOF
Review branch $BRANCH: the changes since $BASE_BRANCH (git diff $BASE_BRANCH...HEAD, git log $BASE_BRANCH..HEAD).
Find the plan in docs/plans/ named by the commits' Plan trailer and check the changes against the
"Code Review Rules" in AGENTS.md. Read-only: do not modify, create or delete files and do not commit.
Answer with one line "Verdict: mergeable" or "Verdict: blocked (<n> P0/P1)", then one finding per line:
[P0|P1|P2|P3] path:line - failure scenario - suggested fix
Report only problems introduced by these changes.
EOF
  # The reviewer cannot see this script's WARNING, so tell it why it should not stop.
  if [[ -n "$SAME_VENDOR_ALLOWED" ]]; then
    echo "The human set REVIEW_ALLOW_SAME_VENDOR=1: review although your vendor authored commits here, and say so on the line after the verdict."
  fi
}

run_codex() {
  local diff_out="$1" plan_out="$2"
  # codex exec review defaults to a workspace-write sandbox; force read-only for the change review.
  (cd "$WT" && codex exec review -c 'sandbox_mode="read-only"' --base "$BASE_BRANCH") >"$diff_out" \
    || die "codex change review failed; see $diff_out"
  (cd "$WT" && codex exec --sandbox read-only -o "$plan_out" "$(plan_prompt)") >/dev/null \
    || die "codex plan review failed"
}

run_claude() {
  local diff_out="$1" plan_out="$2"
  (cd "$WT" && claude -p --permission-mode plan --no-session-persistence "/code-review $BASE_BRANCH...HEAD") \
    >"$diff_out" || die "claude change review failed; see $diff_out"
  (cd "$WT" && claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence "$(plan_prompt)") \
    >"$plan_out" || die "claude plan review failed; see $plan_out"
}

main() {
  local round slug wt_path diff_out plan_out
  [[ $# -ge 2 ]] || usage
  # Codex writes its plan report after cd into the review worktree, so a relative path would land there and be deleted.
  [[ "$OUT_DIR" == /* ]] || die "REVIEW_OUT_DIR must be an absolute path (got '$OUT_DIR'); unset it to use $MAIN_ROOT/.review-out"
  BRANCH="$1"
  REVIEWER="$2"
  round="${3:-1}"
  [[ "$round" =~ ^[0-9]+$ ]] || usage
  reviewer_tool "$REVIEWER" >/dev/null
  require_cmd git "$REVIEWER"
  git show-ref --verify --quiet "refs/heads/$BRANCH" || die "branch '$BRANCH' not found"
  check_independence

  slug="${BRANCH//\//-}"
  wt_path="$WORKTREE_PARENT/review-$slug-r$round"
  [[ ! -e "$wt_path" ]] \
    || die "a review worktree already exists at $wt_path; if no review is running, remove it: git worktree remove --force $wt_path"
  mkdir -p "$OUT_DIR" "$WORKTREE_PARENT"
  trap cleanup EXIT
  prepare_base "$slug" "$round"

  step "create a read-only review worktree for $BRANCH"
  git worktree add --quiet --detach "$wt_path" "$BRANCH" || die "could not create the review worktree at $wt_path"
  WT="$wt_path"

  diff_out="$OUT_DIR/$slug-r$round-$REVIEWER-diff.md"
  plan_out="$OUT_DIR/$slug-r$round-$REVIEWER-plan.md"
  # A failed run must not leave an earlier run's report next to a new one: drop both, publish both on success.
  rm -f "$diff_out" "$plan_out" "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  step "$REVIEWER review of $BRANCH against $BASE_BRANCH (round $round)"
  if [[ "$REVIEWER" == codex ]]; then
    run_codex "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  else
    run_claude "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  fi
  mv "$diff_out$PARTIAL_SUFFIX" "$diff_out"
  mv "$plan_out$PARTIAL_SUFFIX" "$plan_out"
  log "reviews written: $diff_out and $plan_out"
  log "Next: verify each finding, then record them in docs/reviews/$slug.md (format: docs/reviews/README.md)"
}

main "$@"
