#!/usr/bin/env bash
# Mirrors this Mac's Claude Code and Codex memory files to Basic Memory as notes under
# agent-memory/<project key>/<agent>/<device>/: writes new and changed files, deletes the notes of removed, excluded or
# secret-holding files, and records what the server holds in the state folder (memory_state_dir). It never prints file
# content. --hook runs in the background with its output in the state folder's sync.log and always exits 0 (Claude Code
# and Codex hooks); --full writes every file again and deletes this device's mirror notes that no file backs (after a
# restore or a VM rebuild).
# Usage: make memory-sync [HOOK=1] [FULL=1]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mcp.sh
. "$SCRIPT_DIR/lib/mcp.sh"
# shellcheck source=lib/agent-memory.sh
. "$SCRIPT_DIR/lib/agent-memory.sh"

readonly NOTE_ROOT=agent-memory
readonly AGENT_CLAUDE=claude-code
readonly AGENT_CODEX=codex
readonly BM_PROJECT=main
readonly NOTE_TYPE=agent_memory
readonly CLAUDE_MEMORY_FOLDER=memory
readonly CODEX_FOLDER=memories
readonly CODEX_V2_FOLDER=memories_v2
readonly CODEX_V2_PREFIX=v2
readonly CLIENT_NAME=bm-agent-memory
# Claude Code folders of sessions in /private/tmp (scratch work) are not mirrored.
readonly TMP_FOLDER_PREFIX=-private-tmp-
# Codex writes this file only while it consolidates its memory, and it holds deleted text too.
readonly CODEX_WORK_FILE=phase2_workspace_diff.md
readonly LOCK_STALE_MINUTES=10
# Length of the path hash in the key of a third folder of the same repository (<key>--<name>-<hash>).
readonly KEY_HASH_LENGTH=6
readonly SEARCH_PAGE_SIZE=50
# Semantic search is off on the server (compose.yaml), so every search says it wants a text search.
readonly SEARCH_TYPE=text
# Token formats with the gitleaks default lengths (Tailscale, GitHub, AWS, Slack, Anthropic, OpenAI, Google, PEM private
# keys); a file holding one is never sent.
readonly SECRET_PATTERN='tskey-[a-z]+-[A-Za-z0-9]+-[A-Za-z0-9]{10,}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82}|A[KS]IA[A-Z2-7]{16}|xox[bp]-[0-9]+-[A-Za-z0-9-]{10,}|sk-ant-[a-z]+[0-9]{2}-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]+T3BlbkFJ|AIza[A-Za-z0-9_-]{35}|-----BEGIN [A-Z0-9 ]*PRIVATE KEY'
readonly STATE_FILE_NAME=state.tsv
readonly KEYS_FILE_NAME=keys.tsv
# One line: the note path of the first write a run did not send; the next run starts its writes there.
readonly CURSOR_FILE_NAME=next-write.txt
readonly LOG_FILE_NAME=sync.log
readonly LOCK_DIR_NAME=lock
# Pacing for the 1 GB VM, which indexes every note it receives: at most this many write_note calls per run, the rest wait.
readonly WRITE_LIMIT_PER_RUN=5
# Seconds a write_note request may take (other requests keep the MCP library's default). The VM finished writes after up to
# 56 seconds, and a write the client gave up on was sent and indexed again by the next run.
readonly WRITE_TIMEOUT_SECONDS=90
# Pause in seconds between two write_note calls (not before the first one).
readonly WRITE_PAUSE_SECONDS=3
# After this many requests in a row (writes or deletes) that got no answer ("request to <URL> failed") a run sends nothing more.
readonly FAILURES_IN_A_ROW_LIMIT=2

