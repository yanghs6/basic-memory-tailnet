#!/usr/bin/env bash
# PreToolUse hook for the Bash tool of the main agent (.claude/settings.json hooks.PreToolUse, spec
# docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md, section 3.3). It reads the command from the hook input and
#   - denies (exit 2, stderr shown to the agent) deleting backups/ or /srv/basic-memory.prev-* directories,
#   - asks the user (permissionDecision "ask") before a force-push, a direct call of a VM-changing or posting script,
#     script or expect around restore, a make call naming a VM-changing or posting target, and every gh or cloud CLI
#     call in command position that is not a read-only form of its allow-list (gh pr view, gh api GET, compute
#     instances list or describe, ...),
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
# The posting scripts behind make review-post and make review-record: their public text check now runs inside the
# sandbox too, so a direct call could reach gh from there.
readonly POST_SCRIPT_PATTERN="${COMMAND_LEAD}([^[:space:];&|()'\"]*/)?(post-review|post-review-record)\\.sh([[:space:];&|)'\"]|\$)"

readonly PTY_WRAPPER_PATTERN="${BOUNDARY_START}(script|expect)${WORD_END}"
readonly RESTORE_PATTERN="${BOUNDARY_START}restore${WORD_END}"

# A call of a command NAME: NAME in command position with an optional directory prefix, followed by the end, a blank,
# a call end, a redirection or a quote; the rest of the command after NAME holds its arguments.
readonly NEWLINE=$'\n'
readonly CALL_PATH_PREFIX="([^[:space:];&|()'\"]*/)?"
readonly NAME_END="^(\$|[[:space:];&|()<>'\"])"
# The words of a call: its arguments up to the first ; & | ( ) or newline outside quotes. A quoted string (with
# backslash escapes inside double quotes) becomes the word QUOTED, so a quoted read verb or group is no plain word.
readonly BEFORE_QUOTE="^(([^'\"\\\\;&|()${NEWLINE}]|\\\\.)*)(['\"])(.*)\$"
readonly SINGLE_QUOTED_REST="^[^']*'(.*)\$"
readonly DOUBLE_QUOTED_REST='^([^"\\]|\\.)*"(.*)$'
readonly CALL_WORDS_END="^([^;&|()${NEWLINE}]*)(.?)"
readonly QUOTED_WORD='QUOTED'
readonly PLAIN_WORD='^[A-Za-z0-9._/:@%+,=-]+$'

# The cloud CLI is written as a bracket expression so that scripts name no provider (tests/repo-cloud-neutral.bats).
# A call passes when its words, without flags, are (group)* read-verb (argument)*, or when it has no words besides
# flags. A group word never names a command, so the first word that is no group decides.
readonly CLOUD_CLI_NAME='[g]cloud'
readonly CLOUD_GROUPS='config configurations compute instances firewall-rules disks addresses networks zones regions operations images projects services iam service-accounts keys auth billing accounts logging logs components alpha beta'
readonly CLOUD_READ_VERBS='list describe info version help get-value get-iam-policy get-serial-port-output read'
# A flag with an optional =value. A value after a blank stays a word: before the verb it is no group, so the call asks
# (a flag must not swallow the word after it, as in compute instances --quiet start list).
readonly CLOUD_FLAG='^-[A-Za-z0-9._/:@%+,=-]*$'

# A make call in command position with a VM-changing or posting target among its arguments (make backup deploy,
# make -C . deploy): the permission rules see only the first target, so `make status deploy` would run unasked.
readonly MAKE_LEAD="${COMMAND_LEAD}([^[:space:];&|()'\"]*/)?make[[:space:]]+([^;&|()]*[[:space:]])?"
readonly MAKE_ASK_TARGETS='(deploy|restore|vm-bootstrap|sb-fonts|review-post|review-record|memory-hooks)'
readonly MAKE_ASK_PATTERN="${MAKE_LEAD}${MAKE_ASK_TARGETS}([[:space:];&|)'\"]|\$)"

# gh read-only forms after the -R and --repo flags (their value must be plain): COMMAND:SUBCOMMAND pairs, commands that
# read whatever follows them, auth status without the token, and api without fields and with GET. Everything else asks.
readonly GH_READ_FORMS='pr:view pr:list pr:diff pr:checks pr:status issue:view issue:list issue:status run:view run:list run:watch workflow:view workflow:list release:view release:list repo:view repo:list gist:view gist:list label:list secret:list variable:list cache:list ruleset:view ruleset:list ruleset:check'
readonly GH_READ_COMMANDS='search status version help'
readonly GH_SHOW_TOKEN='[[:space:]](--show-token([=[:space:]]|$)|-[A-Za-z0-9]*t)'
readonly GH_API_FIELD_PATTERN='[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)|[[:space:]]-[fF][^[:space:]-]'
readonly GH_API_METHOD_PATTERN='[[:space:]](-X|--method)[[:space:]=]*([^[:space:]]+)'

readonly ASK_MAKE_TARGET='this make target changes the VM or posts to a pull request'
readonly ASK_GH='this gh call is not a read-only form'
readonly ASK_FORCE_PUSH='force-push rewrites the remote branch history'
readonly ASK_VM_SCRIPT='this script changes the VM'
readonly ASK_POST_SCRIPT='this script posts to a pull request'
readonly ASK_RESTORE='restore overwrites the notes on the VM'
readonly ASK_CLOUD='this cloud CLI call is not a read-only form'

block() {
  die "blocked by the agent Bash guard: $*. Deleting backups/ or /srv/basic-memory.prev-* directories is never allowed for an agent; ask the user to do it in their own terminal."
}

