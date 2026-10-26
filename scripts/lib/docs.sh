#!/usr/bin/env bash
# Document helpers for scripts/*.sh: read the document type registry (the table under "## 문서 타입" in
# docs/README.md) and give new documents random ids. Sources common.sh.
# Must stay compatible with macOS bash 3.2. Spec: docs/specs/spec-2026-10-15-sgpbx1gq-doc-system.md, sections 3 and 8.2.
#   doc_types REGISTRY -> every type row as tab-separated fields
#   doc_type_row REGISTRY TYPE -> the row of TYPE
#   doc_paths ROOT LOCATION -> file paths under LOCATION on every branch and in the working tree
#   doc_id_taken ROOT ID -> exit 0 when a file name under docs/ on any branch or in the working tree holds the id
#   random_doc_id -> a random id
#   new_doc_id ROOT -> a random id, not hex digits only, that no file name under docs/ uses
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

[ -n "${_BM_LIB_DOCS:-}" ] && return 0
readonly _BM_LIB_DOCS=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

readonly DOC_TYPES_HEADING="## 문서 타입"
# Registry columns in order, as the header row names them. The parser reads cells by position, so the header must match.
readonly DOC_TYPES_HEADER="타입|코드|위치|상태 값|필수 키|새 문서|성격|언어|템플릿"
readonly DOC_DATE_PATTERN='[0-9]{4}-[0-9]{2}-[0-9]{2}'
# A document id: 8 characters of the lowercase base32 alphabet without i, l, o and u (spec-2026-10-23, section 3.1).
readonly DOC_ID_LENGTH=8
readonly DOC_ID_ALPHABET='0-9a-hjkmnp-tv-z'
readonly DOC_ID_PATTERN='[0-9a-hjkmnp-tv-z]{8}'
# The same pattern as a shell glob, for matching file names.
readonly DOC_ID_GLOB='[0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z][0-9a-hjkmnp-tv-z]'
readonly DOC_ID_MAX_TRIES=20
# An id of hex digits only would read like a short commit SHA, so new_doc_id never hands one out.
readonly DOC_ID_HEX_ONLY_PATTERN='^[0-9a-f]+$'

# doc_types REGISTRY -> one line per row of the table under DOC_TYPES_HEADING, tab-separated: type, code, location,
# statuses, required keys, new (허용|금지), template. Backticks and the spaces around each cell are dropped. Dies when
# the table is missing, its header differs from DOC_TYPES_HEADER, the separator row is missing, a row has the wrong cell
# count or a cell is empty, because a shifted column would put a document in the wrong place.
doc_types() {
  local registry="$1" rows status=0
  [[ -f "$registry" ]] || die "missing $registry: it holds the document type registry"
  rows="$(awk -F'|' -v heading="$DOC_TYPES_HEADING" -v header="$DOC_TYPES_HEADER" '
    BEGIN { want = split(header, names, "|") }
    /^## / { inside = ($0 == heading); next }
    !inside || !/^\|/ { next }
    { seen++ }
    seen == 1 {
      got = ""
      for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); got = got (i > 2 ? "|" : "") c }
      if (got != header) { printf "the header row must name the columns %s in this order, not: %s\n", header, $0 > "/dev/stderr"; bad = 1 }
      next
    }
    seen == 2 {
      if ($0 !~ /^\|( *:?-+:? *\|)+ *$/) { printf "the separator row (|---|) must follow the header, not: %s\n", $0 > "/dev/stderr"; bad = 1 }
      next
    }
    NF - 2 != want {
      printf "row %d has %d cells (want %d): %s\n", seen - 2, NF - 2, want, $0 > "/dev/stderr"
      bad = 1
      next
    }
    {
      for (i = 2; i < NF; i++) {
        cell[i] = $i
        gsub(/`/, "", cell[i])
        gsub(/^ +| +$/, "", cell[i])
        if (cell[i] == "") { printf "row %d has an empty cell %d: %s\n", seen - 2, i - 1, $0 > "/dev/stderr"; bad = 1 }
      }
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", cell[2], cell[3], cell[4], cell[5], cell[6], cell[7], cell[10]
    }
    END {
      if (seen <= 2) { print "no type rows under the heading" > "/dev/stderr"; bad = 1 }
      exit bad
    }
  ' "$registry")" || status=$?
  ((status == 0)) || die "fix the table under '$DOC_TYPES_HEADING' in $registry (see the rows above)"
  printf '%s\n' "$rows"
}

# doc_type_row REGISTRY TYPE -> the doc_types line of TYPE. Dies when the registry lists no such type.
doc_type_row() {
  local rows row
  rows="$(doc_types "$1")" || exit 1
  row="$(awk -F'\t' -v type="$2" '$1 == type' <<<"$rows")" || exit 1
  [[ -n "$row" ]] || die "unknown document type '$2': pick one from the table under '$DOC_TYPES_HEADING' in $1"
  printf '%s\n' "$row"
}

# doc_paths ROOT LOCATION -> every file path under LOCATION on each local and remote-tracking branch of the repo at
# ROOT and in its working tree, one per line (repeats included).
doc_paths() {
  local root="$1" location="$2" refs ref
  refs="$(git -C "$root" for-each-ref --format='%(refname)' refs/heads refs/remotes)" \
    || die "git for-each-ref failed in $root"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    git -C "$root" ls-tree -r --name-only "$ref" -- "$location" || die "git ls-tree failed for $ref in $root"
  done <<<"$refs"
  if [[ -d "$root/$location" ]]; then
    (cd "$root" && find "$location" -type f)
  fi
}

# doc_id_taken ROOT ID -> exit 0 when a file name under docs/ on any branch or in the working tree holds -ID-.
doc_id_taken() {
  local paths
  paths="$(doc_paths "$1" docs)" || exit 1
  grep -qF -- "-$2-" <<<"$paths"
}

# random_doc_id -> DOC_ID_LENGTH characters of DOC_ID_ALPHABET from /dev/urandom. Split out so tests can fix the value.
# tr dies of SIGPIPE when head has its bytes, which pipefail reports, so the status is ignored and the length is checked.
random_doc_id() {
  local id
  id="$(LC_ALL=C tr -dc "$DOC_ID_ALPHABET" </dev/urandom | head -c "$DOC_ID_LENGTH" || true)"
  [[ ${#id} -eq $DOC_ID_LENGTH ]] || die "could not read $DOC_ID_LENGTH random characters from /dev/urandom"
  printf '%s\n' "$id"
}

# new_doc_id ROOT -> an id that is not hex digits only and that no file name under docs/ uses (doc_id_taken), tried up
# to DOC_ID_MAX_TRIES times.
new_doc_id() {
  local root="$1" id tries=0
  while ((tries < DOC_ID_MAX_TRIES)); do
    id="$(random_doc_id)" || exit 1
    if [[ ! "$id" =~ $DOC_ID_HEX_ONLY_PATTERN ]] && ! doc_id_taken "$root" "$id"; then
      printf '%s\n' "$id"
      return 0
    fi
    tries=$((tries + 1))
  done
  die "no unused id after $DOC_ID_MAX_TRIES tries: rerun, or check that docs/ does not hold thousands of ids"
}
