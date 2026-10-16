#!/usr/bin/env bash
# Document helpers for scripts/*.sh: read the document type registry (the table under "## 문서 타입" in
# docs/README.md) and number new documents. Source scripts/lib/common.sh first (die, log).
# Must stay compatible with macOS bash 3.2. Spec: docs/specs/2026-10-15-doc-system-design.md, sections 3 and 8.2.
#   doc_types REGISTRY -> every type row as tab-separated fields

readonly DOC_TYPES_HEADING="## 문서 타입"
# Registry columns: 타입, 코드, 번호, 위치, 상태 값, 필수 키, 새 문서, 성격, 언어, 템플릿.
readonly DOC_TYPES_COLUMNS=10

# doc_types REGISTRY -> one line per row of the table under DOC_TYPES_HEADING, tab-separated: type, code, number
# (없음|NN|NNNN), location, statuses, required keys, new (허용|금지), template. Backticks and the spaces around each
# cell are dropped. Dies when the table is missing, a row has the wrong cell count or a cell is empty, because a
# shifted column would put a document in the wrong place.
doc_types() {
  local registry="$1" rows status=0
  [[ -f "$registry" ]] || die "missing $registry: it holds the document type registry"
  rows="$(awk -F'|' -v heading="$DOC_TYPES_HEADING" -v want="$DOC_TYPES_COLUMNS" '
    /^## / { inside = ($0 == heading); next }
    !inside || !/^\|/ { next }
    { seen++ }
    seen <= 2 { next }
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