IS_HOOK=""
IS_FULL=""
STATE_DIR=""
STATE_FILE=""
KEYS_FILE=""
CURSOR_FILE=""
NEXT_CURSOR=""
LOCK_DIR=""
# Work files of one run: desired (file, note path, sha256, key, agent, repo), old-state (a copy of state.tsv),
# next-state (the lines of the new state.tsv), write (desired lines plus the old permalink), delete (state lines).
WORK_DIR=""
REQUEST_ID=1
WROTE=0
DELETED=0
FAILED=0
# Lines not sent in this run (DEFERRED), the part of them held back by the write limit (LIMIT_DEFERRED), the failed
# requests in a row that got no answer, the write_note calls made and whether the failure streak stopped the run.
DEFERRED=0
LIMIT_DEFERRED=0
FAILURE_STREAK=0
WRITE_CALLS=0
IS_STOPPED=""

usage() { die "usage: sync-agent-memory.sh [--hook] [--full] (make memory-sync [HOOK=1] [FULL=1])"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --hook) IS_HOOK=1 ;;
      --full) IS_FULL=1 ;;
      *) usage ;;
    esac
    shift
  done
}

# tilde_path PATH -> PATH with the home folder written as ~, for messages and the source_path metadata.
tilde_path() {
  case "$1" in
    "$HOME"/*) printf '%s/%s\n' "~" "${1#"$HOME"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

cleanup() {
  local exit_code=$?
  mcp_close
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
  rm -rf "$LOCK_DIR"
  exit "$exit_code"
}

# acquire_lock -> take the lock folder, after removing one older than LOCK_STALE_MINUTES; exits 0 while another run
# holds it.
acquire_lock() {
  local stale
  stale="$(find "$LOCK_DIR" -maxdepth 0 -mmin +"$LOCK_STALE_MINUTES" 2>/dev/null || true)"
  if [[ -n "$stale" ]]; then
    log "WARNING: removing a memory-sync lock older than $LOCK_STALE_MINUTES minutes"
    rm -rf "$LOCK_DIR"
  fi
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "another memory-sync is running"
    exit 0
  fi
  trap cleanup EXIT
}

# key_taken KEY -> status 0 when keys.tsv already gives KEY to a Claude folder.
key_taken() { awk -F'\t' -v key="$1" '$2 == key { found = 1 } END { exit !found }' "$KEYS_FILE"; }

# new_folder_entry FOLDER -> "<key><tab><repo>" for a Claude folder keys.tsv has no line for: claude_folder_key, made
# unique as spec section 3.2 rule 7 says, and the origin of the cwd of its sessions (empty when there is none). keys.tsv
# keeps both.
new_folder_entry() {
  local folder="$1" name="${1##*/}" key base cwd="" dir repo=""
  key="$(claude_folder_key "$folder")" || exit 1
  if cwd="$(claude_folder_cwd "$folder")"; then
    repo="$(repo_for_dir "$cwd")" || exit 1
  fi
  if key_taken "$key"; then
    base="$key"
    dir="${cwd:-$name}"
    key="$base--$(sanitize_key "${dir##*/}")" || exit 1
    if key_taken "$key"; then
      key="$key-$(printf '%s' "$dir" | sha256_of - | cut -c "1-$KEY_HASH_LENGTH")" || exit 1
    fi
    log "WARNING: project key $base is taken; using $key for $(tilde_path "$folder")"
  fi
  printf '%s\t%s\t%s\n' "$name" "$key" "$repo" >>"$KEYS_FILE"
  printf '%s\t%s\n' "$key" "$repo"
}

# fill_keys_repo NAME REPO -> keys.tsv with REPO as the third column of the two-column line (an older run's) of the
# Claude folder NAME, through a .partial file in the same folder. It runs inside $(...), where errexit is off, so each
# step checks its own status: a cut-short keys.tsv would give folders new keys.
fill_keys_repo() {
  local hint
  hint="check the permissions and free space of $(tilde_path "$STATE_DIR")"
  awk -F'\t' -v OFS='\t' -v name="$1" -v repo="$2" '$1 == name && NF == 2 { $3 = repo } { print }' "$KEYS_FILE" \
    >"$KEYS_FILE$PARTIAL_SUFFIX" || die "cannot write $KEYS_FILE_NAME$PARTIAL_SUFFIX: $hint"
  mv "$KEYS_FILE$PARTIAL_SUFFIX" "$KEYS_FILE" || die "cannot replace $KEYS_FILE_NAME: $hint"
}

