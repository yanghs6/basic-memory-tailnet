#!/usr/bin/env bash
# PreToolUse hook for the read-only branch-reviewer agent (.claude/agents/branch-reviewer.md): Bash may run only
# git diff, git log or git show with plain arguments (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5).
# Contract (code.claude.com/docs/en/hooks): the hook input JSON arrives on stdin and the command is
# .tool_input.command; exit 0 allows the call, exit 2 blocks it and shows stderr to the agent.
# Any other exit code does NOT block, so every failure below is turned into exit 2 (fail closed).
# Usage: the branch-reviewer agent's PreToolUse hook (hook input JSON on stdin)
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

# Byte-wise character classes: no locale may widen [A-Za-z] beyond ASCII.
export LC_ALL=C
# The shell sees the whole command, so only plain tokens are allowed: anything the shell would interpret
# (quotes, backslashes, $, globs, operators, any whitespace other than single spaces) cannot match.
readonly ALLOWED_PATTERN='^git (diff|log|show)( [A-Za-z0-9._/:@^~=+,-]+)*$'
# --output writes a file; git also accepts unambiguous abbreviations of long options (--outp=, --ou=).
readonly WRITE_OPTION_PATTERN='(^| )--ou'
# --ext-diff and --textconv run helper programs from git config; block every abbreviation (--ext, --textc)
# while --text (treat files as text) stays allowed. review-branch.sh also hides user and system git config.
readonly HELPER_OPTION_PATTERN='(^| )--(ext|textc)'

block() {
  die "blocked by the review Bash guard: $*. A reviewer may run only git diff, git log or git show followed by single-space-separated plain tokens (letters, digits and . _ / : @ ^ ~ = + , -), never --output, --ext-diff or --textconv."
}

main() {
  local input command
  require_cmd jq
  input="$(cat)"
  [[ -n "$input" ]] || block "empty hook input"
  command="$(jq -er '.tool_input.command | strings' <<<"$input" 2>/dev/null)" \
    || block "hook input is not JSON with a string .tool_input.command"
  [[ "$command" =~ $ALLOWED_PATTERN ]] || block "not a plain git diff, git log or git show command"
  if [[ "$command" =~ $WRITE_OPTION_PATTERN ]]; then
    block "--output (or an abbreviation of it) writes a file"
  fi
  if [[ "$command" =~ $HELPER_OPTION_PATTERN ]]; then
    block "--ext-diff and --textconv (or abbreviations of them) run external helper programs"
  fi
}

main "$@"
