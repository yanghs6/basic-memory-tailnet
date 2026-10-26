#!/usr/bin/env bash
# Check the git policy for a branch (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md):
# branch name, trailers on every non-merge commit in BASE..BRANCH, forbidden trailers, public text in the commit
# messages (scripts/check-public-text.sh), worktree config.
# Usage: make check-git, or check-git.sh [BASE] [BRANCH]   (defaults: main, the current branch)
# Pass BRANCH to check a branch from anywhere, e.g. from a reviewer's detached worktree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

readonly GIT_CONFIG_KEY_MISSING=1
readonly POLICY_HINT="see AGENTS.md, Git; ask the human before rewriting history"

# trailer COMMIT KEY -> the trailer's values joined by commas; empty when absent.
trailer() {
  git log -1 --format="%(trailers:key=$2,valueonly,separator=%x2C)" "$1"
}

# Spec section 2: Antigravity breaks when the key is present, so any value (1, yes, even false) is flagged.
check_worktree_config() {
  local values status=0
  values="$(git config --get-all extensions.worktreeConfig)" || status=$?
  ((status != GIT_CONFIG_KEY_MISSING)) || return 0
  ((status == 0)) || die "could not read extensions.worktreeConfig (git config exit $status); fix the git config file"
  add_problem "extensions.worktreeConfig is set (value '$(tr '\n' ' ' <<<"$values" | sed 's/ $//')') and breaks Antigravity whatever its value: git config --unset-all extensions.worktreeConfig"
}

# check_branch BASE BRANCH: BRANCH is empty on a detached HEAD.
check_branch() {
  local base="$1" branch="$2"
  if [[ -z "$branch" ]]; then
    add_problem "detached HEAD: create a branch first (git switch -c plan/<id>-slug or work/slug)"
  elif [[ "$branch" == "$base" ]]; then
    add_problem "on $base: agents never commit to $base; move the work with git switch -c work/<slug>"
  elif [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    add_problem "branch '$branch' must look like plan/<id>-slug or work/slug: git branch -m <new-name>"
  fi
}

# check_trailer WHERE COMMIT KEY PATTERN FORMAT [HIDE]: with HIDE set, a malformed value is not printed.
check_trailer() {
  local where="$1" sha="$2" key="$3" pattern="$4" format="$5" hide="${6:-}" value
  value="$(trailer "$sha" "$key")" || exit 1
  if [[ -z "$value" ]]; then
    add_problem "$where: missing trailer '$key: $format' ($POLICY_HINT)"
  elif [[ "$value" =~ $pattern ]]; then
    return 0
  elif [[ -n "$hide" ]]; then
    add_problem "$where: trailer '$key' must be '$key: $format'"
  else
    add_problem "$where: trailer '$key: $value' must be '$key: $format'"
  fi
}

# check_commit COMMIT: the whole message (subject, body, trailers) is checked for public text first. A commit with a
# hit is named by its short SHA only and its trailer values are not printed, so the report publishes none of it.
check_commit() {
  local sha="$1" where message key hide=""
  where="$(git log -1 --format=%h "$sha")" || exit 1
  message="$(git log -1 --format=%B "$sha")" || exit 1
  if add_public_text_problems "$where" "$POLICY_HINT" "$message"; then
    where="$(git log -1 --format='%h "%s"' "$sha")" || exit 1
  else
    hide=1
  fi
  check_trailer "$where" "$sha" Assisted-by "$ASSISTED_BY_PATTERN" "<claude-code|codex|antigravity|gemini-cli> <model>" "$hide"
  check_trailer "$where" "$sha" Plan "$PLAN_PATTERN" "<id|none>" "$hide"
  check_trailer "$where" "$sha" Task "$TASK_PATTERN" "<N|review|none>" "$hide"
  for key in $FORBIDDEN_TRAILERS; do
    if [[ -n "$(trailer "$sha" "$key")" ]]; then
      add_problem "$where: agents never add '$key' ($POLICY_HINT)"
    fi
  done
}

main() {
  local base="${1:-main}" branch="${2:-}" head=HEAD sha count=0
  require_cmd git
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base branch '$base' not found"
  if [[ -n "$branch" ]]; then
    git show-ref --verify --quiet "refs/heads/$branch" || die "branch '$branch' not found"
    head="refs/heads/$branch"
  else
    branch="$(git symbolic-ref --quiet --short HEAD || true)"
  fi
  check_worktree_config
  check_branch "$base" "$branch"
  for sha in $(git rev-list --reverse --no-merges "$base..$head"); do
    check_commit "$sha"
    count=$((count + 1))
  done
  report_problems "git policy violations"
  log "OK: git policy ($count commits since $base)"
}

main "$@"
