# 13 Doc System Foundation Implementation Plan

> **For agentic workers:** Implement the tasks in order, one at a time: with a fresh subagent and a review per task where the tool supports it (superpowers:subagent-driven-development), otherwise in one session (superpowers:executing-plans). Nothing here touches the VM or cloud resources. Task 2 and Task 4 change `AGENTS.md` only with the wording the user approved in the start section. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 문서 타입 레지스트리(`docs/README.md`), 타입별 템플릿과 `doc-authoring` 스킬, `make new-doc`, Gemini CLI의 `AGENTS.md` 로딩, ADR 0007을 더해 네 에이전트가 저장소 파일만으로 같은 위치·이름·형식의 새 문서를 만들게 한다. 기존 문서는 옮기지 않는다(계획 14).

**Architecture:**
- `docs/README.md`의 `## 문서 타입` 표가 레지스트리다. `scripts/lib/docs.sh`의 `doc_types`가 표를 탭으로 나눈 줄로 읽고, `scripts/create-doc.sh`(`make new-doc`)와 계획 14의 `tests/repo-docs.bats`가 같은 함수를 쓴다.
- 템플릿 다섯 개는 `.agents/skills/doc-authoring/assets/`에 두고, 스킬이 타입 고르기·상태 바꾸기·레이블·새 타입 더하기를 안내한다. 표의 내용은 스킬에 되풀이하지 않는다.
- `create-doc.sh`는 오늘 날짜와 slug로 이름을 만들고, 번호가 있는 타입(plan `NN`, adr `NNNN`)은 모든 로컬·원격 추적 브랜치와 작업 트리에서 옛 이름과 새 이름의 번호를 모아 가장 큰 값 + 1을 쓴다.
- `.gemini/settings.json`이 Gemini CLI에 `AGENTS.md`를 읽게 하고, `tests/repo.bats`가 그 설정과 `AGENTS.md` 24,000바이트 한도를 검사한다. ADR 0007이 이런 구조 검사를 허용한다.

**Tech Stack:** bash 3.2 호환 셸, awk, git(`for-each-ref`, `ls-tree`), bats-core + bats-assert, jq(테스트 이미지), Agent Skills 명세

**Spec:** `docs/specs/2026-10-15-doc-system-design.md` (특히 §3, §4, §5, §6, §7, §8.1, §8.2, §8.4, §10). 파일 이름은 `docs/specs/2026-10-15-script-test-layout-design.md` §4, §6을 따른다.