# folder_entry FOLDER -> "<key><tab><repo>" that keys.tsv holds for the Claude folder FOLDER (repo empty when none).
# Only a folder without a line, or with a line without the repo column, reads its session files (hundreds of MiB on a
# busy Mac); that column is filled once.
folder_entry() {
  local folder="$1" name line rest key cwd repo=""
  name="${folder##*/}"
  line="$(awk -F'\t' -v name="$name" '$1 == name { print; exit }' "$KEYS_FILE")" || exit 1
  if [[ -z "$line" ]]; then
    new_folder_entry "$folder"
    return 0
  fi
  rest="${line#*$'\t'}"
  key="${rest%%$'\t'*}"
  case "$rest" in
    *$'\t'*) repo="${rest#*$'\t'}" ;;
    *)
      if cwd="$(claude_folder_cwd "$folder")"; then
        repo="$(repo_for_dir "$cwd")" || exit 1
      fi
      fill_keys_repo "$name" "$repo"
      ;;
  esac
  printf '%s\t%s\n' "$key" "$repo"
}

# excluded_key KEY -> status 0 when BM_MEMORY_EXCLUDE lists KEY or the key it was made unique from (<key>--<name>).
excluded_key() { is_excluded "$1" || is_excluded "${1%%--*}"; }

# md_files ROOT AGENT -> the *.md files under ROOT, NUL separated; for Codex without .git/, other hidden files and
# folders, and its work file. -H follows ROOT when it is a symlink (a memory folder kept elsewhere), nothing below it.
md_files() {
  if [[ "$2" == "$AGENT_CODEX" ]]; then
    find -H "$1" \( -name '.*' -o -name "$CODEX_WORK_FILE" \) -prune -o -type f -name '*.md' -print0
  else
    find -H "$1" -type f -name '*.md' -print0
  fi
}

# add_source FILE NOTE KEY AGENT REPO -> the desired line of FILE, unless its path has a tab or a line break or it holds
# a token-like secret (a WARNING then).
add_source() {
  local file="$1" status=0 sha
  # A case statement, because xtrace (kcov) would print the line break of a [[ ]] pattern.
  case "$file" in
    *[$'\t\n']*)
      log "WARNING: $(tilde_path "$file") has a tab or a line break in its path; not mirrored"
      return 0
      ;;
  esac
  grep -q -E -e "$SECRET_PATTERN" -- "$file" || status=$?
  if ((status == 0)); then
    log "WARNING: $(tilde_path "$file") looks like it holds a secret; not mirrored"
    return 0
  fi
  ((status == 1)) || die "cannot read $(tilde_path "$file"): fix its permissions, then run make memory-sync again"
  sha="$(sha256_of "$file")" || exit 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$file" "$2" "$sha" "$3" "$4" "$5" >>"$WORK_DIR/desired"
}

# cannot_list FOLDER -> dies before any request or state change: a file missing from a listing would delete its note.
cannot_list() {
  die "cannot list every file under $(tilde_path "$1"): fix its permissions, then run make memory-sync again; nothing was changed"
}

# add_sources ROOT KEY AGENT REPO PREFIX -> the desired lines of the memory files under ROOT; PREFIX starts their path
# below the device folder. The listing goes to a file first, so a find that fails stops the run.
add_sources() {
  local root="$1" key="$2" agent="$3" repo="$4" prefix="$5" file rel
  md_files "$root" "$agent" >"$WORK_DIR/files" || cannot_list "$root"
  while IFS= read -r -d '' file; do
    rel="${file#"$root"/}"
    add_source "$file" "$NOTE_ROOT/$key/$agent/$BM_MEMORY_DEVICE/$prefix${rel%.md}" "$key" "$agent" "$repo"
  done <"$WORK_DIR/files"
}

