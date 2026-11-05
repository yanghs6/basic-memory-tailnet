#!/usr/bin/env bash
# Run an independent, read-only agent review of a branch in a throwaway detached worktree
# (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5). Writes two reports:
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-diff.md   bugs introduced since the base
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-plan.md   plan conformance per AGENTS.md Code Review Rules
# Both reports name files relative to the repo: the review worktree path is removed from them.
# Before the review it runs make check on the reviewed head in the review worktree, keeps its output in
# <out>/<branch-slug>-r<ROUND>-<reviewer>-check.log and tells the reviewer the result; a failed check does not stop the review.
# It also writes <out>/<branch-slug>-r<ROUND>-<reviewer>-meta.txt with the base and head SHAs, the model, the
# reasoning effort and the check result that post-review.sh puts in the comment header.
# Usage: make review BRANCH=<plan/<ID>-<slug>|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<reviewed head>]
#   REVIEW_BASE=<ref>            base for the review (default main; the reviewed head for round 2)
#   REVIEW_ALLOW_SAME_VENDOR=1   allow a reviewer from the author's vendor (prints a warning)
#   REVIEW_MODEL=<model>         reviewer model (default DEFAULT_CODEX_MODEL or DEFAULT_CLAUDE_MODEL)
#   REVIEW_EFFORT=<effort>       reasoning effort, one of REVIEW_EFFORTS (default DEFAULT_REVIEW_EFFORT)
# The reviewed branch must not change its own review tools (ADR yyn265p7, decision 1): unless REVIEW_TRUSTED_DIR is set,
# the script unpacks TRUSTED_PATHS of REVIEW_TRUST_REF into a temporary directory, runs that copy of itself with the same
# arguments and REVIEW_TRUSTED_DIR set to the copy, passes on its exit status and removes the copy.
#   REVIEW_TRUST_REF=<ref>       where the review tools come from (default DEFAULT_TRUST_REF; tests only); never REVIEW_BASE
# The claude reviewer takes its agent definition and Bash guard from that copy (--agents), and neither reviewer loads
# the reviewed branch's project settings, the user's config or any MCP server (ADR yyn265p7, decisions 2 and 7).
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
# The codex permission profile that denies the reviewer its credential paths and the main checkout's notes.
readonly CODEX_PROFILE=reviewer
# The trusted source of the review tools and the paths of it that the snapshot holds.
readonly DEFAULT_TRUST_REF=origin/main
readonly TRUST_REF="${REVIEW_TRUST_REF:-$DEFAULT_TRUST_REF}"
readonly TRUSTED_PATHS="scripts Makefile tools .claude/agents/branch-reviewer.md .agents/skills/branch-review"
# The Claude reviewer agent, its definition and Bash guard inside the snapshot, and the only tools its session gets.
readonly REVIEWER_AGENT=branch-reviewer
readonly REVIEWER_DEFINITION=.claude/agents/branch-reviewer.md
readonly REVIEWER_GUARD=scripts/guard-reviewer-bash.sh
readonly REVIEWER_TOOLS=Read,Grep,Glob,Bash
# Only exit 2 from a hook blocks a Claude Code tool call.
readonly HOOK_BLOCK_EXIT=2

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
SNAPSHOT_DIR=""
AGENTS_FILE=""

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
  if [[ -n "$SNAPSHOT_DIR" ]] && ! rm -rf "$SNAPSHOT_DIR"; then
    log "WARNING: could not remove the review tool snapshot; run: rm -rf $SNAPSHOT_DIR"
  fi
  if [[ -n "$AGENTS_FILE" ]] && ! rm -f "$AGENTS_FILE"; then
    log "WARNING: could not remove the reviewer definition file; run: rm -f $AGENTS_FILE"
  fi
  exit "$exit_code"
}

# prepare_trusted_tools: sets SNAPSHOT_DIR to a new temporary directory holding TRUSTED_PATHS of TRUST_REF, removed on
# exit. Dies, before any review worktree exists, when TRUST_REF does not resolve or holds no scripts/review-branch.sh.
prepare_trusted_tools() {
  local fetch_hint="run git fetch origin (or check REVIEW_TRUST_REF) and run make review again"
  local paths=()
  read -r -a paths <<<"$TRUSTED_PATHS"
  git rev-parse --verify --quiet "$TRUST_REF^{commit}" >/dev/null \
    || die "the trusted review tools ref '$TRUST_REF' does not resolve: $fetch_hint"
  SNAPSHOT_DIR="$(new_temp -d review-tools)" || exit 1
  trap cleanup EXIT
  git archive "$TRUST_REF" -- "${paths[@]}" | tar -x -C "$SNAPSHOT_DIR" \
    || die "could not unpack the review tools from '$TRUST_REF': $fetch_hint"
  [[ -x "$SNAPSHOT_DIR/scripts/review-branch.sh" ]] \
    || die "'$TRUST_REF' holds no scripts/review-branch.sh: $fetch_hint"
}

