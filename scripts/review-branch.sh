#!/usr/bin/env bash
# Run an independent, read-only agent review of a branch in a throwaway detached worktree
# (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5). Writes two reports:
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-diff.md   bugs introduced since the base
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-plan.md   plan conformance per AGENTS.md Code Review Rules
# Before the review it runs make check on the reviewed head in the review worktree, keeps its output in
# <out>/<branch-slug>-r<ROUND>-<reviewer>-check.log and tells the reviewer the result; a failed check does not stop the review.
# It also writes <out>/<branch-slug>-r<ROUND>-<reviewer>-meta.txt with the base and head SHAs, the model, the
# reasoning effort and the check result that post-review.sh puts in the comment header.
# Usage: make review BRANCH=<plan/<ID>-<slug>|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<reviewed head>]
#   REVIEW_BASE=<ref>            base for the review (default main; the reviewed head for round 2)
#   REVIEW_ALLOW_SAME_VENDOR=1   allow a reviewer from the author's vendor (prints a warning)
#   REVIEW_MODEL=<model>         reviewer model (default DEFAULT_CODEX_MODEL or DEFAULT_CLAUDE_MODEL)
#   REVIEW_EFFORT=<effort>       reasoning effort, one of REVIEW_EFFORTS (default DEFAULT_REVIEW_EFFORT)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

readonly BASE_REF="${REVIEW_BASE:-main}"
readonly DEFAULT_CODEX_MODEL=gpt-6.1-sol
readonly DEFAULT_CLAUDE_MODEL=claude-opus-5-5
readonly DEFAULT_REVIEW_EFFORT=low
# The reasoning efforts both reviewer CLIs accept (codex model_reasoning_effort, claude --effort).
readonly REVIEW_EFFORTS="low medium high xhigh max"
# How many lines from the end of a failed make check's log the reviewer gets.
readonly CHECK_TAIL_LINES=20

BRANCH=""
REVIEWER=""
BASE_BRANCH=""
TEMP_BASE=""
WT=""
SAME_VENDOR_ALLOWED=""
MODEL=""
EFFORT=""
CHECK_RESULT=""
CHECK_SUMMARY=""

usage() {
  die "usage: make review BRANCH=<plan/<ID>-<slug>|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<reviewed head>]"
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

# worktree_parent -> REVIEW_WORKTREE_PARENT, else <main checkout>-wt next to the main checkout of the current repo.
worktree_parent() {
  local root
  if [[ -n "${REVIEW_WORKTREE_PARENT:-}" ]]; then
    printf '%s\n' "$REVIEW_WORKTREE_PARENT"
    return 0
  fi
  root="$(main_checkout_root "$PWD")" \
    || die "cannot find the main checkout from $PWD: run make review inside a checkout of this repo"
  printf '%s/%s-wt\n' "$(dirname "$root")" "$(basename "$root")"
}

# reviewer_tool REVIEWER -> the Assisted-by tool name of that reviewer's vendor.
reviewer_tool() {
  case "$1" in
    codex) echo codex ;;
    claude) echo claude-code ;;
    *) usage ;;
  esac
}