# collect_claude -> the desired lines of every Claude Code memory folder, in folder name order, except temporary
# folders and excluded projects.
collect_claude() {
  local projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" folder entry key repo
  [[ -d "$projects" ]] || return 0
  find -H "$projects" -mindepth 1 -maxdepth 1 -type d >"$WORK_DIR/folders.found" || cannot_list "$projects"
  LC_ALL=C sort "$WORK_DIR/folders.found" >"$WORK_DIR/folders"
  while IFS= read -r folder; do
    if [[ "${folder##*/}" == "$TMP_FOLDER_PREFIX"* || ! -d "$folder/$CLAUDE_MEMORY_FOLDER" ]]; then
      continue
    fi
    entry="$(folder_entry "$folder")" || exit 1
    key="${entry%%$'\t'*}"
    repo="${entry#*$'\t'}"
    if excluded_key "$key"; then
      continue
    fi
    add_sources "$folder/$CLAUDE_MEMORY_FOLDER" "$key" "$AGENT_CLAUDE" "$repo" ""
  done <"$WORK_DIR/folders"
}

# collect_codex -> the desired lines of the Codex memory (and memory V2 under v2/), all under the _global key.
collect_codex() {
  local home="${CODEX_HOME:-$HOME/.codex}"
  if excluded_key "$GLOBAL_PROJECT_KEY"; then
    return 0
  fi
  if [[ -d "$home/$CODEX_FOLDER" ]]; then
    add_sources "$home/$CODEX_FOLDER" "$GLOBAL_PROJECT_KEY" "$AGENT_CODEX" "" ""
  fi
  if [[ -d "$home/$CODEX_V2_FOLDER" ]]; then
    add_sources "$home/$CODEX_V2_FOLDER" "$GLOBAL_PROJECT_KEY" "$AGENT_CODEX" "" "$CODEX_V2_PREFIX/"
  fi
}

# plan_changes -> next-state (state lines whose file, note path and sha256 are still desired), write (the other desired
# lines, with the old permalink) and delete (state lines whose file and note path are no longer desired). With --full
# every desired line is written and the deletions come from plan_full_deletes. A state line with an empty sha256 (a
# failed write) never matches a file, so its file is written again.
plan_changes() {
  : >"$WORK_DIR/next-state"
  : >"$WORK_DIR/write"
  : >"$WORK_DIR/delete"
  awk -F'\t' -v OFS='\t' -v full="$IS_FULL" -v dir="$WORK_DIR" '
    FILENAME == ARGV[1] { old[$1 FS $2] = $0; old_sha[$1 FS $2] = $3; old_link[$1 FS $2] = $4; next }
    {
      pair = $1 FS $2
      wanted[pair] = 1
      if (full == "" && (pair in old) && old_sha[pair] != "" && old_sha[pair] == $3) print old[pair] > (dir "/next-state")
      else print $0, old_link[pair] > (dir "/write")
    }
    END { if (full == "") for (pair in old) if (!(pair in wanted)) print old[pair] > (dir "/delete") }
  ' "$WORK_DIR/old-state" "$WORK_DIR/desired"
}

# connect -> an initialized MCP session with the mirror's endpoint; dies when it cannot be reached.
connect() {
  mcp_open
  MCP_URL="$(memory_mcp_url)" || exit 1
  (mcp_initialize "$CLIENT_NAME") || die "basic-memory unreachable (run make tunnel); sync skipped"
}

# list_device_notes -> remote: the file_path and permalink of every mirror note of this device, page by page.
list_device_notes() {
  local page=1 args result
  : >"$WORK_DIR/remote"
  while :; do
    REQUEST_ID=$((REQUEST_ID + 1))
    args="$(jq -cn --arg project "$BM_PROJECT" --arg device "$BM_MEMORY_DEVICE" --argjson page "$page" \
      --argjson size "$SEARCH_PAGE_SIZE" --arg type "$SEARCH_TYPE" \
      '{project: $project, metadata_filters: {device: $device, mirror: true}, search_type: $type, page: $page, page_size: $size,
        output_format: "json"}')" || exit 1
    result="$(mcp_call_tool "$REQUEST_ID" search_notes "$args")" \
      || die "search_notes failed, so FULL=1 cannot tell which notes to delete; run make memory-sync FULL=1 again"
    jq -r '.results[] | [.file_path, .permalink] | @tsv' <<<"$result" >>"$WORK_DIR/remote" \
      || die "search_notes: the result has no results list; run make memory-sync FULL=1 again"
    [[ "$(jq -r '.has_more' <<<"$result")" == true ]] || return 0
    page=$((page + 1))
  done
}