# ask REASON: print the ask decision for the permission prompt and stop with exit 0.
ask() {
  jq -cn --arg reason "agent Bash guard: $1; confirm with the user" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# word_in WORD LIST: succeed when WORD is one of the blank-separated words of LIST.
word_in() {
  [[ " $2 " == *" $1 "* ]]
}

# each_call NAME CHECK TEXT: run CHECK LEAD ARGS for every call of the command NAME (an ERE) in command position in
# TEXT, where LEAD is the text from the call's separator to NAME and ARGS the rest of TEXT after NAME. It searches
# again in ARGS after each call, so a later or nested call is checked too. Fails as soon as a CHECK fails.
each_call() {
  local pattern="${COMMAND_LEAD}${CALL_PATH_PREFIX}($1)(.*)\$" check="$2" text="$3" last name rest lead
  while [[ "$text" =~ $pattern ]]; do
    last=$((${#BASH_REMATCH[@]} - 1))
    rest="${BASH_REMATCH[last]}"
    name="${BASH_REMATCH[last - 1]}"
    lead="${BASH_REMATCH[0]%"$name$rest"}"
    if [[ "$rest" =~ $NAME_END ]]; then
      "$check" "$lead" "$rest" || return 1
    fi
    text="$rest"
  done
  return 0
}

# call_words ARGS: print the words of the call whose arguments start ARGS, on one line (see BEFORE_QUOTE). An
# unmatched quote, such as the end of sh -c '...', adds the word QUOTED and ends the words; an opening parenthesis
# ($(...) or a subshell) stays a word, so it cannot end the words before the verb unseen.
call_words() {
  local text="$1" words="" rest_pattern
  while [[ "$text" =~ $BEFORE_QUOTE ]]; do
    words+="${BASH_REMATCH[1]}"
    rest_pattern="$DOUBLE_QUOTED_REST"
    [[ "${BASH_REMATCH[3]}" == '"' ]] || rest_pattern="$SINGLE_QUOTED_REST"
    text="${BASH_REMATCH[4]}"
    if ! [[ "$text" =~ $rest_pattern ]]; then
      printf '%s %s' "$words" "$QUOTED_WORD"
      return 0
    fi
    words+="$QUOTED_WORD"
    text="${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}"
  done
  [[ "$words$text" =~ $CALL_WORDS_END ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
  if [[ "${BASH_REMATCH[2]}" == "(" ]]; then
    printf ' ('
  fi
}

# cloud_call_reads LEAD ARGS: succeed when the cloud CLI call is a read-only form (CLOUD_GROUPS, CLOUD_READ_VERBS).
cloud_call_reads() {
  local text word has_group=""
  local -a words=()
  text="$(call_words "$2")" || exit 1
  read -r -a words <<<"$text"
  ((${#words[@]} > 0)) || return 0
  for word in "${words[@]}"; do
    if [[ "$word" =~ $CLOUD_FLAG ]]; then
      continue
    fi
    if word_in "$word" "$CLOUD_READ_VERBS"; then
      return 0
    fi
    word_in "$word" "$CLOUD_GROUPS" || return 1
    has_group=1
  done
  [[ -z "$has_group" ]]
}

# gh_call_reads LEAD ARGS: succeed when the gh call is a read-only form (GH_READ_FORMS and the rules above it).
gh_call_reads() {
  local text word command="" subcommand="" i=0 count
  local -a words=()
  text="$(call_words "$2")" || exit 1
  read -r -a words <<<"$text"
  count=${#words[@]}
  while ((i < count)) && [[ -z "$subcommand" ]]; do
    word="${words[i]}"
    i=$((i + 1))
    if [[ "$word" == -R || "$word" == --repo ]]; then
      ((i < count)) && [[ "${words[i]}" =~ $PLAIN_WORD ]] || return 1
      i=$((i + 1))
    elif [[ "$word" == --repo=* ]]; then
      [[ "${word#--repo=}" =~ $PLAIN_WORD ]] || return 1
    elif [[ -z "$command" ]]; then
      command="$word"
    else
      subcommand="$word"
    fi
  done
  gh_form_reads "$command" "$subcommand" " $text"
}

# gh_form_reads COMMAND SUBCOMMAND WORDS: succeed when gh COMMAND SUBCOMMAND, called with WORDS, only reads.
gh_form_reads() {
  if [[ -z "$1" || "$1" == --version ]] || word_in "$1" "$GH_READ_COMMANDS"; then
    return 0
  fi
  case "$1" in
    api) ! gh_api_writes "$3" ;;
    auth) [[ "$2" == status && ! "$3" =~ $GH_SHOW_TOKEN ]] ;;
    *) word_in "$1:$2" "$GH_READ_FORMS" ;;
  esac
}

# gh_api_writes WORDS: succeed when a gh api call with WORDS sends fields or input, or uses a method other than GET.
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
  if [[ "$command" =~ $POST_SCRIPT_PATTERN ]]; then
    ask "$ASK_POST_SCRIPT"
  fi
  if [[ "$command" =~ $PTY_WRAPPER_PATTERN && "$command" =~ $RESTORE_PATTERN ]]; then
    ask "$ASK_RESTORE"
  fi
  each_call "$CLOUD_CLI_NAME" cloud_call_reads "$command" || ask "$ASK_CLOUD"
  if [[ "$command" =~ $MAKE_ASK_PATTERN ]]; then
    ask "$ASK_MAKE_TARGET"
  fi
  each_call gh gh_call_reads "$command" || ask "$ASK_GH"
}

main "$@"
