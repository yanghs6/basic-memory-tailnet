#!/usr/bin/env bash
# Write the SilverBullet space files into the Basic Memory notes folder, locally (--local) or on the VM:
#   .gitignore                      keeps SilverBullet-only pages out of the Basic Memory index (always replaced)
#   Library/agent-hub/agent-hub.md  font, new-note frontmatter hook, journal off, tree, dashboard (replaced on every
#                                   run that prints "unchanged")
#   index.md                        the dashboard page (only when missing, so your edits stay)
# Basic Memory reads .gitignore only at start, keeps using the old patterns until then and never drops a file it
# already indexed. Before changing .gitignore, this script creates the $SB_GITIGNORE_PENDING marker. While the marker
# exists it writes only .gitignore and prints "changed": the caller recreates the Basic Memory container, removes the
# marker only after that succeeds, and runs this script again to write the pages. Without the marker it writes the
# library page (and index.md when missing) and prints "unchanged". A run that failed in between (a pull, the
# recreate) leaves the marker, so the next run asks again.
# Usage: sb-space.sh [--local]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

readonly SOURCE_DIR="$REPO_DIR/silverbullet"
readonly LIBRARY_PAGE=Library/agent-hub/agent-hub.md

main() {
  local local_dir previous state pending where
  local_dir="$(notes_dir_arg "$@")" || exit 1
  where="${local_dir:-$BM_VM_HOST:$SB_REMOTE_NOTES_DIR}"

  previous="$(in_notes_dir "$local_dir" 'cat .gitignore 2>/dev/null || true' </dev/null)" \
    || die "could not read the notes folder $where"
  if [[ "$previous" != "$(cat "$SOURCE_DIR/notes.gitignore")" ]]; then
    in_notes_dir "$local_dir" "touch $SB_GITIGNORE_PENDING" </dev/null \
      || die "could not mark the .gitignore change in $where, so .gitignore was not written"
  fi
  write_notes_file "$local_dir" .gitignore <"$SOURCE_DIR/notes.gitignore" || die "could not write .gitignore in $where"

  pending="$(notes_file_state "$local_dir" "$SB_GITIGNORE_PENDING")" \
    || die "could not check for $SB_GITIGNORE_PENDING in $where"
  if [[ "$pending" == present ]]; then
    # A running Basic Memory would index the pages under the old patterns and keep them after the recreate.
    log "the notes .gitignore changed since Basic Memory started: it must be recreated to load it"
    echo changed
    return 0
  fi

  write_notes_file "$local_dir" "$LIBRARY_PAGE" <"$SOURCE_DIR/agent-hub.md" || die "could not write $LIBRARY_PAGE in $where"
  state="$(notes_file_state "$local_dir" index.md)" \
    || die "could not check for index.md in $where, so it was not written"
  if [[ "$state" == absent ]]; then
    write_notes_file "$local_dir" index.md <"$SOURCE_DIR/index.md" || die "could not write index.md in $where"
    log "wrote the dashboard index.md"
  fi
  echo unchanged
}

main "$@"