# plan_full_deletes -> delete: a state-like line (no file, no sha256) for each listed note whose file_path is
# agent-memory/<key>/<agent>/<this device>/... and, without .md, no desired note path. The device segment is checked
# here too, so a server that ignored the device filter could not make this delete other Macs' notes. Permalinks are
# lowercased and romanized, so they are never compared.
plan_full_deletes() {
  awk -F'\t' -v OFS='\t' -v root="$NOTE_ROOT" -v device="$BM_MEMORY_DEVICE" '
    FILENAME == ARGV[1] { wanted[$2] = 1; next }
    split($1, part, "/") > 4 && part[1] == root && part[4] == device && $2 != "" {
      path = $1
      sub(/\.md$/, "", path)
      if (!(path in wanted)) print "", path, "", $2
    }
  ' "$WORK_DIR/desired" "$WORK_DIR/remote" >"$WORK_DIR/delete"
}

# unit_fields FILE -> FILE.fields: FILE with each tab turned into the unit separator, which read splits on without
# merging empty fields (it merges runs of tabs). A file, not a process substitution, so a failure stops the run.
unit_fields() { LC_ALL=C tr '\t' '\037' <"$1" >"$1.fields"; }

# delete_one PERMALINK -> deletes the note; fails when the result holds an error. A note that is already gone counts as
# deleted (deleted: false and no error).
delete_one() {
  local args result
  args="$(jq -cn --arg id "$1" --arg project "$BM_PROJECT" '{identifier: $id, project: $project, output_format: "json"}')" \
    || exit 1
  result="$(mcp_call_tool "$REQUEST_ID" delete_note "$args")" || exit 1
  jq -e 'type == "object" and (has("error") | not)' <<<"$result" >/dev/null || die "delete_note: error for $1"
}

# note_failure -> after a failed request: re-emits its stderr (the err file), counts it when no answer came back (the mcp
# library's "request to <URL> failed" message) and resets the streak when the server answered (conflict, tool error).
# The run stops sending once FAILURES_IN_A_ROW_LIMIT unanswered requests came in a row.
note_failure() {
  cat "$WORK_DIR/err" >&2
  if ! grep -qF "request to $MCP_URL failed" "$WORK_DIR/err"; then
    FAILURE_STREAK=0
    return 0
  fi
  FAILURE_STREAK=$((FAILURE_STREAK + 1))
  if ((FAILURE_STREAK >= FAILURES_IN_A_ROW_LIMIT)) && [[ -z "$IS_STOPPED" ]]; then
    IS_STOPPED=1
    log "WARNING: basic-memory did not answer $FAILURES_IN_A_ROW_LIMIT requests in a row; stopped sending, the next memory-sync continues"
  fi
}

# send_deletes -> delete_one for each line of delete; the line of a failed or unsent delete stays in the state.
send_deletes() {
  local source note sha permalink
  unit_fields "$WORK_DIR/delete"
  while IFS=$'\037' read -r source note sha permalink; do
    if [[ -n "$IS_STOPPED" ]]; then
      DEFERRED=$((DEFERRED + 1))
      printf '%s\t%s\t%s\t%s\n' "$source" "$note" "$sha" "$permalink" >>"$WORK_DIR/next-state"
      continue
    fi
    REQUEST_ID=$((REQUEST_ID + 1))
    if (delete_one "$permalink") 2>"$WORK_DIR/err"; then
      DELETED=$((DELETED + 1))
      FAILURE_STREAK=0
    else
      log "WARNING: could not delete $note; the next memory-sync tries again"
      FAILED=$((FAILED + 1))
      printf '%s\t%s\t%s\t%s\n' "$source" "$note" "$sha" "$permalink" >>"$WORK_DIR/next-state"
      note_failure
    fi
  done <"$WORK_DIR/delete.fields"
}

