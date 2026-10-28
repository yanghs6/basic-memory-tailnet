#!/usr/bin/env bash
# Project, device and state rules of the agent memory mirror, shared by the memory sync and index scripts. Sources
# common.sh. Must stay compatible with macOS bash 3.2.
#   normalize_remote URL -> host/path: lowercase host, no scheme, user, port, trailing .git or /
#   repo_for_dir DIR -> the normalized origin of the repository DIR belongs to, or an empty line
#   sanitize_key TEXT -> lowercase, every character outside [a-z0-9_-] turned into -
#   project_key_for_dir DIR -> _global for $HOME, owner-repo from the origin, else local-<DIR name>
#   claude_folder_name DIR -> DIR the way Claude Code names its project folder ([A-Za-z0-9-] kept, the rest -)
#   claude_folder_cwd FOLDER -> the cwd in FOLDER/*.jsonl that claude_folder_name maps to FOLDER's name; status 1 if none
#   claude_folder_key FOLDER -> project_key_for_dir of that cwd, else local-<FOLDER name>
#   is_excluded KEY -> status 0 when BM_MEMORY_EXCLUDE (comma separated) lists KEY
#   require_memory_device -> dies unless BM_MEMORY_DEVICE matches ^[a-z0-9-]+$
#   memory_state_dir -> the folder of the mirror's state files
#   memory_mcp_url -> BM_MEMORY_MCP_URL, else the make tunnel endpoint

[ -n "${_BM_LIB_AGENT_MEMORY:-}" ] && return 0
readonly _BM_LIB_AGENT_MEMORY=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

readonly GLOBAL_PROJECT_KEY=_global
readonly LOCAL_KEY_PREFIX=local-
readonly MEMORY_STATE_SUBDIR=bm-agent-memory

normalize_remote() {
  local url="$1" rest host path
  rest="${url#*://}"
  if [[ "$rest" == "$url" ]]; then
    # scp form: [user@]host:path
    rest="${rest#*@}"
    rest="${rest/://}"
  else
    rest="${rest#*@}"
  fi
  host="${rest%%/*}"
  host="${host%%:*}"
  path=""
  [[ "$rest" == */* ]] && path="${rest#*/}"
  path="${path%/}"
  path="${path%.git}"
  path="${path%/}"
  host="$(printf '%s' "$host" | LC_ALL=C tr '[:upper:]' '[:lower:]')" || exit 1
  if [[ -n "$path" ]]; then printf '%s/%s\n' "$host" "$path"; else printf '%s\n' "$host"; fi
}

repo_for_dir() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || url=""
  if [[ -z "$url" ]]; then
    echo ""
    return 0
  fi
  normalize_remote "$url"
}

sanitize_key() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9_-]/-/g'
  echo
}

project_key_for_dir() {
  local dir="${1%/}" repo path owner
  if [[ "$dir" == "${HOME%/}" ]]; then
    echo "$GLOBAL_PROJECT_KEY"
    return 0
  fi
  repo="$(repo_for_dir "$dir")" || exit 1
  if [[ -z "$repo" ]]; then
    sanitize_key "$LOCAL_KEY_PREFIX${dir##*/}"
    return 0
  fi
  # The last two path segments (owner and repo); a remote with one segment gives that segment.
  path="${repo#*/}"
  if [[ "$path" == */* ]]; then
    owner="${path%/*}"
    sanitize_key "${owner##*/}-${path##*/}"
  else
    sanitize_key "$path"
  fi
}

claude_folder_name() {
  printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9-]/-/g'
  echo
}

claude_folder_cwd() {
  local folder="${1%/}" name cwd
  name="${folder##*/}"
  # grep -o prints only the cwd fields (session files can be large); sort -u leaves the few distinct values, since a
  # session file repeats the same cwd tens of thousands of times.
  while IFS= read -r cwd; do
    cwd="${cwd#\"cwd\":\"}"
    cwd="${cwd%\"}"
    if [[ "$(claude_folder_name "$cwd")" == "$name" ]]; then
      echo "$cwd"
      return 0
    fi
  done < <(find "$folder" -maxdepth 1 -name '*.jsonl' -exec grep -ho '"cwd":"[^"]*"' {} + 2>/dev/null | LC_ALL=C sort -u || true)
  return 1
}

claude_folder_key() {
  local folder="${1%/}" cwd
  if cwd="$(claude_folder_cwd "$folder")"; then
    project_key_for_dir "$cwd"
  else
    sanitize_key "$LOCAL_KEY_PREFIX${folder##*/}"
  fi
}

is_excluded() {
  case ",${BM_MEMORY_EXCLUDE:-}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

require_memory_device() {
  [[ "${BM_MEMORY_DEVICE:-}" =~ ^[a-z0-9-]+$ ]] \
    || die "BM_MEMORY_DEVICE must be lowercase letters, digits and - (for example mac-work): set it in .env in the main checkout"
}

memory_state_dir() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/$MEMORY_STATE_SUBDIR"; }

memory_mcp_url() { echo "${BM_MEMORY_MCP_URL:-http://127.0.0.1:${BM_TUNNEL_MCP_PORT:-$DEFAULT_TUNNEL_MCP_PORT}/mcp}"; }