# run_trusted_copy ARG...: runs the snapshot's review-branch.sh with ARG... as a child, so the trap above still removes
# the snapshot, and exits with its status.
run_trusted_copy() {
  local status=0
  prepare_trusted_tools
  step "run the review tools of $TRUST_REF"
  REVIEW_TRUSTED_DIR="$SNAPSHOT_DIR" "$SNAPSHOT_DIR/scripts/review-branch.sh" "$@" || status=$?
  exit "$status"
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

# codex_isolation_args -> the codex arguments, one per line, that keep the reviewer's shell free of token-like
# environment variables and deny it the credential paths and the notes. A permission profile is ignored while --sandbox or
# sandbox_mode is set, so neither is passed; the profile extends :read-only, which also leaves the network off.
# The main checkout's .env, backups/ and .local-data/ (note contents) are absolute paths found at run time, so a
# prompt in the reviewed branch cannot copy notes into a report that make review-post publishes. ~/.config holds the
# cloud CLI and gh credentials; it is denied as a whole because the cloud-neutral rule keeps provider names out of scripts.
codex_isolation_args() {
  local root toml_root deny
  root="$(main_checkout_root "$PWD")" || die "cannot find the main checkout from $PWD"
  [[ "$root" != *[[:cntrl:]]* ]] \
    || die "the main checkout path contains a control character or newline; move the checkout to a plain path"
  # Escape the path for a TOML basic string: backslash first, then the double quote.
  toml_root="${root//\\/\\\\}"
  toml_root="${toml_root//\"/\\\"}"
  deny="{\"$toml_root/.env\"=\"deny\", \"$toml_root/backups\"=\"deny\", \"$toml_root/.local-data\"=\"deny\", \"~/.ssh\"=\"deny\", \"~/.config\"=\"deny\"}"
  printf '%s\n' -c 'shell_environment_policy.inherit="core"' -c 'shell_environment_policy.ignore_default_excludes=false' \
    -c "default_permissions=\"$CODEX_PROFILE\"" -c "permissions.$CODEX_PROFILE.extends=\":read-only\"" \
    -c "permissions.$CODEX_PROFILE.filesystem=$deny"
}

run_codex() {
  local diff_out="$1" plan_out="$2" isolation_lines line
  local isolation=()
  isolation_lines="$(codex_isolation_args)" || exit 1
  while IFS= read -r line; do isolation+=("$line"); done <<<"$isolation_lines"
  # The user's config.toml would add its MCP servers and hooks; apps and plugins would add the account's connectors.
  # Login still comes from CODEX_HOME, and the -c arguments above define the reviewer profile without that file.
  isolation+=(--ignore-user-config --disable apps --disable plugins)
  # codex exec review defaults to a workspace-write sandbox; the profile makes both calls read-only.
  (cd "$WT" && codex exec review -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" "${isolation[@]}" \
    --base "$BASE_BRANCH") >"$diff_out" </dev/null \
    || die "codex change review failed; see $diff_out"
  (cd "$WT" && codex exec -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" "${isolation[@]}" \
    -o "$plan_out" "$(plan_prompt)") >/dev/null </dev/null \
    || die "codex plan review failed"
}

# definition_field FILE KEY -> the value of the "KEY: value" line in the front matter of FILE; empty when there is none.
definition_field() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }' "$1"
}

# required_field FILE KEY -> the value of KEY in the front matter of FILE; dies when it is empty or missing.
required_field() {
  local value
  value="$(definition_field "$1" "$2")" || exit 1
  [[ -n "$value" ]] \
    || die "REVIEW_TRUSTED_DIR: $1 has no '$2: <value>' line in its front matter; fix it on main, git fetch origin and run make review again"
  printf '%s\n' "$value"
}

# definition_body FILE -> the lines of FILE after its front matter, from the first non-blank one.
definition_body() {
  awk '
    NR == 1 && $0 == "---" { front = 1; next }
    front && $0 == "---" { front = 0; body = 1; next }
    body && (started || NF) { started = 1; print }' "$1"
}

# shell_double_quote TEXT -> TEXT escaped for the inside of a double-quoted sh word (\, ", $ and `).
shell_double_quote() {
  local text="${1//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//\$/\\\$}"
  printf '%s\n' "${text//\`/\\\`}"
}

# claude_agents_json -> the path of a new temporary file with the --agents JSON of REVIEWER_AGENT: the description,
# tools, disallowedTools, permissionMode and body of REVIEWER_DEFINITION in REVIEW_TRUSTED_DIR (the snapshot), and a
# Bash hook that runs the snapshot's REVIEWER_GUARD by absolute path, never the reviewed branch's copy. The caller removes
# the file. Dies when REVIEW_TRUSTED_DIR lacks the definition, one of its fields or the guard.
claude_agents_json() {
  local dir definition guard quoted description tools disallowed mode prompt file
  local hint="run make review without REVIEW_TRUSTED_DIR so it unpacks the review tools from $DEFAULT_TRUST_REF"
  dir="$(cd "${REVIEW_TRUSTED_DIR:-}" 2>/dev/null && pwd)" \
    || die "REVIEW_TRUSTED_DIR '${REVIEW_TRUSTED_DIR:-}' is not a directory: $hint"
  definition="$dir/$REVIEWER_DEFINITION"
  guard="$dir/$REVIEWER_GUARD"
  [[ -f "$definition" ]] || die "REVIEW_TRUSTED_DIR '$dir' holds no $REVIEWER_DEFINITION: $hint"
  [[ -x "$guard" ]] || die "REVIEW_TRUSTED_DIR '$dir' holds no executable $REVIEWER_GUARD: $hint"
  [[ "$guard" != *[[:cntrl:]]* ]] \
    || die "REVIEW_TRUSTED_DIR '$dir' contains a control character or newline: set TMPDIR to a plain path and run make review again"
  require_cmd jq
  description="$(required_field "$definition" description)" || exit 1
  tools="$(required_field "$definition" tools)" || exit 1
  disallowed="$(required_field "$definition" disallowedTools)" || exit 1
  mode="$(required_field "$definition" permissionMode)" || exit 1
  prompt="$(definition_body "$definition")" || exit 1
  quoted="$(shell_double_quote "$guard")" || exit 1
  file="$(new_temp review-agents)" || exit 1
  # shellcheck disable=SC2016  # the jq program is single-quoted on purpose
  jq -n --arg name "$REVIEWER_AGENT" --arg description "$description" --arg prompt "$prompt" --arg tools "$tools" \
    --arg disallowed "$disallowed" --arg mode "$mode" --arg hook "\"$quoted\" || exit $HOOK_BLOCK_EXIT" '
    def list: split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0));
    {($name): {description: $description, prompt: $prompt, tools: ($tools | list),
      disallowedTools: ($disallowed | list), permissionMode: $mode,
      hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $hook}]}]}}}' >"$file" || {
    rm -f "$file"
    die "could not write the --agents JSON of $REVIEWER_AGENT from $definition"
  }
  printf '%s\n' "$file"
}