**Sequence:** 계획 13. 다음을 모두 만족한 뒤 시작한다.
- 이 계획과 두 스펙의 문서 PR(#9)이 `main`에 병합됐다.
- 계획 11이 병합됐다(PR #6, `4c84dba`, 충족).
- 계획 12의 결과 PR(Task 8)과는 고치는 파일이 겹치지 않는다. 그 PR은 계획 12 파일, ADR 0006, 접속 방식 설계, `operations.md`, `gcp-vm.md`만 고친다. 그래서 어느 쪽이 먼저 병합돼도 된다.

## Global Constraints

- 기존 문서의 이름, 위치, 본문, 상태 줄을 바꾸지 않는다(계획 14·15). 예외: ADR 0004 머리의 "일부 대체" 한 줄, `README.md`의 스킬 목록과 문서 지도 한 줄, `AGENTS.md`의 승인된 줄.
- `AGENTS.md`는 시작 절에서 사용자가 승인한 문구 그대로 고친다. 승인 전에는 고치지 않는다(계획 10 때 자동 모드에서 막힌 적이 있다).
- 새 파일 이름은 스크립트·테스트 구조 설계를 따른다: `scripts/create-doc.sh`, `scripts/lib/docs.sh`, `tests/create-doc.bats`, `tests/lib-docs.bats`. 기존 파일 이름(`tests/repo.bats`, `tests/common.bats` 등)은 계획 17이 바꾼다.
- 스크립트 규칙(`AGENTS.md` Invariants): `#!/usr/bin/env bash` 다음 `set -euo pipefail`, `scripts/lib/common.sh` source, 실패는 `die`로, macOS bash 3.2(`mapfile`, 연관 배열, `${x,,}`, 빈 배열 전개 금지), 이름 붙은 상수, 실패할 수 있는 `x="$(fn)"` 뒤 `|| exit 1`.
- 테스트를 먼저 쓴다(RED → GREEN). `make test`/`make check`로만 돌린다. ADR 0004: 레지스트리나 템플릿의 문구를 되풀이하는 테스트를 쓰지 않는다. 테스트는 레지스트리를 읽어 반복문으로 확인한다.
- 템플릿과 스킬 파일에는 실제로 있는 파일만 상대 링크로 걸고, 없는 `docs/...md` 경로를 쓰지 않는다. `tests/repo.bats`의 문서 경로 검사는 `.agents/skills`를 코드 블록까지 읽는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 13`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`, `Claude-Session`, 세션 링크, `Generated with`는 넣지 않는다.
- PR: 브랜치 `plan/13-doc-system-foundation`, 제목 `feat: add the document registry, templates and make new-doc`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 13`이다.
- 증거는 이 계획의 Progress log에 `Verified` / `Command` / `Assumption` / `Open question`으로 남긴다.

## Review Focus

1. **다른 에이전트가 push만 한 계획 번호를 건너뜀.** 원격 추적 브랜치에만 있는 계획 09가 있으면 새 계획은 10이어야 한다. → Task 3 번호 테스트의 `refs/remotes/origin/plan/09-remote`.
2. **08·09 같은 번호를 8진수로 읽다가 실패함.** → Task 3 번호 테스트가 09를 최대값 후보로 둔다.
3. **ADR 폴더의 날짜로 시작하는 파일이 번호를 부풀림.** `2026-10-01-draft.md`를 ADR 2026으로 읽으면 다음 ADR이 2027이 된다. → Task 3 번호 테스트의 `docs/decisions/2026-10-01-draft.md`, 기대값 0007.
4. **slug로 폴더 밖에 쓰거나 같은 날 같은 slug로 덮어씀.** `../escape`, 대문자, 이미 있는 파일. → Task 3 거부 테스트가 작업 트리에 첫 파일 하나만 남고 그 내용이 그대로인지 본다.
5. **레지스트리 표가 깨져 엉뚱한 위치나 템플릿을 씀.** 셀 하나가 빠지거나 비면 열이 밀린다. → Task 1 파서 테스트가 행 번호와 함께 실패하는지 본다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `docs/README.md` | 문서 지도와 레지스트리(`## 문서 타입`), 타입 고르는 법, 이름, 메타데이터, 새 타입 더하기 | 1 |
| `scripts/lib/docs.sh` | 레지스트리 파서 `doc_types`(Task 1), `doc_type_row`, `doc_paths`, `next_doc_number`(Task 3) | 1, 3 |
| `tests/lib-docs.bats` | 파서의 짝 테스트 | 1 |
| `.agents/skills/doc-authoring/SKILL.md`, `assets/{spec,plan,adr,runbook,research}.md` | 작성 규칙과 템플릿 | 2 |
| `.claude/skills/doc-authoring` | Claude Code용 심볼릭 링크 | 2 |
| `scripts/create-doc.sh`, `Makefile`의 `new-doc` | 템플릿에서 문서 만들기 | 3 |
| `tests/create-doc.bats` | 생성 명령의 짝 테스트 | 3 |
| `.gemini/settings.json` | Gemini CLI가 `AGENTS.md`를 읽게 함 | 4 |
| `tests/repo.bats` | Gemini 설정과 `AGENTS.md` 크기 검사 | 4 |
| ADR 0007(`make new-doc`이 만든 경로) | 구조 검사의 허용 범위 | 4 |

---

### 시작: 브랜치, worktree, `AGENTS.md` 문구 승인, 초안 PR

- [ ] `gh pr view 9 --json state`가 `MERGED`다.
- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/13-doc-system-foundation` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 사용자 OK: `main`의 `AGENTS.md`를 다시 읽고, Task 2 Step 6과 Task 4 Step 6의 바뀌는 줄을 지금 줄 번호와 함께 사용자에게 보여 승인을 받는다. 승인한 날짜와 줄 번호를 Progress log에 `Verified`로 적는다. 대상 줄이 이 계획을 쓴 뒤 바뀌었으면 바뀐 문장에 맞춰 다시 보여 준다.
- [ ] 첫 커밋으로 이 계획 파일을 `active/`로 옮기고 push한 뒤 초안 PR을 연다. 이 계획은 레지스트리가 생기기 전에 썼으므로 옛 규칙(폴더 이동)을 따른다.

```bash
git mv docs/plans/backlog/2026-10-16-13-doc-system-foundation.md docs/plans/active/2026-10-16-13-doc-system-foundation.md
git commit -m "docs: start plan 13 doc system foundation" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: none"
git push -u origin plan/13-doc-system-foundation
gh pr create --draft --base main --title "feat: add the document registry, templates and make new-doc" --body-file "$TMPDIR/pr-13.md"
```

---

### Task 1: 레지스트리와 파서

**Files:**
- Create: `docs/README.md`, `scripts/lib/docs.sh`
- Test: `tests/lib-docs.bats`

**Interfaces:**
- Consumes: `scripts/lib/common.sh`의 `die`
- Produces:
  - 상수 `DOC_TYPES_HEADING="## 문서 타입"`, `DOC_TYPES_COLUMNS=10`
  - `doc_types REGISTRY`: 표의 행마다 한 줄, 탭으로 나눈 8개 필드 `type code number location statuses keys new template`. `number`는 `없음|NN|NNNN`, `new`는 `허용|금지`, `location`은 `docs/specs/`처럼 `/`로 끝난다. 셀의 백틱과 앞뒤 공백은 지운다. 표가 없거나 행의 셀 수가 10이 아니거나 빈 셀이 있으면 행 번호를 stderr에 쓰고 `die`한다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/lib-docs.bats`)**

```bash
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
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `lib-docs.bats`의 두 테스트가 `scripts/lib/docs.sh`가 없어 실패한다(setup의 source 오류).

- [ ] **Step 3: 파서 작성 (`scripts/lib/docs.sh`)**

```bash
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
```

- [ ] **Step 4: 레지스트리 작성 (`docs/README.md`)**

템플릿 경로는 Task 2가 만든다. 이 Task에서는 아직 없어도 된다(템플릿 존재 검사는 계획 14).

```markdown
# 문서 지도

이 저장소의 문서가 어디에 있고 새 문서를 어떻게 만드는지 정한다. 문서를 만들거나 상태를 바꿀 때는 `doc-authoring` 스킬을 쓰고, 새 문서는 `make new-doc TYPE=<타입> SLUG=<slug>`로 만든다. 근거는 [문서 체계 설계](specs/2026-10-15-doc-system-design.md)다.

**전환 중 (계획 14가 병합될 때까지):** 기존 문서는 아직 옛 이름(`2026-10-12-...-design.md`, `0004-...md` 등)과 옛 계획 폴더(`docs/plans/backlog/`, `active/`, `completed/`)에 있고 front matter가 없다. 새 문서만 아래 규칙으로 만든다. 옛 이름의 계획은 `git-workflow` 스킬대로 폴더를 옮기고, 새 이름의 계획은 `status`를 바꾼다.

## 문서 타입

| 타입 | 코드 | 번호 | 위치 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |
|---|---|---|---|---|---|---|---|---|---|
| spec | spec | 없음 | `docs/specs/` | draft, approved, superseded | status, date | 허용 | 기록 | 한국어 | `.agents/skills/doc-authoring/assets/spec.md` |
| plan | plan | NN | `docs/plans/` | backlog, active, completed, dropped | status, spec | 허용 | 진행 중엔 갱신, 끝나면 기록 | 제목 영어, 본문 한국어 | `.agents/skills/doc-authoring/assets/plan.md` |
| adr | adr | NNNN | `docs/decisions/` | proposed, accepted, superseded, deprecated | status, date | 허용 | 기록 | 한국어 | `.agents/skills/doc-authoring/assets/adr.md` |
| runbook | rbk | 없음 | `docs/runbooks/` | current, retired | status, reviewed | 허용 | 계속 고침 | 한국어 | `.agents/skills/doc-authoring/assets/runbook.md` |
| research | rsch | 없음 | `docs/research/` | snapshot | status | 허용 | 기록(고정) | 한국어 | `.agents/skills/doc-authoring/assets/research.md` |
| review | rev | 없음 | `docs/reviews/` | final | status | 금지 | 동결 | 영어 | 없음 |

- `번호`: `없음`이면 이름에 번호가 없다. `NN`·`NNNN`이면 날짜 뒤에 그 자릿수의 번호가 온다. `make new-doc`이 모든 로컬·원격 추적 브랜치와 작업 트리에서 가장 큰 번호 + 1을 고른다. 그래서 먼저 `git fetch origin`을 한다.
- `새 문서`: `금지`인 타입은 `make new-doc`이 만들지 않는다. 기존 파일은 그대로 둔다. 리뷰 기록은 계획 09부터 PR 댓글이다.
- `make new-doc`과 문서 검사는 이 표를 읽는다. 셀을 비우거나 열을 빼면 둘 다 그 행 번호와 함께 실패한다.
- `docs/ARCHITECTURE.md`는 표 밖의 단일 파일이다. front matter(`status: current`, `reviewed`)는 갖지만 이름 양식과 템플릿은 없다.

## 타입 고르는 법

- spec: 여러 구성 요소의 관계나 다른 에이전트가 기대는 인터페이스를 바꿀 때. 브레인스토밍 → 스펙 → 계획 순서를 따른다.
- plan: 승인된 스펙을 Task로 나눠 실행할 때. 계획 하나는 독립적으로 검증할 수 있는 Task 3~5개다.
- adr: 되돌리기 비싼 기술 결정, 대안을 검토한 결정, 기존 규칙을 바꾸는 결정을 남길 때.
- runbook: 사람이 따라 하는 절차를 적을 때.
- research: 특정 날짜의 조사를 남길 때. 쓴 뒤에는 고치지 않고, 사실이 바뀌면 새 조사를 쓴다.

## 파일 이름

- 번호가 없는 타입: `<코드>-<YYYY-MM-DD>-<slug>.md`
- 번호가 있는 타입: `<코드>-<YYYY-MM-DD>-<번호>-<slug>.md`(plan은 두 자리, adr은 네 자리)
- 날짜는 문서를 처음 만든 날이다. slug는 영어 소문자와 숫자를 하이픈 하나로 잇는다.
- 이름을 바꾸지 않는 단일 파일: `README.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, `docs/reviews/README.md`

## 메타데이터

파일 맨 위의 YAML front matter에 한 줄에 하나씩 쓴다. 키와 값은 영어 소문자다. 키는 아래 여섯 개만 쓴다.

| 키 | 값 | 쓰는 타입 |
|---|---|---|
| `status` | 타입별 상태 값 | 모든 타입과 ARCHITECTURE |
| `date` | `YYYY-MM-DD`, 마지막으로 상태가 바뀐 날 | spec, adr |
| `spec` | 근거 문서의 저장소 기준 경로, 없으면 `none` | plan |
| `reviewed` | `YYYY-MM-DD`, 내용을 실제와 마지막으로 대조한 날 | runbook, ARCHITECTURE |
| `superseded-by` | 대체한 문서의 경로. `status: superseded`이면 필수 | spec, adr |
| `amended-by` | 일부를 대체한 문서의 경로 하나, 또는 `[경로, 경로]` | spec, adr |

- 상태는 front matter에만 둔다. 본문에 상태 줄을 따로 쓰지 않는다.
- 문서를 대체할 때는 두 문서를 한 커밋에서 고친다. 새 문서는 본문의 "대체 범위"에 무엇을 대체하는지 적고, 옛 문서에는 `status: superseded`와 `superseded-by`(전체) 또는 `amended-by`(일부)를 단다.

## 저장소 밖 문서

| 문서 | 위치 | 언어 |
|---|---|---|
| 에이전트 지침 | `AGENTS.md`. Claude Code는 `CLAUDE.md`의 `@AGENTS.md`로, Gemini CLI는 `.gemini/settings.json`으로 읽는다 | 영어 |
| 스킬 | `.agents/skills/<이름>/SKILL.md`(규칙은 `skill-authoring` 스킬) | 영어 |
| 저장소 소개 | `README.md` | 한국어 |
| PR 본문 | `.github/pull_request_template.md` | 영어 |
| 구조 개요 | `docs/ARCHITECTURE.md` | 한국어 |

## 새 타입을 더하는 법

1. 기존 타입으로 안 되는지 먼저 본다. 위치나 생애 주기(상태 값)가 기존 타입과 다를 때만 새 타입을 만든다.
2. PR 하나에 이 표의 행(겹치지 않는 3~4자 코드 포함), 템플릿(`.agents/skills/doc-authoring/assets/<타입>.md`, 스킬 본문에 이름을 적는다), 필요하면 `AGENTS.md` 지도 한 줄을 함께 넣는다. `make new-doc`과 검사는 이 표를 읽으므로 코드를 고칠 필요가 없다.
3. 상태 값이 기존 타입에 없는 새 생애 주기라면 ADR로 이유를 남긴다.
4. 타입을 그만 쓸 때는 `새 문서` 열을 `금지`로 바꾼다. 새 파일은 막히고 기존 파일은 남는다.
5. front matter 키를 더해야 하면 위 메타데이터 표와 검사의 허용 키 목록을 같은 PR에서 고친다.
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. `lib-docs.bats`의 두 테스트가 통과하고, `relative links in markdown files resolve`가 `docs/README.md`의 스펙 링크를 받아들인다. 커버리지 80% 이상.

- [ ] **Step 6: 커밋**

```bash
git add docs/README.md scripts/lib/docs.sh tests/lib-docs.bats
git commit -m "feat: add the document type registry and its parser" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: 1"
git push
```

---

### Task 2: 템플릿과 `doc-authoring` 스킬

**Files:**
- Create: `.agents/skills/doc-authoring/SKILL.md`, `.agents/skills/doc-authoring/assets/spec.md`, `assets/plan.md`, `assets/adr.md`, `assets/runbook.md`, `assets/research.md`, 링크 `.claude/skills/doc-authoring`
- Modify: `AGENTS.md`(`## Skills` 한 줄, 승인된 문구), `README.md`(스킬 목록, 문서 지도 한 줄)
- Test: `tests/skills.bats`(기존 규칙), `tests/repo.bats`(상대 링크, 문서 경로)

**Interfaces:**
- Consumes: Task 1의 레지스트리 템플릿 열(`.agents/skills/doc-authoring/assets/<type>.md`)
- Produces: 템플릿의 자리표시 `{{date}}`, `{{number}}`, `{{slug}}`(Task 3이 채움). 그 밖의 `{{...}}`는 작성자가 채운다.

- [ ] **Step 1: 템플릿 다섯 개 작성**

`assets/spec.md`:

```markdown
---
status: draft
date: {{date}}
---

# {{제목}} — 설계

- 구현 계획: {{계획 번호와 범위. 아직 없으면 "계획을 쓸 때 정한다"}}
- 근거 조사: {{조사 문서 링크. 없으면 이 줄을 지운다}}
- 대체 범위: {{이 문서가 대체하는 문서와 절. 없으면 이 줄을 지운다}}

## 1. 목적과 범위

{{무엇을 왜 바꾸는가. 두세 문장}}

**사용자 결정 ({{date}})**
1. {{사용자가 정한 것. 대안과 함께 물어 정한 것만 적는다}}

**범위 밖**
- {{하지 않는 것과 이유}}

**완료 조건**
1. {{명령이나 테스트로 확인할 수 있는 결과}}

## 2. 근거가 된 사실 ({{date}}, `main` {{커밋}})

- **Verified:** {{직접 확인한 사실. `path:line`이나 명령과 결과를 붙인다}}
- **Assumption:** {{확인하지 못한 전제. 없으면 이 줄을 지운다}}

## 3. 설계

{{필요한 만큼 3.1, 3.2로 나눈다. 대안이 있었으면 표로 비교하고 고른 이유를 적는다}}

## 4. 보안

{{비밀값, 공개 노출, 인증에 주는 영향. 없으면 그 이유}}

## 5. 테스트와 검증

{{어떤 bats 테스트와 make 타깃으로 완료 조건을 확인하는가}}

## 6. 위험과 대응

| 위험 | 대응 |
|---|---|
| {{위험}} | {{대응}} |

## 7. 계획 분할

| 계획 | 범위 | 시작 조건 |
|---|---|---|
| {{번호와 이름}} | {{범위}} | {{시작 조건}} |

## 8. Open questions

1. {{사람이 정할 일. 없으면 "없음"}}
```

`assets/plan.md`:

```markdown
---
status: backlog
spec: {{근거 스펙의 저장소 기준 경로, 없으면 none}}
---

# {{number}} {{Title in English}} Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** {{이 계획이 끝나면 무엇이 되는가. 한 문장}}

**Architecture:**
- {{접근 방식. 두세 줄}}

**Spec:** `{{근거 스펙 경로}}` ({{특히 읽을 절}})

**Sequence:** 계획 {{number}}. 다음을 모두 만족한 뒤 시작한다.
- {{앞선 PR이나 계획의 병합 같은 조건}}

## Global Constraints

- {{스펙이 정한 저장소 전체 요구사항. 한 줄에 하나, 값은 스펙에서 그대로 옮긴다}}
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: {{number}}`, `Task: <N|review|none>`.

## Review Focus

1. {{어느 Task의 테스트도 다루지 않지만 스펙이 함의하는 입력이나 실패, 그때 기대하는 동작, 그것을 고정하는 테스트를 둔 Task}}

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `{{경로}}` | {{한 줄}} | {{N}} |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/{{number}}-{{slug}}` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: {{구성 요소}}

**Files:**
- Create: `{{경로}}`
- Modify: `{{경로}}`
- Test: `{{경로}}`

**Interfaces:**
- Consumes: {{앞 Task에서 쓰는 이름과 시그니처}}
- Produces: {{뒤 Task가 기대는 이름과 시그니처}}

- [ ] **Step 1: 실패하는 테스트 작성**

{{테스트 코드 전체}}

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: {{실패하는 테스트 이름과 이유}}

- [ ] **Step 3: 최소 구현**

{{구현 코드 전체}}

- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0, 커버리지 80% 이상

- [ ] **Step 5: 커밋**

{{커밋 명령. 트레일러 포함}}

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- {{이 계획 밖으로 미룬 일. 없으면 "없음"}}

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
```

`assets/adr.md`:

```markdown
---
status: proposed
date: {{date}}
---

# ADR {{number}}: {{결정을 한 줄로}}

- 설계: {{근거 스펙 링크. 없으면 이 줄을 지운다}}
- 대체 범위: {{이 ADR이 바꾸는 이전 ADR과 결정 번호. 없으면 이 줄을 지운다}}

## 맥락과 문제

{{무엇이 문제이고 왜 지금 정해야 하는가}}

## 검토한 대안

1. {{대안}}: {{장점}}. {{단점}}.

## 결정

1. {{정한 것. 수락한 뒤에는 이 문장을 고치지 않는다}}

## 결과

- {{좋아지는 것과 치르는 것}}
- 확인 방법: {{이 결정이 지켜지는지 보는 테스트나 명령}}
```

`assets/runbook.md`:

```markdown
---
status: current
reviewed: {{date}}
---

# {{런북 제목}}

{{무엇을 하는 런북이고 언제 쓰는가. 한두 문장}}

## {{절차 이름}}

### 언제 쓰나

{{이 절차가 필요한 상황}}

### 사전 조건

- {{필요한 권한, 설정, 먼저 끝낼 절차}}

### 절차

1. {{명령과 읽을 출력}}

### 확인

- {{성공했음을 보는 명령과 기대 출력}}

### 되돌리기

1. {{실패했을 때 원래대로 돌리는 방법}}
```

`assets/research.md`:

```markdown
---
status: snapshot
---

# {{질문을 제목으로}}

- 기준: {{date}} 시점의 스냅샷이다. 이후 바뀐 사실은 반영하지 않는다. 저장소 안 사실은 `main` {{커밋}} 기준이다.
- 표기: 출처 링크가 붙은 문장은 `Verified`(그날 1차 출처에서 확인), 2차 보도는 `Reported`, 추론은 `Assumption`이다.
- 방법: {{쓴 출처의 종류와 도구}}

{{결론 요약. 질문에 대한 답을 세 줄 이내로}}

## 1. {{주장 문장을 제목으로}}

{{근거와 출처 링크}}

## 시사점

1. {{이 저장소에 주는 의미}}
```

- [ ] **Step 2: 스킬 작성 (`.agents/skills/doc-authoring/SKILL.md`)**

```markdown
---
name: doc-authoring
description: Creates and updates this repo's documents (spec, plan, ADR, runbook, research note) from the type registry in docs/README.md and this skill's templates with make new-doc. Use when writing a new spec, plan, ADR, runbook or research note, changing a document's status (approved, active, completed, superseded), superseding or amending a document, deciding where labels and evidence go, or adding a document type. Not for skills (use skill-authoring) or review records, which are PR comments (use branch-review).
---

# Create and update repository documents

Every agent creates documents the same way from repo files alone. The type registry, the table under "문서 타입" in `docs/README.md`, holds each type's code, number, folder, status values, required front matter keys and template. Read it instead of guessing, and change it instead of working around it.

## Rules

- Create a new document only with `make new-doc TYPE=<type> SLUG=<slug>`. Never copy a neighboring document: older documents predate the templates and spread old formats.
- Write documents only in the folders the registry lists. Repo rules override tool and plugin default paths such as `docs/superpowers/`.
- Never rewrite evidence (commands, output, SHAs, dates, measurements), the decision sentences of an accepted ADR or the user decisions of a spec. Add new facts after them instead.
- Fill every `{{...}}` blank or delete its line before you commit.

## Create a document

1. Pick the type in `docs/README.md` ("타입 고르는 법").
2. Run `git fetch origin`, then `make new-doc TYPE=<type> SLUG=<slug>` in your worktree. Numbered types (plan, adr) take the number after the largest one on every local and remote-tracking branch, so fetch first. The slug is lowercase words joined by single hyphens. The command prints the new path.
3. Fill the template in Korean; plan headings stay English:
   - spec: [assets/spec.md](assets/spec.md)
   - plan: [assets/plan.md](assets/plan.md)
   - ADR: [assets/adr.md](assets/adr.md)
   - runbook: [assets/runbook.md](assets/runbook.md)
   - research note: [assets/research.md](assets/research.md)
4. Commit it through `git-workflow`.

## Front matter and status

- Front matter keys are lowercase English: `status`, `date`, `spec`, `reviewed`, `superseded-by`, `amended-by` (meanings in `docs/README.md`, "메타데이터"). Use no other keys.
- Change `status` in the commit that causes the change, and set `date` (spec, ADR) or `reviewed` (runbook) to that day:
  - spec: `draft`, then `approved` when the user approves it.
  - plan: `backlog` when written, `active` in the first commit of the plan branch, `completed` when every task is done and before the review, or `dropped` with a one-line reason under the title.
  - ADR: `proposed`, then `accepted`; later `superseded` or `deprecated`.
  - runbook: `reviewed` is the day you last followed the steps or checked them against the system.
- To replace a document, write the new one (its "대체 범위" line says what it replaces) and, in the same commit, give the old one `status: superseded` and `superseded-by: <path>`, or `amended-by: <path>` when only part changes.
- Until plan 14 merges, older documents keep their old names and have no front matter, and old-name plans still move between `docs/plans/backlog/`, `active/` and `completed/` as `git-workflow` says. Do not rename them by hand: plan 14 does.

## Labels and evidence

- In Korean documents, start a statement about outside systems, the environment or tool behavior with a label: `**Verified:**` (you checked it), `**Command:**` (what you ran), `**Assumption:**` (not checked), `**Open question:**` (for a human), `**Reported:**` (second-hand). In a table, put only the label in the 표기 column. Add a date when it matters: `**Verified (2026-10-16):**`.
- Record evidence (command and result) in the active plan's Progress log (`| 날짜 | 표기 | 내용 |`) or in an ADR.
- Name repo files by relative link or by repo path in backticks. Write example paths of files that do not exist only inside code blocks.

## Add a document type

1. First check whether an existing type fits. Add a type only for a new folder or a new lifecycle (status values).
2. In one pull request: a registry row with an unused 3-4 letter code, a template `assets/<type>.md` named in this SKILL.md, and a line in `AGENTS.md` if agents need it. `make new-doc` reads the registry, so no code changes.
3. Record the reason in an ADR when the status values are a lifecycle no other type has.
4. To retire a type, set its `새 문서` cell to `금지`: new files are refused and old ones stay.

## Gotchas

- `make new-doc` sees only the branches you have fetched; a number another agent pushed after your last fetch can collide. If your pull request shows a duplicate number, rename your file with `git mv` and update its references.
- `tests/repo.bats` checks the relative links of every tracked Markdown file and every `docs/...md` path named in skills, even inside code blocks, so templates and this skill name only files that exist.
```

- [ ] **Step 3: Claude Code 링크**

```bash
ln -s ../../.agents/skills/doc-authoring .claude/skills/doc-authoring
```

- [ ] **Step 4: 실패 확인**

Run: `make test`
Expected: `AGENTS.md and README.md list every skill`만 `AGENTS.md:doc-authoring README.md:doc-authoring`으로 실패한다. 다른 스킬 규칙(이름, 설명 길이와 `Use when`, 번들 파일 언급, 링크)은 통과한다.

- [ ] **Step 5: `README.md` 고치기**

57행의 스킬 목록에서 `` `skill-authoring`(스킬 추가·수정 규칙) `` 뒤에 `` , `doc-authoring`(문서 작성 규칙) ``을 더한다. 59행("Claude Code·Codex 연결은…") 앞에 한 줄과 빈 줄을 더한다.

```markdown
문서의 종류와 위치, 새 문서를 만드는 법(`make new-doc`)은 [문서 지도](docs/README.md)에 있습니다.
```

- [ ] **Step 6: `AGENTS.md` `## Skills`에 한 줄 (시작 절에서 승인한 문구)**

`` - Adding, renaming or editing a skill: `skill-authoring`. `` 바로 앞에 넣는다.

```markdown
- Writing a spec, plan, ADR, runbook or research note, changing a document's status, or adding a document type: `doc-authoring`.
```

- [ ] **Step 7: 스킬 시험 (skill-authoring 스킬의 "Test the skill")**

이 worktree에서 새 세션으로 아래 세 프롬프트를 실행한다. 바꾸지 말고 계획만 말하라고 덧붙인다(`claude -p "<프롬프트> 아무것도 바꾸지 말고 계획만 말해 주세요."`, 또는 `codex exec`). 두 도구 중 설치된 것으로 한다.
1. "새 ADR을 하나 써야 합니다. 어디에 어떤 이름과 형식으로 만들지 알려 주세요." → `doc-authoring`을 고르고 `make new-doc TYPE=adr`과 `git fetch origin`을 말한다.
2. "계획 14를 backlog에 추가하려고 합니다. 파일을 어떻게 만드나요?" → `make new-doc TYPE=plan`을 말하고 `docs/superpowers/`를 쓰지 않는다.
3. 근접 오답: "skill-authoring 스킬의 Gotchas에 한 줄을 더하려고 합니다." → `doc-authoring`이 아니라 `skill-authoring`을 고른다.

결과(도구, 고른 스킬, 어긋난 점)를 Progress log에 적는다. 틀리게 고르면 설명(description)을, 틀리게 행동하면 본문을 고친 뒤 다시 돌린다.

- [ ] **Step 8: 통과 확인**

Run: `make check`
Expected: exit 0. `tests/skills.bats` 전체와 `relative links in markdown files resolve`, `every docs markdown path named in scripts, skills and AGENTS.md exists`가 통과한다.

- [ ] **Step 9: 커밋**

```bash
git add .agents/skills/doc-authoring .claude/skills/doc-authoring AGENTS.md README.md
git commit -m "feat: add the doc-authoring skill and its templates" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: 2"
git push
```

---

### Task 3: `make new-doc`

**Files:**
- Create: `scripts/create-doc.sh`(실행 권한), `tests/create-doc.bats`
- Modify: `scripts/lib/docs.sh`(함수 셋 추가), `Makefile`(`.PHONY`, `new-doc`)

**Interfaces:**
- Consumes: Task 1의 `doc_types`, `DOC_TYPES_HEADING`, Task 2의 템플릿과 자리표시 `{{date}}`, `{{number}}`, `{{slug}}`
- Produces:
  - `doc_type_row REGISTRY TYPE`: `doc_types`의 그 타입 줄. 없는 타입이면 `die`.
  - `doc_paths ROOT LOCATION`: ROOT 저장소의 모든 `refs/heads`·`refs/remotes`와 작업 트리에서 LOCATION 아래 파일 경로, 한 줄에 하나(중복 포함).
  - `next_doc_number ROOT LOCATION CODE WIDTH`: 새 이름(`CODE-YYYY-MM-DD-N…-`), 날짜가 붙은 옛 이름(`YYYY-MM-DD-N…-`), 날짜 없는 옛 이름(`N…-<소문자>`)에서 읽은 WIDTH자리 번호 중 가장 큰 값 + 1, 0으로 채움.
  - `scripts/create-doc.sh TYPE SLUG`: 만든 파일의 저장소 기준 경로를 stdout에 한 줄로 쓴다. 로그는 stderr.
  - `make new-doc TYPE=<type> SLUG=<slug>`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/create-doc.bats`)**

```bash
#!/usr/bin/env bats
load helpers

# Each test works in a fresh git repo that holds a copy of the real registry and templates.
setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  mkdir -p "$WORK/docs" "$WORK/.agents/skills/doc-authoring"
  cp "$REPO_DIR/docs/README.md" "$WORK/docs/README.md"
  cp -R "$REPO_DIR/.agents/skills/doc-authoring/assets" "$WORK/.agents/skills/doc-authoring/assets"
  cd "$WORK"
  git config user.email agent@example.com
  git config user.name agent
  git add -A
  git commit -q -m "chore: init"
  CREATE="$REPO_DIR/scripts/create-doc.sh"
  TODAY="$(date +%F)"
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
}