# resolve_model_effort: sets MODEL and EFFORT from REVIEW_MODEL and REVIEW_EFFORT or the reviewer's defaults.
resolve_model_effort() {
  local default_model="$DEFAULT_CLAUDE_MODEL" allowed
  [[ "$REVIEWER" == codex ]] && default_model="$DEFAULT_CODEX_MODEL"
  MODEL="${REVIEW_MODEL:-$default_model}"
  EFFORT="${REVIEW_EFFORT:-$DEFAULT_REVIEW_EFFORT}"
  [[ "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "REVIEW_MODEL '$MODEL' may contain only letters, digits, '.', '_' and '-'; unset it to use $default_model"
  for allowed in $REVIEW_EFFORTS; do
    [[ "$EFFORT" == "$allowed" ]] && return 0
  done
  die "REVIEW_EFFORT must be one of: $REVIEW_EFFORTS (got '$EFFORT'); unset it to use $DEFAULT_REVIEW_EFFORT"
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

# run_check CHECK_LOG: runs make check in the review worktree with its output in CHECK_LOG, sets CHECK_RESULT to
# "passed" or "failed (exit N)" and CHECK_SUMMARY to CHECK_RESULT, followed on failure by the last CHECK_TAIL_LINES
# lines of CHECK_LOG.
run_check() {
  local check_log="$1" status=0
  (cd "$WT" && make check) >"$check_log" 2>&1 </dev/null || status=$?
  if [[ "$status" -eq 0 ]]; then
    CHECK_RESULT=passed
    CHECK_SUMMARY="$CHECK_RESULT"
    return 0
  fi
  log "WARNING: make check failed on the reviewed head (exit $status); the review goes on, see $check_log"
  CHECK_RESULT="failed (exit $status)"
  CHECK_SUMMARY="$CHECK_RESULT
$(tail -n "$CHECK_TAIL_LINES" "$check_log")"
}

# prompt_footer: the make check result, the read-only rule and the report format shared by every review prompt.
prompt_footer() {
  cat <<EOF
make check on the reviewed head: $CHECK_SUMMARY
Read-only: do not modify, create or delete files and do not commit.
Answer with one line "Verdict: mergeable" or "Verdict: blocked (<n> P0/P1)", then one finding per line:
[P0|P1|P2|P3] path:line - failure scenario - suggested fix
Report only problems introduced by these changes.
EOF
  # The reviewer cannot see this script's WARNING, so tell it why it should not stop.
  if [[ -n "$SAME_VENDOR_ALLOWED" ]]; then
    echo "The human set REVIEW_ALLOW_SAME_VENDOR=1: review although your vendor authored commits here, and say so on the line after the verdict."
  fi
}

# change_prompt: the claude change review (bugs introduced since the base). Every git command it names is
# made of plain tokens, so the branch-reviewer Bash guard allows it.
change_prompt() {
  cat <<EOF
Review the changes in git diff $BASE_BRANCH...HEAD on branch $BRANCH (commits: git log $BASE_BRANCH..HEAD).
Follow the branch-review skill (.agents/skills/branch-review/SKILL.md) and its checklist, and look for bugs,
security problems and unmet requirements that these changes introduce. Run git diff, git log and git show
with plain arguments only (for example git diff $BASE_BRANCH...HEAD -- scripts/review-branch.sh).
EOF
  prompt_footer
}

plan_prompt() {
  cat <<EOF
Review branch $BRANCH: the changes since $BASE_BRANCH (git diff $BASE_BRANCH...HEAD, git log $BASE_BRANCH..HEAD).
Find the plan in docs/plans/ named by the commits' Plan trailer (the document id in its file name) and check the changes against the
"Code Review Rules" in AGENTS.md.
EOF
  prompt_footer
}

run_codex() {
  local diff_out="$1" plan_out="$2"
  # codex exec review defaults to a workspace-write sandbox; force read-only for the change review.
  (cd "$WT" && codex exec review -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -c 'sandbox_mode="read-only"' \
    --base "$BASE_BRANCH") >"$diff_out" </dev/null \
    || die "codex change review failed; see $diff_out"
  (cd "$WT" && codex exec -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" --sandbox read-only \
    -o "$plan_out" "$(plan_prompt)") >/dev/null </dev/null \
    || die "codex plan review failed"
}

# claude_review PROMPT: one claude review as the branch-reviewer agent, whose Bash guard hook and
# disallowedTools apply only under --agent; plan mode stays as defence in depth.
# git diff runs diff.external and textconv drivers from config by default, so the reviewer's git sees no
# user or system config. A helper in the repository's own .git/config still runs; that config is the human's.
claude_review() {
  (cd "$WT" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence \
    --model "$MODEL" --effort "$EFFORT" "$1") </dev/null
}

run_claude() {
  local diff_out="$1" plan_out="$2"
  claude_review "$(change_prompt)" >"$diff_out" || die "claude change review failed; see $diff_out"
  claude_review "$(plan_prompt)" >"$plan_out" || die "claude plan review failed; see $plan_out"
}

main() {
  local round slug wt_path diff_out plan_out base_sha head_sha meta_out check_log out_dir wt_parent prefix
  [[ $# -ge 2 ]] || usage
  out_dir="$(review_out_dir)" || exit 1
  # Codex writes its plan report after cd into the review worktree, so a relative path would land there and be deleted.
  [[ "$out_dir" == /* ]] || die "REVIEW_OUT_DIR must be an absolute path (got '$out_dir'); unset it to use the main checkout's .review-out"
  wt_parent="$(worktree_parent)" || exit 1
  BRANCH="$1"
  REVIEWER="$2"
  round="${3:-1}"
  [[ "$round" =~ ^[0-9]+$ ]] || usage
  reviewer_tool "$REVIEWER" >/dev/null
  resolve_model_effort
  require_cmd git "$REVIEWER"
  git show-ref --verify --quiet "refs/heads/$BRANCH" || die "branch '$BRANCH' not found"
  check_independence

  slug="$(branch_slug "$BRANCH")"
  wt_path="$wt_parent/review-$slug-r$round"
  [[ ! -e "$wt_path" ]] \
    || die "a review worktree already exists at $wt_path; if no review is running, remove it: git worktree remove --force $wt_path"
  mkdir -p "$out_dir" "$wt_parent"
  trap cleanup EXIT
  prepare_base "$slug" "$round"

  step "create a read-only review worktree for $BRANCH"
  git worktree add --quiet --detach "$wt_path" "$BRANCH" || die "could not create the review worktree at $wt_path"
  WT="$wt_path"
  base_sha="$(git rev-parse "$BASE_BRANCH")" || exit 1
  head_sha="$(git rev-parse "refs/heads/$BRANCH")" || exit 1

  prefix="$(review_report_prefix "$BRANCH" "$round" "$REVIEWER")" || exit 1
  diff_out="$prefix-diff.md"
  plan_out="$prefix-plan.md"
  meta_out="$prefix-meta.txt"
  check_log="$prefix-check.log"
  # A failed run must not leave an earlier run's report next to a new one: drop both, publish both on success.
  rm -f "$diff_out" "$plan_out" "$meta_out" "$check_log" "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  step "make check on the reviewed head of $BRANCH"
  run_check "$check_log"
  step "$REVIEWER review of $BRANCH against $BASE_BRANCH (round $round)"
  if [[ "$REVIEWER" == codex ]]; then
    run_codex "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  else
    run_claude "$diff_out$PARTIAL_SUFFIX" "$plan_out$PARTIAL_SUFFIX"
  fi
  mv "$diff_out$PARTIAL_SUFFIX" "$diff_out"
  mv "$plan_out$PARTIAL_SUFFIX" "$plan_out"
  printf 'base %s\nhead %s\nmodel %s\neffort %s\ncheck %s\n' "$base_sha" "$head_sha" "$MODEL" "$EFFORT" "$CHECK_RESULT" >"$meta_out"
  log "reviews written: $diff_out and $plan_out"
  log "Next: verify each finding (make check output: $check_log), then make review-post PR=<number> BRANCH=$BRANCH REVIEWER=$REVIEWER ROUND=$round and make review-record PR=<number> FILE=<findings file>"
}

main "$@"
