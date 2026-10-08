#!/usr/bin/env bash
# Check the git policy for the current branch (docs/specs/2026-10-07-git-review-policy-design.md):
# branch name, trailers on every non-merge commit in BASE..HEAD, forbidden trailers, worktree config.
# Usage: check-git.sh [BASE]   (default: main)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly BRANCH_PATTERN='^(plan/[0-9]{2}-[a-z0-9-]+|work/[a-z0-9-]+)$'
readonly ASSISTED_BY_PATTERN='^(claude-code|codex|antigravity|gemini-cli) [^ ]+$'
readonly PLAN_PATTERN='^([0-9]{2}|none)$'
readonly TASK_PATTERN='^([0-9]+|review|none)$'
readonly FORBIDDEN_TRAILERS="Co-authored-by Signed-off-by"
readonly POLICY_HINT="see AGENTS.md, Git; ask the human before rewriting history"

PROBLEMS=""

add_problem() {
  PROBLEMS="${PROBLEMS}  - $*
"
}

# trailer COMMIT KEY -> the trailer's values joined by commas; empty when absent.
trailer() {
  git log -1 --format="%(trailers:key=$2,valueonly,separator=%x2C)" "$1"
}

check_worktree_config() {
  if [[ "$(git config --get extensions.worktreeConfig || true)" == true ]]; then
    add_problem "extensions.worktreeConfig is enabled and breaks Antigravity: git config --unset extensions.worktreeConfig"
  fi
}

check_branch() {
  local base="$1" branch
  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  if [[ -z "$branch" ]]; then
    add_problem "detached HEAD: create a branch first (git switch -c plan/NN-slug or work/slug)"
  elif [[ "$branch" == "$base" ]]; then
    add_problem "on $base: agents never commit to $base; move the work with git switch -c work/<slug>"
  elif [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    add_problem "branch '$branch' must look like plan/NN-slug or work/slug: git branch -m <new-name>"
  fi
}

# check_trailer WHERE COMMIT KEY PATTERN FORMAT
check_trailer() {
  local where="$1" sha="$2" key="$3" pattern="$4" format="$5" value
  value="$(trailer "$sha" "$key")"
  if [[ -z "$value" ]]; then
    add_problem "$where: missing trailer '$key: $format' ($POLICY_HINT)"
  elif [[ ! "$value" =~ $pattern ]]; then
    add_problem "$where: trailer '$key: $value' must be '$key: $format'"
  fi
}

check_commit() {
  local sha="$1" where key
  where="$(git log -1 --format='%h "%s"' "$sha")"
  check_trailer "$where" "$sha" Assisted-by "$ASSISTED_BY_PATTERN" "<claude-code|codex|antigravity|gemini-cli> <model>"
  check_trailer "$where" "$sha" Plan "$PLAN_PATTERN" "<NN|none>"
  check_trailer "$where" "$sha" Task "$TASK_PATTERN" "<N|review|none>"
  for key in $FORBIDDEN_TRAILERS; do
    if [[ -n "$(trailer "$sha" "$key")" ]]; then
      add_problem "$where: agents never add '$key' ($POLICY_HINT)"
    fi
  done
}

main() {
  local base="${1:-main}" sha count=0
  require_cmd git
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base branch '$base' not found"
  check_worktree_config
  check_branch "$base"
  for sha in $(git rev-list --reverse --no-merges "$base..HEAD"); do
    check_commit "$sha"
    count=$((count + 1))
  done
  if [[ -n "$PROBLEMS" ]]; then
    printf 'git policy violations:\n%s' "$PROBLEMS" >&2
    exit 1
  fi
  log "OK: git policy ($count commits since $base)"
}

main "$@"