@test "creates a document of every type that takes new ones, named, placed and with front matter as its registry row says" {
  local type code number location statuses keys new template path expected doc_status key checked=0
  while IFS=$'\t' read -r type code number location statuses keys new template; do
    [[ "$new" == "허용" ]] || continue
    checked=$((checked + 1))
    path="$("$CREATE" "$type" "check-$code" 2>/dev/null)" || fail "create-doc.sh failed for $type"
    if [[ "$number" == "없음" ]]; then
      expected="${location%/}/$code-$TODAY-check-$code.md"
    else
      expected="${location%/}/$code-$TODAY-$(printf '%0*d' "${#number}" 1)-check-$code.md"
    fi
    assert_equal "$path" "$expected"
    # Not "status": bats run sets that name.
    doc_status="$(frontmatter "$path" | sed -n 's/^status: *//p')"
    [[ ", $statuses," == *", $doc_status,"* ]] || fail "$type: status '$doc_status' is not one of: $statuses"
    for key in $(tr ',' ' ' <<<"$keys"); do
      frontmatter "$path" | grep -q "^$key: " || fail "$type: the front matter has no $key"
    done
    run grep -nE '\{\{(date|number|slug)\}\}' "$path"
    assert_failure 1
  done <<<"$(doc_types "$WORK/docs/README.md")"
  ((checked > 0)) || fail "the registry has no type that takes new documents"
}

@test "numbers plans and ADRs one past the largest number on any branch or in the working tree, in old and new names" {
  mkdir -p docs/plans/completed docs/decisions
  : >docs/plans/completed/2026-10-07-01-first.md
  : >docs/decisions/0006-old-name.md
  # A dated file in the ADR folder must not count as ADR 2026.
  : >docs/decisions/2026-10-01-draft.md
  git add -A
  git commit -q -m "docs: documents with old names"
  git switch -q -c plan/05-local
  mkdir -p docs/plans/backlog
  : >docs/plans/backlog/2026-10-13-05-local.md
  git add -A
  git commit -q -m "docs: plan 05 on a local branch"
  # Only a remote-tracking branch has plan 09, under a new name; 09 is not a valid octal number.
  git switch -q -c scratch
  : >docs/plans/plan-2026-10-14-09-remote.md
  git add -A
  git commit -q -m "docs: plan 09 pushed by another agent"
  git update-ref refs/remotes/origin/plan/09-remote HEAD
  git switch -q main
  git branch -q -D scratch
  run "$CREATE" plan next-plan
  assert_success
  assert_line "docs/plans/plan-$TODAY-10-next-plan.md"
  assert_output --partial "git fetch origin"
  # The first new plan is untracked; the working tree counts too.
  run "$CREATE" plan another-plan
  assert_success
  assert_line "docs/plans/plan-$TODAY-11-another-plan.md"
  run "$CREATE" adr next-adr
  assert_success
  assert_line "docs/decisions/adr-$TODAY-0007-next-adr.md"
}

@test "refuses an unknown type, a type that takes no new documents, a slug that is not lowercase-hyphen and an existing file, and writes nothing" {
  local args
  run "$CREATE" spec same-name
  assert_success
  printf 'edited\n' >>"docs/specs/spec-$TODAY-same-name.md"
  for args in "memo note" "review late-record" "spec Bad_Slug" "spec ../escape" "spec same-name"; do
    # shellcheck disable=SC2086 # two words: the type and the slug
    run "$CREATE" $args
    assert_failure
  done
  run git status --porcelain --untracked-files=all
  assert_output "?? docs/specs/spec-$TODAY-same-name.md"
  run tail -n 1 "docs/specs/spec-$TODAY-same-name.md"
  assert_output "edited"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `create-doc.bats`의 세 테스트가 `scripts/create-doc.sh`가 없어 실패한다.

- [ ] **Step 3: 라이브러리 함수 추가 (`scripts/lib/docs.sh`)**

머리 주석의 색인 줄 아래에 세 줄을 더한다.

```bash
#   doc_type_row REGISTRY TYPE -> the row of TYPE
#   doc_paths ROOT LOCATION -> file paths under LOCATION on every branch and in the working tree
#   next_doc_number ROOT LOCATION CODE WIDTH -> the next free document number, zero-padded
```

`DOC_TYPES_COLUMNS` 아래에 상수 하나를 더한다.

```bash
readonly DOC_DATE_PATTERN='[0-9]{4}-[0-9]{2}-[0-9]{2}'
```

파일 끝에 더한다.

```bash
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
```

- [ ] **Step 4: 생성 스크립트 작성 (`scripts/create-doc.sh`, `chmod +x`)**

```bash
#!/usr/bin/env bash
# Create a document from the template of its type (the table under "## 문서 타입" in docs/README.md). The name is
# <code>-<YYYY-MM-DD>-<slug>.md, with the next free number after the date for numbered types (plan NN, adr NNNN).
# Numbers come from every local and remote-tracking branch and the working tree, so run git fetch origin first.
# Prints the new path on stdout. Spec: docs/specs/2026-10-15-doc-system-design.md, section 8.2.
# Usage: make new-doc TYPE=<type> SLUG=<slug>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/docs.sh
. "$SCRIPT_DIR/lib/docs.sh"

readonly REGISTRY_REL_PATH="docs/README.md"
readonly SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# Registry cell values: a type that takes new documents, and a type without numbers.
readonly NEW_DOCS_ALLOWED="허용"
readonly NO_NUMBER="없음"

main() {
  local type="${1:-}" slug="${2:-}" root row code number location new template day name target
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
```

- [ ] **Step 5: Make 타깃 (`Makefile`)**

`.PHONY` 줄 끝에 ` new-doc`을 더하고, `check-git` 타깃 바로 뒤에 넣는다.

```make
new-doc: ## Create a document from its template: TYPE=<type> SLUG=<slug> (types and rules: docs/README.md)
	scripts/create-doc.sh "$(TYPE)" "$(SLUG)"
```

- [ ] **Step 6: 통과 확인**

Run: `make check`
Expected: exit 0. `create-doc.bats` 세 테스트와 `every Make target has a ## description and is declared .PHONY`가 통과하고, `scripts/create-doc.sh`가 커버리지 목록에 나온다. 전체 80% 이상.

- [ ] **Step 7: macOS에서 직접 실행 (bash 3.2, BSD sed·date)**

```bash
make new-doc TYPE=research SLUG=plan13-smoke
```

Expected: `docs/research/rsch-<오늘>-plan13-smoke.md` 한 줄과 `created …` 로그. 파일 맨 위가 `status: snapshot`이고 `{{date}}`가 오늘 날짜로 바뀌었는지 보고 지운다(`rm docs/research/rsch-<오늘>-plan13-smoke.md`). 결과를 Progress log에 `Verified`로 적는다.

- [ ] **Step 8: 커밋**

```bash
git add scripts/create-doc.sh scripts/lib/docs.sh tests/create-doc.bats Makefile
git commit -m "feat: add make new-doc to create documents from their templates" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: 3"
git push
```

---

### Task 4: 에이전트 진입점과 ADR 0007

**Files:**
- Create: `.gemini/settings.json`, ADR 0007(`make new-doc TYPE=adr SLUG=structure-checks`가 출력한 경로)
- Modify: `tests/repo.bats`(상수 하나, 테스트 둘), `AGENTS.md`(Notes and language, Map; 승인된 문구), `docs/decisions/0004-test-scope.md`(머리 한 줄)

**Interfaces:**
- Consumes: Task 3의 `make new-doc`
- Produces: `tests/repo.bats`의 `AGENTS_MD_MAX_BYTES=24000`, ADR 0007의 경로(계획 14가 ADR 0004의 `amended-by`에 쓴다)

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/repo.bats`)**

`load helpers` 바로 아래에 넣는다.

```bash
# Antigravity truncates a rule file at 24,000 bytes, the smallest limit of the four agents
# (docs/research/2026-10-15-agent-repo-conventions.md, section 1).
AGENTS_MD_MAX_BYTES=24000
```

`CLAUDE.md only imports AGENTS.md` 테스트 바로 뒤에 넣는다.

```bash
@test "Gemini CLI reads AGENTS.md through .gemini/settings.json" {
  run jq -e '.context.fileName | if type == "array" then index("AGENTS.md") != null else . == "AGENTS.md" end' \
    "$REPO_DIR/.gemini/settings.json"
  assert_success
}

@test "AGENTS.md fits the smallest rule file limit of the four agents" {
  local bytes
  bytes="$(wc -c <"$REPO_DIR/AGENTS.md")"
  ((bytes <= AGENTS_MD_MAX_BYTES)) \
    || fail "AGENTS.md has $bytes bytes (max $AGENTS_MD_MAX_BYTES; Antigravity drops the rest): move detail into docs/README.md or a skill"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `Gemini CLI reads AGENTS.md through .gemini/settings.json`만 실패한다(파일 없음, jq exit 2). 크기 검사는 지금 8,278바이트라 처음부터 통과한다. 앞으로 늘어나는 것을 막는 검사다.

- [ ] **Step 3: Gemini 설정 (`.gemini/settings.json`)**

```json
{
  "context": {
    "fileName": ["AGENTS.md"]
  }
}
```

- [ ] **Step 4: ADR 0007 만들기**

```bash
git fetch origin
make new-doc TYPE=adr SLUG=structure-checks
```

출력된 경로가 `docs/decisions/adr-<오늘>-0007-structure-checks.md`인지 본다. 번호가 0007이 아니면 멈추고 다른 브랜치가 쓴 ADR을 확인한다. 파일을 아래 내용으로 채운다(`date`는 오늘). ADR 문장은 다른 ADR처럼 "합니다"체로 쓴다.

```markdown
---
status: accepted
date: <오늘>
---

# ADR 0007: 문서·스크립트 구조 검사를 허용하는 범위

- 설계: [문서 체계 설계](../specs/2026-10-15-doc-system-design.md) 8.4절, [스크립트·테스트 구조 설계](../specs/2026-10-15-script-test-layout-design.md) 9절
- 대체 범위: [ADR 0004](0004-test-scope.md) 결정 2의 "문구·형식만 확인하는 테스트" 금지 가운데, 아래 결정 1의 구조 검사

## 맥락과 문제

- ADR 0004 결정 2는 문구·형식만 확인하는 테스트를 새로 쓰지 않게 했습니다. 그때 지운 것은 문서 문장을 되풀이하는 검사(`AGENTS.md` 줄 수, 런북 섹션 이름 등)였습니다.
- Claude Code, Codex, Gemini CLI, Antigravity가 같은 위치와 이름으로 문서와 스크립트를 만들려면 위치, 이름, 메타데이터를 기계로 확인해야 합니다. 문서 체계 설계 2절의 문제(제각각인 상태 표기, 낡은 경로, PR 구성에 따라 달라지는 active 폴더)는 모두 메타데이터와 위치 문제였습니다.
- 이런 검사도 "형식 확인"으로 읽힐 수 있어서, 무엇을 허용하는지 정해야 합니다.

## 검토한 대안

1. ADR 0004를 그대로 두고 템플릿과 스킬만 둡니다: 바꿀 것이 없습니다. 도구 하나가 템플릿을 무시해도 아무도 모릅니다.
2. 섹션 이름과 레이블까지 검사합니다: 어긋남을 가장 많이 잡습니다. 문서 문구를 되풀이하는 변경 감지 테스트가 되어 ADR 0004의 취지와 어긋납니다.
3. 위치, 이름, 메타데이터, 파일 존재만 검사합니다: 2절의 문제를 모두 잡고 문장은 묶지 않습니다. 사용자가 고른 강제 수준 B입니다.

## 결정

1. 다음 구조 검사는 쓸 수 있습니다: 위치와 파일 이름, 메타데이터의 키와 값, 경로가 가리키는 파일의 존재, 채우지 않은 템플릿 표지(`{{`), 에이전트가 읽는 도구 설정 파일(`CLAUDE.md`, `.gemini/settings.json`), 도구가 자르는 크기 한도, 짝 파일의 존재(스크립트와 테스트).
2. 섹션 이름, 문장, 레이블, 언어를 확인하는 테스트와 문서 문구를 되풀이하는 변경 감지 테스트는 계속 쓰지 않습니다.
3. 구조 검사는 규칙을 정본 한 곳(문서 레지스트리, 동사 표)에서 읽어 반복문으로 씁니다. 실패 메시지는 파일, 어긋난 값, 허용 값, 고칠 곳을 함께 출력합니다.

## 결과

- 계획 13이 `.gemini/settings.json`과 `AGENTS.md` 크기 검사를, 계획 14가 문서 이름·위치·메타데이터 검사를, 계획 17이 스크립트 짝과 이름 검사를 더합니다.
- ADR 0004의 나머지 결정은 그대로입니다.
- 확인 방법: `make check`. 새 테스트가 결정 2에 해당하면 리뷰에서 지적합니다.
```

- [ ] **Step 5: ADR 0004 머리에 한 줄**

`docs/decisions/0004-test-scope.md` 3행(`- 상태: Accepted (2026-10-13)`) 바로 뒤에 넣는다. `<ADR 0007 파일 이름>`은 Step 4의 파일 이름이다. front matter의 `amended-by`로 옮기는 일은 계획 14가 한다.

```markdown
- 일부 대체: [ADR 0007](<ADR 0007 파일 이름>)이 결정 2의 "문구·형식만 확인하는 테스트" 금지에서 구조 검사를 허용합니다.
```

- [ ] **Step 6: `AGENTS.md` (시작 절에서 승인한 문구)**

`## Notes and language`의 두 줄을 바꾸고 한 줄을 더한다. 세 번째 줄(evidence)은 그대로 두고, 네 번째 줄이 새 줄이다.

```markdown
- Label repository notes `Verified`, `Command`, `Assumption`, `Open question` or `Reported` (second-hand), as `**Verified:**` at the start of a paragraph or list item, or in the label column of a table.
- Code, comments, script messages, this file, skills, front matter and plan headings are English. README, `docs/README.md`, runbooks, ARCHITECTURE, ADRs, specs, research and plan bodies are Korean; review records stay as written.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`.
- Create specs, plans, ADRs, runbooks and research notes with `make new-doc TYPE=<type> SLUG=<slug>` in the folders `docs/README.md` lists; this overrides tool and plugin default paths such as `docs/superpowers/`.
```

`## Map`의 `` - `docs/specs/`, `docs/plans/{active,backlog,completed}/`. `` 바로 앞에 두 줄을 더한다.

```markdown
- `docs/README.md` document map and type registry; templates in `.agents/skills/doc-authoring/assets/`.
- `CLAUDE.md` (Claude Code) and `.gemini/settings.json` (Gemini CLI) load this file; Codex and Antigravity read it directly.
```

- [ ] **Step 7: 통과 확인**

Run: `make check`
Expected: exit 0. 새 두 테스트, `tests/skills.bats`, 상대 링크(ADR 0007의 세 링크, ADR 0004의 링크), 문서 경로 검사(`AGENTS.md`의 `docs/README.md`)가 통과한다. `wc -c AGENTS.md`가 24,000 이하다.

- [ ] **Step 8: Gemini CLI 확인 (사용자, 선택)**

사용자가 Gemini CLI를 쓰면 이 worktree에서 `gemini`를 띄워 `/memory show`를 실행하고 `AGENTS.md`의 내용이 보이는지 확인해 달라고 부탁한다. 결과를 Progress log에 `Verified`로 적는다. 하지 않으면 `Assumption`(설정 문서 기준)으로 적는다.

- [ ] **Step 9: 커밋**

```bash
git add .gemini/settings.json tests/repo.bats AGENTS.md docs/decisions
git commit -m "feat: load AGENTS.md in Gemini CLI and allow structure checks (ADR 0007)" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: 4"
git push
```

---

### 마무리: 리뷰, 넘기기 (git-workflow 스킬의 Review and merge)

- [ ] 문서와 코드가 맞는지 본다: `README.md`의 스킬 목록, `AGENTS.md`의 Skills·Map, `docs/README.md`의 저장소 밖 문서 표, `make help`의 `new-doc`.
- [ ] Progress log에 그날 `make check`의 테스트 수와 커버리지 %를 `Verified`로 적고, 계획 파일을 `docs/plans/completed/`로 옮겨 커밋·push한다(`Task: none`). 이 계획은 옛 이름이므로 폴더를 옮긴다.
- [ ] PR 본문의 Verification에 `make check` 결과와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰(`make review BRANCH=plan/13-doc-system-foundation REVIEWER=<다른 벤더>`)는 사용자 승인 후 실행한다. PR 코멘트 게시도 승인 후 한다.
- [ ] 지적을 검증하고 하나당 커밋 하나로 고친다. 2회차까지만 돈다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.
- [ ] 병합 뒤 worktree를 정리한다(`backups/`·`.env` 확인 먼저).

## Follow-ups (이 계획 밖)

- 계획 14: 모든 문서 이름 변경과 참조 갱신, 계획 폴더 통합, front matter, 문서 검사(`tests/repo-docs.bats`, 스펙 8.3절 1~6), 증거 위치 변경(D4). `docs/README.md`와 `doc-authoring` 스킬의 "전환 중" 문장을 지우고, ADR 0004의 "일부 대체" 줄을 front matter `amended-by`로 옮긴다. 계획 12 결과 PR이 병합된 뒤 시작한다.
- 계획 15: 본문 소급(템플릿 절 구성, 레이블 표기 통일, README 중복 삭제).
- 계획 16·17: 스크립트·테스트 구조 설계. `scripts/lib/docs.sh`의 이중 source 방지 줄과 `lib-*.bats` 규칙은 계획 16이 다른 라이브러리와 함께 맞춘다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
