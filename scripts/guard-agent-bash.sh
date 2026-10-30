#!/usr/bin/env bash
# PreToolUse hook for the Bash tool of the main agent (.claude/settings.json hooks.PreToolUse, spec
# docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md, section 3.3). It reads the command from the hook input and
#   - denies (exit 2, stderr shown to the agent) deleting backups/ or /srv/basic-memory.prev-* directories,
#   - asks the user (permissionDecision "ask") before a force-push, a direct call of a VM-changing script,
#     script or expect around restore, a make call naming a VM-changing or posting target, gh write forms (api with
#     fields or a non-GET method, gist, issue, release, repo, pr close or merge) and cloud CLI changes (create, delete,
#     metadata, update, stop, reset, resize),
#   - passes everything else (exit 0, no output) on to the normal permission rules.
# Contract (code.claude.com/docs/en/hooks): hook input JSON on stdin, the command is .tool_input.command; exit 2 blocks.
# Any other failing exit code does NOT block, so every failure below is turned into exit 2 (fail closed).
# The patterns match the text of the command, so they also catch sh -c, env and git -C wrappers; a command hidden
# by variable substitution or encoding is not caught (see the ADR for the sandbox).
# Accepted false positives, on the safe side: rm together with backups anywhere in the command denies, and a +word
# token after push asks.
# Usage: the Bash PreToolUse hook in .claude/settings.json (hook input JSON on stdin)
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

# A word boundary: start of the command or any character that cannot be part of a command or option name.
readonly BOUNDARY_START='(^|[^A-Za-z0-9_.-])'
readonly WORD_END='($|[^A-Za-z0-9_-])'

readonly RM_PATTERN="${BOUNDARY_START}rm${WORD_END}"
readonly PROTECTED_PATTERN='backups|basic-memory\.prev'

readonly PUSH_PATTERN="${BOUNDARY_START}push${WORD_END}"
# --force and --force-with-lease, a standalone -f, or a refspec token that starts with +.
readonly FORCE_PATTERN="(^|[[:space:]'\"])(--force|-[A-Za-z]*f[A-Za-z]*${WORD_END}|\\+[A-Za-z0-9._/])"

# Only a direct call: the script name in command position (start, after ; & | ( or a newline, or after sh, bash
# or env, also inside sh -c '...'), with an optional directory prefix. cat, git add or shellcheck on it pass.
readonly COMMAND_LEAD=$'(^|[;&|(\n]|(^|[[:space:];&|(])(sh|bash|env)[[:space:]]+(-c[[:space:]]+)?)[[:space:]\'"]*'
readonly VM_SCRIPT_PATTERN="${COMMAND_LEAD}([^[:space:];&|()'\"]*/)?(restore-notes|deploy-stack|bootstrap-vm|upload-sb-fonts)\\.sh([[:space:];&|)'\"]|\$)"

readonly PTY_WRAPPER_PATTERN="${BOUNDARY_START}(script|expect)${WORD_END}"
readonly RESTORE_PATTERN="${BOUNDARY_START}restore${WORD_END}"

# The cloud CLI is written as a bracket expression so that scripts name no provider (tests/repo-cloud-neutral.bats).
readonly CLOUD_CLI_PATTERN="${BOUNDARY_START}[g]cloud${WORD_END}"
readonly CLOUD_CHANGE_PATTERN='[[:space:]](create|delete|add-metadata|remove-metadata|update|stop|reset|resize|set-machine-type)([[:space:]]|$)'

# A make call in command position with a VM-changing or posting target among its arguments (make backup deploy,
# make -C . deploy): the permission rules see only the first target, so `make status deploy` would run unasked.
readonly MAKE_LEAD="${COMMAND_LEAD}([^[:space:];&|()'\"]*/)?make[[:space:]]+([^;&|()]*[[:space:]])?"
readonly MAKE_ASK_TARGETS='(deploy|restore|vm-bootstrap|sb-fonts|review-post|review-record|memory-hooks)'
readonly MAKE_ASK_PATTERN="${MAKE_LEAD}${MAKE_ASK_TARGETS}([[:space:];&|)'\"]|\$)"