# write_args FILE NOTE KEY AGENT REPO -> the write_note arguments: the file as it is, the note path and the mirror
# metadata (repo only when there is one).
write_args() {
  jq -cn --rawfile content "$1" --arg directory "${2%/*}" --arg title "${2##*/}" --arg project "$BM_PROJECT" \
    --arg note_type "$NOTE_TYPE" --arg key "$3" --arg agent "$4" --arg repo "$5" --arg device "$BM_MEMORY_DEVICE" \
    --arg source_path "$(tilde_path "$1")" \
    '{title: $title, directory: $directory, content: $content, project: $project, note_type: $note_type,
      overwrite: true, output_format: "json",
      metadata: ({project: $key} + (if $repo == "" then {} else {repo: $repo} end)
        + {agent: $agent, device: $device, source_path: $source_path, mirror: true})}'
}

# write_one FILE NOTE KEY AGENT REPO -> the permalink of the note written from FILE; fails unless the result's action is
# created or updated (conflict is a failure too).
write_one() {
  local args result action
  args="$(write_args "$@")" || exit 1
  result="$(MCP_TIMEOUT_SECONDS="$WRITE_TIMEOUT_SECONDS" mcp_call_tool "$REQUEST_ID" write_note "$args")" || exit 1
  action="$(jq -r '.action' <<<"$result")" || exit 1
  [[ "$action" == created || "$action" == updated ]] || die "write_note: action $action for $2"
  jq -r '.permalink // empty' <<<"$result"
}

# keep_unwritten SOURCE NOTE OLD_LINK -> a file whose write failed or was not sent: with an old permalink its line stays
# in the state with an empty sha256 (the note can still be deleted, the next run writes the file again, also after
# --full, where the old sha256 is the current one); without one it is left out, so the next run sees it as new.
keep_unwritten() {
  if [[ -n "$3" ]]; then
    printf '%s\t%s\t\t%s\n' "$1" "$2" "$3" >>"$WORK_DIR/next-state"
  fi
}

# send_writes -> write_one for each line of write, at most WRITE_LIMIT_PER_RUN of them with WRITE_PAUSE_SECONDS between
# two; a written note's line goes to the state with its permalink. Failed and unsent files go through keep_unwritten.
send_writes() {
  local source note sha key agent repo old_link permalink
  unit_fields "$WORK_DIR/write"
  while IFS=$'\037' read -r source note sha key agent repo old_link; do
    if [[ -n "$IS_STOPPED" ]] || ((WRITE_CALLS >= WRITE_LIMIT_PER_RUN)); then
      DEFERRED=$((DEFERRED + 1))
      [[ -n "$IS_STOPPED" ]] || LIMIT_DEFERRED=$((LIMIT_DEFERRED + 1))
      [[ -n "$NEXT_CURSOR" ]] || NEXT_CURSOR="$note"
      keep_unwritten "$source" "$note" "$old_link"
      continue
    fi
    if ((WRITE_CALLS > 0)); then
      sleep "$WRITE_PAUSE_SECONDS"
    fi
    WRITE_CALLS=$((WRITE_CALLS + 1))
    REQUEST_ID=$((REQUEST_ID + 1))
    if permalink="$(write_one "$source" "$note" "$key" "$agent" "$repo" 2>"$WORK_DIR/err")" && [[ -n "$permalink" ]]; then
      WROTE=$((WROTE + 1))
      FAILURE_STREAK=0
      printf '%s\t%s\t%s\t%s\n' "$source" "$note" "$sha" "$permalink" >>"$WORK_DIR/next-state"
    else
      log "WARNING: could not write $note; the next memory-sync tries again"
      FAILED=$((FAILED + 1))
      keep_unwritten "$source" "$note" "$old_link"
      note_failure
    fi
  done <"$WORK_DIR/write.fields"
}

