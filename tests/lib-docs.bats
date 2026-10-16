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
    printf '\n## 메타데이터\n\n| 키 | 값 |\n|---|---|\n| `status` | 상태 |\n'
  } >"$REGISTRY"
}

@test "doc_types reads only the type table, one tab-separated line per row without backticks" {
  write_registry \
    '| spec | spec | 없음 | `docs/specs/` | draft, approved | status, date | 허용 | 기록 | 한국어 | `a/spec.md` |' \
    '| review | rev | 없음 | `docs/reviews/` | final | status | 금지 | 동결 | 영어 | 없음 |'
  run doc_types "$REGISTRY"
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --index 0 "$(printf 'spec\tspec\t없음\tdocs/specs/\tdraft, approved\tstatus, date\t허용\ta/spec.md')"
  assert_line --index 1 "$(printf 'review\trev\t없음\tdocs/reviews/\tfinal\tstatus\t금지\t없음')"
}

@test "doc_types fails when the header row's columns are reordered or the separator row is missing" {
  local top
  # Swapping two columns in the header and in every row keeps the cell counts, so only the header can catch it.
  for top in \
    '| 타입 | 코드 | 위치 | 번호 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |\n|---|---|---|---|---|---|---|---|---|---|' \
    '| 타입 | 코드 | 번호 | 위치 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |'; do
    {
      printf '## 문서 타입\n\n%b\n' "$top"
      printf '%s\n' '| spec | spec | `docs/specs/` | 없음 | draft | status | 허용 | 기록 | 한국어 | `a/spec.md` |'
    } >"$REGISTRY"
    run doc_types "$REGISTRY"
    assert_failure
    assert_output --partial "header"
  done
}

@test "doc_types fails and names the row when a row lost a cell or has an empty one" {
  local row
  for row in \
    '| spec | spec | 없음 | `docs/specs/` | draft | status | 허용 | 기록 | `a/spec.md` |' \
    '| spec | spec | 없음 | `docs/specs/` | draft | status | 허용 | 기록 | | `a/spec.md` |'; do
    write_registry "$row"
    run doc_types "$REGISTRY"
    assert_failure
    assert_output --partial "row 1"
  done
}
