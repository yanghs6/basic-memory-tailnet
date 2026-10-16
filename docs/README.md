# 문서 지도

이 저장소의 문서가 어디에 있고 새 문서를 어떻게 만드는지 정한다. 문서를 만들거나 상태를 바꿀 때는 `doc-authoring` 스킬을 쓰고, 새 문서는 `make new-doc TYPE=<타입> SLUG=<slug>`로 만든다. 근거는 [문서 체계 설계](specs/spec-2026-10-15-doc-system.md)다.

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
