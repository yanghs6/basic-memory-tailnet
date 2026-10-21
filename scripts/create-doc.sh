#!/usr/bin/env bash
# Create a document from the template of its type (the table under "## 문서 타입" in docs/README.md). The name is
# <code>-<YYYY-MM-DD>-<slug>.md, with the next free number after the date for numbered types (plan NN, adr NNNN).
# Numbers come from every local and remote-tracking branch and the working tree, so run git fetch origin first.
# Prints the new path on stdout. Spec: docs/specs/spec-2026-10-15-sgpbx1gq-doc-system.md, section 8.2.
# Usage: make new-doc TYPE=<type> SLUG=<slug>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/docs.sh
. "$SCRIPT_DIR/lib/docs.sh"

readonly REGISTRY_REL_PATH="docs/README.md"
readonly SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# Registry cell values: a type that takes new documents, and a type without numbers.
readonly NEW_DOCS_ALLOWED="허용"
readonly NO_NUMBER="없음"

main() {
  local type="${1:-}" slug="${2:-}" root row code number location new template day name target digits i
  [[ -n "$type" && -n "$slug" ]] || die "usage: make new-doc TYPE=<type> SLUG=<slug> (types: $REGISTRY_REL_PATH)"
  [[ "$slug" =~ $SLUG_PATTERN ]] || die "slug '$slug' must be lowercase letters and digits joined by single hyphens"
  require_cmd git
  root="$(git rev-parse --show-toplevel)" || die "run make new-doc inside a checkout of this repo"
  row="$(doc_type_row "$root/$REGISTRY_REL_PATH" "$type")" || exit 1
  IFS=$'\t' read -r _ code number location _ _ new template <<<"$row"
  [[ "$new" == "$NEW_DOCS_ALLOWED" ]] \
    || die "'$type' documents are no longer created (column 새 문서 in $REGISTRY_REL_PATH)"
  [[ -f "$root/$template" ]] || die "missing template $template for '$type' ($REGISTRY_REL_PATH)"
  day="$(date +%F)"
  name="$code-$day-$slug.md"
  if [[ "$number" != "$NO_NUMBER" ]]; then
    # A rerun would take the next number instead of hitting the existing file, so match any number of that width.
    digits=""
    for ((i = 0; i < ${#number}; i++)); do digits="${digits}[0-9]"; done
    if compgen -G "$root/${location%/}/$code-$day-$digits-$slug.md" >/dev/null; then
      die "a $type with slug '$slug' was already created today in ${location%/}: fill that file or pick another slug"
    fi
    log "numbering from every local and remote-tracking branch: run 'git fetch origin' first if you have not"
    number="$(next_doc_number "$root" "$location" "$code" "${#number}")" || exit 1
    name="$code-$day-$number-$slug.md"
  fi
  target="${location%/}/$name"
  [[ ! -e "$root/$target" ]] || die "$target already exists: pick another slug"
  mkdir -p "$root/${location%/}"
  sed -e "s/{{date}}/$day/g" -e "s/{{number}}/$number/g" -e "s/{{slug}}/$slug/g" "$root/$template" >"$root/$target"
  log "created $target from $template: fill every {{...}} blank or delete its line"
  printf '%s\n' "$target"
}

main "$@"