# gh in command position. Write forms ask; read forms (pr view, issue list, api GET) pass.
# Global flags (-R a/b, --repo a/b, --repo=a/b, or a bare flag) may stand between gh and the subcommand.
readonly GH_GLOBAL_FLAGS='(-[A-Za-z-]+(=[^[:space:]]+|[[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*'
readonly GH_LEAD="${COMMAND_LEAD}gh[[:space:]]+${GH_GLOBAL_FLAGS}"
readonly GH_API_PATTERN="${GH_LEAD}api([[:space:]]|\$)"
readonly GH_API_FIELD_PATTERN='[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)|[[:space:]]-[fF][^[:space:]-]'
readonly GH_API_METHOD_PATTERN='[[:space:]](-X|--method)[[:space:]=]*([^[:space:]]+)'
readonly GH_WRITE_PATTERN="${GH_LEAD}((gist[[:space:]]+(create|edit|delete))|(issue[[:space:]]+(create|comment|edit|close|delete|reopen|transfer|lock))|(release[[:space:]]+(create|upload|edit|delete))|(repo[[:space:]]+(create|edit|delete|rename|archive|fork|sync))|(pr[[:space:]]+(close|merge|review|reopen)))([[:space:]]|\$)"

readonly ASK_MAKE_TARGET='this make target changes the VM or posts to a pull request'
readonly ASK_GH_WRITE='this gh call writes to GitHub from outside the sandbox'
readonly ASK_FORCE_PUSH='force-push rewrites the remote branch history'
readonly ASK_VM_SCRIPT='this script changes the VM'
readonly ASK_RESTORE='restore overwrites the notes on the VM'
readonly ASK_CLOUD='cloud CLI create or delete changes cloud resources'

block() {
  die "blocked by the agent Bash guard: $*. Deleting backups/ or /srv/basic-memory.prev-* directories is never allowed for an agent; ask the user to do it in their own terminal."
}

# ask REASON: print the ask decision for the permission prompt and stop with exit 0.
ask() {
  jq -cn --arg reason "agent Bash guard: $1; confirm with the user" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# gh_api_writes COMMAND: succeed when a gh api call sends fields or input, or uses a method other than GET.
gh_api_writes() {
  local method
  if [[ "$1" =~ $GH_API_FIELD_PATTERN ]]; then
    return 0
  fi
  if [[ "$1" =~ $GH_API_METHOD_PATTERN ]]; then
    method="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    [[ "$method" == get ]] || return 0
  fi
  return 1
}

main() {
  local input command
  require_cmd jq
  input="$(cat)"
  [[ -n "$input" ]] || block "empty hook input"
  command="$(jq -er '.tool_input.command | strings | select(length > 0)' <<<"$input" 2>/dev/null)" \
    || block "hook input is not JSON with a non-empty string .tool_input.command"

  if [[ "$command" =~ $RM_PATTERN && "$command" =~ $PROTECTED_PATTERN ]]; then
    block "rm together with backups or basic-memory.prev"
  fi
  if [[ "$command" =~ $PUSH_PATTERN && "$command" =~ $FORCE_PATTERN ]]; then
    ask "$ASK_FORCE_PUSH"
  fi
  if [[ "$command" =~ $VM_SCRIPT_PATTERN ]]; then
    ask "$ASK_VM_SCRIPT"
  fi
  if [[ "$command" =~ $PTY_WRAPPER_PATTERN && "$command" =~ $RESTORE_PATTERN ]]; then
    ask "$ASK_RESTORE"
  fi
  if [[ "$command" =~ $CLOUD_CLI_PATTERN && "$command" =~ $CLOUD_CHANGE_PATTERN ]]; then
    ask "$ASK_CLOUD"
  fi
  if [[ "$command" =~ $MAKE_ASK_PATTERN ]]; then
    ask "$ASK_MAKE_TARGET"
  fi
  if [[ "$command" =~ $GH_WRITE_PATTERN ]]; then
    ask "$ASK_GH_WRITE"
  fi
  if [[ "$command" =~ $GH_API_PATTERN ]] && gh_api_writes "$command"; then
    ask "$ASK_GH_WRITE"
  fi
}

main "$@"
