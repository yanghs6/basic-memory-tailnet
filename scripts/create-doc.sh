#!/usr/bin/env bash
# Create a document from the template of its type (the table under "## 문서 타입" in docs/README.md). The name is
# <code>-<YYYY-MM-DD>-<id>-<slug>.md for every type; the id is the one passed in, else a random id that no file name
# under docs/ on any local or remote-tracking branch or in the working tree uses, so run git fetch origin first.
# Prints the new path on stdout. Spec: docs/specs/spec-2026-10-23-q3jxc77k-doc-ids-and-draft-board.md, section 3.
# Usage: make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/docs.sh
. "$SCRIPT_DIR/lib/docs.sh"

readonly REGISTRY_REL_PATH="docs/README.md"
readonly SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# Registry cell value: a type that takes new documents.
readonly NEW_DOCS_ALLOWED="허용"

main() {
  local type="${1:-}" slug="${2:-}" id="${3:-}" root row code location new template day target
  [[ -n "$type" && -n "$slug" ]] || die "usage: make new-doc TYPE=<type> SLUG=<slug> [ID=<id>] (types: $REGISTRY_REL_PATH)"
  [[ "$slug" =~ $SLUG_PATTERN ]] || die "slug '$slug' must be lowercase letters and digits joined by single hyphens"
  [[ -z "$id" || "$id" =~ ^${DOC_ID_PATTERN}$ ]] \
    || die "id '$id' must be 8 characters from 0-9 and a-z without i, l, o and u: leave ID empty for a random one"
  require_cmd git
  root="$(git rev-parse --show-toplevel)" || die "run make new-doc inside a checkout of this repo"
  row="$(doc_type_row "$root/$REGISTRY_REL_PATH" "$type")" || exit 1
  IFS=$'\t' read -r _ code location _ _ new template <<<"$row"
  [[ "$new" == "$NEW_DOCS_ALLOWED" ]] \
    || die "'$type' documents are no longer created (column 새 문서 in $REGISTRY_REL_PATH)"
  [[ -f "$root/$template" ]] || die "missing template $template for '$type' ($REGISTRY_REL_PATH)"
  day="$(date +%F)"
  # A rerun would get a new random id instead of hitting the existing file, so match any id.
  if compgen -G "$root/${location%/}/$code-$day-$DOC_ID_GLOB-$slug.md" >/dev/null; then
    die "a $type with slug '$slug' was already created today in ${location%/}: fill that file or pick another slug"
  fi
  if [[ -z "$id" ]]; then
    log "checking ids on every local and remote-tracking branch: run 'git fetch origin' first if you have not"
    id="$(new_doc_id "$root")" || exit 1
  elif doc_id_taken "$root" "$id"; then
    die "id '$id' is already used by a file name under docs/ on this or another branch: leave ID empty for a random one"
  fi
  target="${location%/}/$code-$day-$id-$slug.md"
  [[ ! -e "$root/$target" ]] || die "$target already exists: pick another slug"
  mkdir -p "$root/${location%/}"
  sed -e "s/{{date}}/$day/g" -e "s/{{id}}/$id/g" -e "s/{{slug}}/$slug/g" "$root/$template" >"$root/$target"
  log "created $target from $template: fill every {{...}} blank or delete its line"
  printf '%s\n' "$target"
}

main "$@"
