#!/usr/bin/env bash
# Adds this repo's memory hooks to the user's Claude Code settings and Codex hooks file: memory-sync on SessionStart and
# Stop, memory-index on SessionStart (UserPromptSubmit gets nothing). Both files are read and checked before either is
# written. A hook that matches OWN_COMMAND_PATTERN is ours: it is removed first and added again at the end of its event,
# so running it again gives the same result and a moved checkout replaces the old entry. A changed file is copied to
# <file>.bak-<utc stamp> first (an existing backup is kept) and written through its path, so a symlink stays.
# --remove only takes our hooks out. Edits user settings: ask the user before running it.
# Usage: make memory-hooks [REMOVE=1]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly HOOK_TIMEOUT_SECONDS=10
readonly SYNC_EVENTS="SessionStart Stop"
readonly INDEX_EVENT=SessionStart
readonly OWN_COMMAND_PATTERN='^make -s --no-print-directory -C .+ memory-(sync HOOK=1|index MEMORY_AGENT=(claude-code|codex))$'
readonly CLAUDE_AGENT=claude-code
readonly CODEX_AGENT=codex

# The settings with our hooks removed and, unless $remove is true, added again. Variables: pattern, remove, sync, index,
# events (space separated), index_event, timeout.
HOOKS_JQ=""
read -r -d '' HOOKS_JQ <<'JQ' || true
def own: ((.command // "") | test($pattern));
def strip: map(
  . as $g | ($g.hooks // []) as $all | [$all[] | select(own | not)] as $kept
  | if $kept == $all then $g elif ($kept | length) == 0 then empty else $g | .hooks = $kept end);
def group($cmd): {hooks: [{type: "command", command: $cmd, timeout: $timeout}]};

(if .hooks then .hooks |= map_values(strip) else . end)
| if $remove then .
  else reduce ($events | split(" "))[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [group($sync)]))
    | .hooks[$index_event] = ((.hooks[$index_event] // []) + [group($index)])
  end
JQ

# current_json FILE -> the file's JSON object, {} when it does not exist; dies when it is not a JSON object.
current_json() {
  local file="$1"
  [[ -e "$file" ]] || {
    echo '{}'
    return 0
  }
  jq -e 'if type == "object" then . else error("not an object") end' "$file" 2>/dev/null \
    || die "$file is not valid JSON; fix it, nothing was changed"
}

# new_json CURRENT_JSON AGENT MAIN REMOVE -> CURRENT_JSON with our hooks for AGENT replaced (REMOVE true: removed).
new_json() {
  local current="$1" agent="$2" main="$3" remove="$4" sync_cmd index_cmd
  sync_cmd="make -s --no-print-directory -C '$main' memory-sync HOOK=1"
  index_cmd="make -s --no-print-directory -C '$main' memory-index MEMORY_AGENT=$agent"
  jq --arg pattern "$OWN_COMMAND_PATTERN" --argjson remove "$remove" --arg sync "$sync_cmd" --arg index "$index_cmd" \
    --arg events "$SYNC_EVENTS" --arg index_event "$INDEX_EVENT" --argjson timeout "$HOOK_TIMEOUT_SECONDS" \
    "$HOOKS_JQ" <<<"$current"
}

# same_json A B -> succeeds when both JSON texts are equal, whatever their key order and layout.
same_json() { [[ "$(jq -S . <<<"$1")" == "$(jq -S . <<<"$2")" ]]; }

# write_if_changed FILE CURRENT NEW -> backs up and writes FILE, or says it is up to date.
write_if_changed() {
  local file="$1" current="$2" new="$3" backup
  if same_json "$current" "$new"; then
    log "$file: already up to date"
    return 0
  fi
  if [[ -e "$file" ]]; then
    backup="$file.bak-$(utc_stamp)"
    [[ -e "$backup" ]] || cp "$file" "$backup"
  else
    mkdir -p "$(dirname "$file")"
  fi
  printf '%s\n' "$new" | cat >"$file"
  log "$file: updated (backup $(basename "${backup:-none}"))"
}

main() {
  local remove=false main_root claude_file codex_file claude_current codex_current claude_new codex_new
  case "${1:-}" in
    "") ;;
    --remove) remove=true ;;
    *) die "unknown argument '$1'; usage: make memory-hooks [REMOVE=1]" ;;
  esac
  require_cmd jq
  main_root="$(main_checkout_root)" || exit 1
  [[ "$main_root" != *"'"* ]] || die "the main checkout path contains a single quote; move the checkout"
  claude_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  codex_file="${CODEX_HOME:-$HOME/.codex}/hooks.json"

  claude_current="$(current_json "$claude_file")" || exit 1
  codex_current="$(current_json "$codex_file")" || exit 1
  claude_new="$(new_json "$claude_current" "$CLAUDE_AGENT" "$main_root" "$remove")" || exit 1
  codex_new="$(new_json "$codex_current" "$CODEX_AGENT" "$main_root" "$remove")" || exit 1

  write_if_changed "$claude_file" "$claude_current" "$claude_new"
  write_if_changed "$codex_file" "$codex_current" "$codex_new"
  log "Codex: open /hooks once and trust the new hooks (and check that no other hook lost its trust)"
}

main "$@"