# claude_review PROMPT: one claude review as REVIEWER_AGENT, defined by AGENTS_FILE (claude_agents_json), whose
# Bash guard hook and disallowedTools apply only under --agent; plan mode stays as defence in depth. --restricted keeps
# the file tools inside the review worktree and drops the project's settings and agents, --tools lists the only tools
# and --strict-mcp-config loads no MCP server (combination S2b, plan kkqjgknh Task 1).
# git diff runs diff.external and textconv drivers from config by default, so the reviewer's git sees no
# user or system config. A helper in the repository's own .git/config still runs; that config is the human's.
claude_review() {
  (cd "$WT" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    claude -p --restricted --tools "$REVIEWER_TOOLS" --agents "$AGENTS_FILE" --agent "$REVIEWER_AGENT" \
    --permission-mode plan --strict-mcp-config --no-session-persistence \
    --model "$MODEL" --effort "$EFFORT" "$1") </dev/null
}

run_claude() {
  local diff_out="$1" plan_out="$2"
  claude_review "$(change_prompt)" >"$diff_out" || die "claude change review failed; see $diff_out"
  claude_review "$(plan_prompt)" >"$plan_out" || die "claude plan review failed; see $plan_out"
}

# strip_worktree_prefix REPORT: removes every "$WT/" from REPORT as a literal string (index(), not a regex: the path
# may hold regex characters), so the findings name repo-relative paths instead of the user's home directory.
strip_worktree_prefix() {
  local stripped
  stripped="$(new_temp review-branch)" || exit 1
  # shellcheck disable=SC2016  # the awk program is single-quoted on purpose
  LC_ALL=C REVIEW_WT_PREFIX="$WT/" awk '
    BEGIN { prefix = ENVIRON["REVIEW_WT_PREFIX"]; size = length(prefix) }
    {
      rest = $0
      out = ""
      while ((at = index(rest, prefix)) > 0) {
        out = out substr(rest, 1, at - 1)
        rest = substr(rest, at + size)
      }
      print out rest
    }' "$1" >"$stripped" || {
    rm -f "$stripped"
    die "could not remove the review worktree path from $1"
  }
  mv "$stripped" "$1"
}

main() {
  local round slug wt_path diff_out plan_out base_sha head_sha meta_out check_log out_dir wt_parent prefix
  [[ -n "${REVIEW_TRUSTED_DIR:-}" ]] || run_trusted_copy "$@"
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
  if [[ "$REVIEWER" == claude ]]; then
    AGENTS_FILE="$(claude_agents_json)" || exit 1
  fi
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
  strip_worktree_prefix "$diff_out$PARTIAL_SUFFIX"
  strip_worktree_prefix "$plan_out$PARTIAL_SUFFIX"
  mv "$diff_out$PARTIAL_SUFFIX" "$diff_out"
  mv "$plan_out$PARTIAL_SUFFIX" "$plan_out"
  printf 'base %s\nhead %s\nmodel %s\neffort %s\ncheck %s\n' "$base_sha" "$head_sha" "$MODEL" "$EFFORT" "$CHECK_RESULT" >"$meta_out"
  log "reviews written: $diff_out and $plan_out"
  log "Next: verify each finding (make check output: $check_log), then make review-post PR=<number> BRANCH=$BRANCH REVIEWER=$REVIEWER ROUND=$round and make review-record PR=<number> FILE=<findings file>"
}

main "$@"
