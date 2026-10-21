#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
  REGISTRY="$BATS_TEST_TMPDIR/README.md"
}

# write_registry ROW... : a registry whose type table has these body rows, followed by another section with a table.
write_registry() {
  {
    printf '# 문서 지도\n\n## 문서 타입\n\n'
    printf '| 타입 | 코드 | 번호 | 위치 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|\n'
    printf '%s\n' "$@"
    # shellcheck disable=SC2016 # the backticks are literal Markdown in the registry text
    printf '\n## 메타데이터\n\n| 키 | 값 |\n|---|---|\n| `status` | 상태 |\n'
  } >"$REGISTRY"
}

@test "doc_types reads only the type table, one tab-separated line per row without backticks" {
  # shellcheck disable=SC2016 # the backticks are literal Markdown in the registry rows
  write_registry \
    '| spec | spec | 없음 | `docs/specs/` | draft, approved | status, date | 허용 | 기록 | 한국어 | `a/spec.md` |' \
    '| review | rev | 없음 | `docs/reviews/` | final | status | 금지 | 동결 | 영어 | 없음 |'
  run doc_types "$REGISTRY"
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --index 0 "$(printf 'spec\tspec\t없음\tdocs/specs/\tdraft, approved\tstatus, date\t허용\ta/spec.md')"
  assert_line --index 1 "$(printf 'review\trev\t없음\tdocs/reviews/\tfinal\tstatus\t금지\t없음')"
}

@test "doc_types fails on a reordered header, a missing separator, a short row and an empty cell" {
  local case problem message header separator swapped_header swapped_row
  header='| 타입 | 코드 | 번호 | 위치 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |'
  separator='|---|---|---|---|---|---|---|---|---|---|'
  # Swapping two columns in the header and in every row keeps the cell counts, so only the header can catch it.
  swapped_header='| 타입 | 코드 | 위치 | 번호 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |'
  # shellcheck disable=SC2016 # the backticks are literal Markdown in the registry rows
  swapped_row='| spec | spec | `docs/specs/` | 없음 | draft | status | 허용 | 기록 | 한국어 | `a/spec.md` |'
  # Each case: the registry's problem | the start of the message that names it.
  for case in "reordered header|the header row must name the columns" "missing separator|the separator row" \
    "short row|row 1 has 9 cells" "empty cell|row 1 has an empty cell"; do
    IFS='|' read -r problem message <<<"$case"
    (
      # shellcheck disable=SC2016 # the backticks are literal Markdown in the registry rows
      case "$problem" in
        "reordered header") printf '## 문서 타입\n\n%s\n%s\n%s\n' "$swapped_header" "$separator" "$swapped_row" >"$REGISTRY" ;;
        "missing separator") printf '## 문서 타입\n\n%s\n%s\n' "$header" "$swapped_row" >"$REGISTRY" ;;
        "short row") write_registry '| spec | spec | 없음 | `docs/specs/` | draft | status | 허용 | 기록 | `a/spec.md` |' ;;
        "empty cell") write_registry '| spec | spec | 없음 | `docs/specs/` | draft | status | 허용 | 기록 | | `a/spec.md` |' ;;
      esac
      run doc_types "$REGISTRY"
      assert_failure && assert_output --partial "$message"
    ) || fail "doc_types did not fail on a $problem"
  done
}
