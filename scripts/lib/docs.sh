#!/usr/bin/env bash
# Document helpers for scripts/*.sh: read the document type registry (the table under "## 문서 타입" in
# docs/README.md) and number new documents. Sources common.sh.
# Must stay compatible with macOS bash 3.2. Spec: docs/specs/spec-2026-10-15-sgpbx1gq-doc-system.md, sections 3 and 8.2.
#   doc_types REGISTRY -> every type row as tab-separated fields
#   doc_type_row REGISTRY TYPE -> the row of TYPE
#   doc_paths ROOT LOCATION -> file paths under LOCATION on every branch and in the working tree
#   next_doc_number ROOT LOCATION CODE WIDTH -> the next free document number, zero-padded

[ -n "${_BM_LIB_DOCS:-}" ] && return 0
readonly _BM_LIB_DOCS=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"

readonly DOC_TYPES_HEADING="## 문서 타입"
# Registry columns in order, as the header row names them. The parser reads cells by position, so the header must match.
readonly DOC_TYPES_HEADER="타입|코드|번호|위치|상태 값|필수 키|새 문서|성격|언어|템플릿"
readonly DOC_DATE_PATTERN='[0-9]{4}-[0-9]{2}-[0-9]{2}'

# doc_types REGISTRY -> one line per row of the table under DOC_TYPES_HEADING, tab-separated: type, code, number
# (없음|NN|NNNN), location, statuses, required keys, new (허용|금지), template. Backticks and the spaces around each
# cell are dropped. Dies when the table is missing, its header differs from DOC_TYPES_HEADER, the separator row is
# missing, a row has the wrong cell count or a cell is empty, because a shifted column would put a document in the
# wrong place.
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
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", cell[2], cell[3], cell[4], cell[5], cell[6], cell[7], cell[8], cell[11]
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

# next_doc_number ROOT LOCATION CODE WIDTH -> one past the largest WIDTH-digit number among the files under LOCATION
# (doc_paths), zero-padded. Reads new names (CODE-YYYY-MM-DD-NN-slug.md), dated old names (YYYY-MM-DD-NN-slug.md,
# the old plans) and bare old names (NNNN-slug.md, the old ADRs). A bare name needs a letter after the number, so a
# dated file in the ADR folder never counts as ADR 2026.
next_doc_number() {
  local root="$1" location="$2" code="$3" width="$4" paths path name number max=0
  local new_name="^${code}-${DOC_DATE_PATTERN}-([0-9]{${width}})-"
  local old_dated="^${DOC_DATE_PATTERN}-([0-9]{${width}})-"
  local old_bare="^([0-9]{${width}})-[a-z]"
  paths="$(doc_paths "$root" "$location")" || exit 1
  while IFS= read -r path; do
    name="${path##*/}"
    if [[ "$name" =~ $new_name || "$name" =~ $old_dated || "$name" =~ $old_bare ]]; then
      # 10#: read 08 and 09 as decimal numbers, not as invalid octal ones.
      number=$((10#${BASH_REMATCH[1]}))
      if ((number > max)); then
        max=$number
      fi
    fi
  done <<<"$paths"
  printf '%0*d\n' "$width" "$((max + 1))"
}
