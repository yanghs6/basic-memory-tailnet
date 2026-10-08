#!/usr/bin/env bash
# PreToolUse hook for the read-only branch-reviewer agent (.claude/agents/branch-reviewer.md): Bash may run only
# git diff, git log or git show with plain arguments (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5).
# Contract (code.claude.com/docs/en/hooks): the hook input JSON arrives on stdin and the command is
# .tool_input.command; exit 0 allows the call, exit 2 blocks it and shows stderr to the agent.
# Any other exit code does NOT block, so every failure below is turned into exit 2 (fail closed).
set -euo pipefail

readonly BLOCK_EXIT=2

# shellcheck disable=SC2317  # invoked via trap
fail_closed() {
  local exit_code=$?
  ((exit_code == 0)) || exit "$BLOCK_EXIT"
}
trap fail_closed EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly ALLOWED_PATTERN='^git (diff|log|show)( |$)'
readonly NEWLINE=$'\n'
readonly CARRIAGE_RETURN=$'\r'

block() {
  die "blocked by the review Bash guard: $*. A reviewer may run only git diff, git log or git show with plain arguments (no ; & | \` \$ < > or line breaks, no --output)."
}

main() {
  local input command
  require_cmd jq
  input="$(cat)"
  [[ -n "$input" ]] || block "empty hook input"
  command="$(jq -er '.tool_input.command | strings' <<<"$input" 2>/dev/null)" \
    || block "hook input is not JSON with a string .tool_input.command"
  case "$command" in
    *';'* | *'&'* | *'|'* | *'`'* | *'$'* | *'<'* | *'>'* | *"$NEWLINE"* | *"$CARRIAGE_RETURN"*)
      block "shell operators are not allowed"
      ;;
    *--output*) block "--output writes a file" ;;
  esac
  [[ "$command" =~ $ALLOWED_PATTERN ]] || block "'${command%% *}' is not git diff, git log or git show"
}

main "$@"
