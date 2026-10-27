#!/usr/bin/env bash
# Stops when the local compose project's containers were started from another directory (another worktree), so that
# make local-up does not silently recreate, and make local-down does not stop, a stack that another worktree uses.
# Changes nothing: it only lists containers with docker ps.
# Usage: scripts/check-local-stack.sh (make local-up and make local-down run it first; no target of its own)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# The compose file whose top-level name: is the project name (the one place it is set).
readonly COMPOSE_FILE="$REPO_DIR/compose.yaml"
# Labels Docker Compose puts on every container of a project.
readonly PROJECT_LABEL="com.docker.compose.project"
readonly WORKING_DIR_LABEL="com.docker.compose.project.working_dir"

# project_name -> the top-level name: of COMPOSE_FILE; dies when it has none.
project_name() {
  local name
  name="$(sed -n 's/^name:[[:space:]]*//p' "$COMPOSE_FILE" | head -n 1)" || exit 1
  [[ -n "$name" ]] || die "$COMPOSE_FILE has no top-level 'name:': restore it (compose.yaml line 4)"
  printf '%s\n' "$name"
}

# stack_dirs NAME -> the distinct working directories of the containers of project NAME, one per line.
stack_dirs() {
  docker ps -a --filter "label=$PROJECT_LABEL=$1" --format "{{.Label \"$WORKING_DIR_LABEL\"}}" | sort -u
}

main() {
  require_cmd docker
  local name dirs dir own real
  name="$(project_name)" || exit 1
  dirs="$(stack_dirs "$name")" || die "docker ps failed: start Docker, then rerun the make target"
  own="$(cd "$REPO_DIR" && pwd -P)" || exit 1
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    if [[ ! -d "$dir" ]]; then
      log "WARNING: the local stack '$name' was started in $dir, which no longer exists; continuing"
      continue
    fi
    real="$(cd "$dir" && pwd -P)" || exit 1
    [[ "$real" == "$own" ]] \
      || die "the local stack '$name' belongs to $dir: run 'make local-down' in that worktree (or wait until it is done there), then rerun this target"
  done <<<"$dirs"
}

main "$@"