# rotate_writes -> the write list starts at the note the cursor names (lines before it move to the end, the order is
# kept), so notes that fail every run cannot use up the per-run limit before the others get their turn. Without a
# cursor, or when its note is not in the list, the list stays as it is.
rotate_writes() {
  local cursor=""
  [[ -f "$CURSOR_FILE" ]] || return 0
  IFS= read -r cursor <"$CURSOR_FILE" || true
  [[ -n "$cursor" ]] || return 0
  awk -F'\t' -v cursor="$cursor" '
    { line[NR] = $0; if (start == 0 && $2 == cursor) start = NR }
    END {
      if (start == 0) start = 1
      for (i = start; i <= NR; i++) print line[i]
      for (i = 1; i < start; i++) print line[i]
    }
  ' "$WORK_DIR/write" >"$WORK_DIR/write.rotated" || exit 1
  mv "$WORK_DIR/write.rotated" "$WORK_DIR/write"
}

# write_cursor -> the cursor file holds NEXT_CURSOR (through a .partial file, like state.tsv) or is removed when this run
# sent every write.
write_cursor() {
  if [[ -z "$NEXT_CURSOR" ]]; then
    rm -f "$CURSOR_FILE"
    return 0
  fi
  printf '%s\n' "$NEXT_CURSOR" >"$CURSOR_FILE$PARTIAL_SUFFIX"
  mv "$CURSOR_FILE$PARTIAL_SUFFIX" "$CURSOR_FILE"
}

# write_state -> state.tsv replaced by next-state through a .partial file in the same folder.
write_state() {
  cp "$WORK_DIR/next-state" "$STATE_FILE$PARTIAL_SUFFIX"
  mv "$STATE_FILE$PARTIAL_SUFFIX" "$STATE_FILE"
}

# sync_memory -> lock, keys, the desired list, the comparison, the requests and the new state.
sync_memory() {
  require_cmd curl jq git
  require_memory_device
  acquire_lock
  WORK_DIR="$(mktemp -d)" || exit 1
  : >"$WORK_DIR/desired"
  touch "$KEYS_FILE"
  collect_claude
  collect_codex
  if [[ -f "$STATE_FILE" ]]; then
    cp "$STATE_FILE" "$WORK_DIR/old-state"
  else
    : >"$WORK_DIR/old-state"
  fi
  plan_changes
  if [[ -z "$IS_FULL" && ! -s "$WORK_DIR/write" && ! -s "$WORK_DIR/delete" ]]; then
    return 0
  fi
  connect
  if [[ -n "$IS_FULL" ]]; then
    list_device_notes
    plan_full_deletes
  fi
  send_deletes
  rotate_writes
  send_writes
  write_state
  write_cursor
  log "synced: wrote $WROTE, deleted $DELETED, failed $FAILED, deferred $DEFERRED"
  if ((LIMIT_DEFERRED > 0)); then
    log "$LIMIT_DEFERRED notes wait for the next memory-sync (at most $WRITE_LIMIT_PER_RUN writes per run)"
  fi
  ((FAILED == 0)) || die "$FAILED notes failed (see the WARNING lines above); the next memory-sync tries them again"
}

main() {
  parse_args "$@"
  STATE_DIR="$(memory_state_dir)" || exit 1
  STATE_FILE="$STATE_DIR/$STATE_FILE_NAME"
  KEYS_FILE="$STATE_DIR/$KEYS_FILE_NAME"
  CURSOR_FILE="$STATE_DIR/$CURSOR_FILE_NAME"
  LOCK_DIR="$STATE_DIR/$LOCK_DIR_NAME"
  # The hook's log goes to this folder, so it exists before anything runs in the background.
  mkdir -p "$STATE_DIR" || die "cannot create the state folder $(tilde_path "$STATE_DIR"); check its parent's permissions"
  if [[ -n "$IS_HOOK" ]]; then
    (
      trap '' HUP
      sync_memory
    ) >>"$STATE_DIR/$LOG_FILE_NAME" 2>&1 </dev/null &
    exit 0
  fi
  sync_memory
}

main "$@"
