---
status: approved
date: 2026-10-16
amended-by: docs/specs/spec-2026-10-23-doc-ids-and-draft-board.md
---

# 에이전트 공용 문서 체계 — 설계

- 기준 커밋은 `main` 87e86d4(계획 12 코드 병합)다.
- 구현 계획: 계획 13(기반), 계획 14(이름·메타데이터 소급과 검사), 계획 15(본문 소급). 번호는 계획을 쓸 때 모든 브랜치를 훑어 다시 확인한다.
- 근거 조사: [여러 코딩 에이전트가 같은 규칙으로 문서·스크립트·테스트를 만들게 하려면](../research/rsch-2026-10-15-agent-repo-conventions.md)
- 함께 읽기: [스크립트·테스트 구조 설계](spec-2026-10-15-script-test-layout.md). 이 스펙의 레지스트리, 생성 명령, 구조 검사 원칙을 스크립트와 테스트에 적용한다.
- 대체 범위: [OCI 설계](spec-2026-10-07-basic-memory-oci-tailscale.md) §5의 문서 배치 규칙(GCP 설계 §5가 이어받음)과 [git·리뷰 정책](spec-2026-10-07-git-review-policy.md)·[GitHub PR 워크플로](spec-2026-10-13-github-pr-workflow.md) §9의 계획 파일 이동 규칙(계획 상태는 폴더가 아니라 front matter의 `status`)을 이 문서로 대체한다. [ADR 0004](../decisions/adr-2026-10-13-0004-test-scope.md) 결정 2의 "문구·형식만 확인하는 테스트" 금지는 새 ADR로 일부 대체한다(8.4절).

## 1. 목적과 범위

Claude Code, Codex, Gemini CLI, Antigravity 중 어느 에이전트든 플러그인 없이 저장소 안의 정보만으로 맞는 위치와 형식의 문서를 만들게 한다. 어긋나면 `make check`가 잡는다. 지금은 문서 형식의 일부가 Claude 전용 플러그인(superpowers)에서 오고, 같은 타입의 문서끼리 상태 표기와 메타데이터가 다르며, 낡은 경로를 검사가 잡지 못한다(2절).

**사용자 결정 (2026-10-15)**
1. 대상 도구는 커밋 트레일러가 허용하는 네 가지다(`AGENTS.md`의 `## Git`).
2. 강제 수준은 B다. 저장소가 가진 템플릿, 작성 스킬, 생성 명령을 두고, 검사는 메타데이터·파일 이름·위치만 본다. 문장과 섹션 이름은 검사하지 않는다.
3. 스크립트와 테스트도 구조를 정리한다(함께 읽기의 스펙). 스킬은 [ADR 0003](../decisions/adr-2026-10-13-0003-skill-structure.md)으로 이미 정리했으므로 범위 밖이다.
4. 스펙이 크면 항목별로 나눈다. 그래서 문서와 스크립트·테스트를 두 스펙으로 나눴다.

**사용자 결정 (2026-10-15, 초안 검토)**
- D1. 기존 문서에 가능한 만큼 최대한 소급 적용한다. 최소한 파일 이름은 모두 새 양식으로 바꾼다(9절).
- D2. 계획 폴더를 `docs/plans/` 하나로 합치고 상태를 front matter에 둔다(5.2절).
- D3. 메타데이터는 YAML front matter에 둔다. 키와 값은 영어, 본문은 한국어다(4절).
- D4. PR의 CI 결과는 계획의 Progress log가 아니라 PR 본문에 남긴다. `AGENTS.md`의 `## Code Review Rules` 3번이 바뀐다(6.3절).
- D5. 계획 11이 병합된 뒤 계획 13부터 진행한다(10절). 2026-10-16에 충족됐다(PR #6, `4c84dba`).
- D6. 문서 파일 이름을 "타입 코드-날짜-slug"로 통일한다(3.1절).
- D7. 계획 템플릿에 ExecPlan의 Decision Log, Surprises & Discoveries 절을 더하지 않는다.
- D8. `docs/reviews/`는 그 자리에 둔다.

**사용자 결정 (2026-10-16, D6의 세부)** 초안을 그대로 받았다.
- N1. 타입 코드: `spec`, `plan`, `adr`, `rbk`(런북), `rsch`(조사), `rev`(리뷰).
- N2. 번호가 있는 타입은 날짜 뒤에 번호를 둔다: `plan-2026-10-15-13-<slug>.md`, `adr-2026-10-13-0004-<slug>.md`. 계획 브랜치(`plan/NN-slug`), `Plan:` 트레일러, "ADR 0004" 같은 부르는 이름을 그대로 쓸 수 있다.
- N3. `README.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, `docs/reviews/README.md`는 이름을 바꾸지 않는다. GitHub이 폴더를 열 때 보여 주는 이름이고, `ARCHITECTURE.md`는 널리 쓰는 고정 이름이다.
- N4. 이름에 날짜가 없던 문서(ADR, 런북, 리뷰)는 그 파일이 처음 커밋된 날을 쓴다. 스펙은 타입 코드가 뜻을 말하므로 `-design` 꼬리를 뗀다.

**사용자 결정 (2026-10-16, 계획 15 범위)**
- D9. 기존 문서의 절 구성(이름, 순서, 번호)은 바꾸지 않고, 템플릿은 새 문서에 쓴다. 이유: 다른 문서가 절 번호와 제목으로 인용하고(리뷰를 빼고 177행·16파일, 2026-10-16), 스크립트와 스킬이 런북 제목과 번호를 가리키며, 옛 ADR에 없는 절은 내용을 지어내야 한다. 계획 15는 레이블 표기(6.2절)와 README의 중복만 정리하고, 리뷰 기록과 조사 문서(5.5절)는 레이블도 그대로 둔다. 예외로 제목 꼬리에 붙은 레이블(`## 근거 (Verified, 날짜)`)은 꼬리만 떼어 제목 바로 아래 첫 줄로 옮긴다. 제목의 나머지와 번호는 그대로다.

**범위 밖**
- 스크립트·테스트 구조: 함께 읽기의 스펙
- 스킬의 구조와 규칙: ADR 0003, `skill-authoring` 스킬, `tests/skills.bats`
- `silverbullet/*.md`: 문서가 아니라 VM에 배포하는 공간 파일이다(`tests/sb_space.bats`가 바이트 단위로 비교한다).
- 필수 헤딩, 문체, 레이블, 언어의 기계 검사: 결정 2에 따라 템플릿과 리뷰로 지킨다.
- 외부 도구(markdownlint, lychee, yq) 도입: bats와 awk로 충분하다(근거 조사 §4).

**완료 조건**
1. 네 도구가 모두 `AGENTS.md`를 읽는다.
2. `docs/README.md`의 레지스트리가 모든 문서 타입을 정의하고, 새 문서를 만들 수 있는 타입마다 템플릿이 있다.
3. `make new-doc TYPE=<type> SLUG=<slug>`가 템플릿에서 문서를 만든다.
4. `doc-authoring` 스킬이 있고, `AGENTS.md`의 `## Skills`가 문서 작업을 그 스킬로 보낸다.
5. 기존 문서가 모두 레지스트리 규칙(이름, 위치, 메타데이터)을 지키고, 어긋나면 `make check`가 고치는 방법과 함께 실패한다.
6. 새 ADR이 허용하는 구조 검사의 범위를 정한다.

## 2. 근거가 된 사실 (2026-10-16, `main` 87e86d4)

**Verified (저장소):**
- `AGENTS.md`를 읽는 도구는 Claude Code(`CLAUDE.md`의 `@AGENTS.md`), Codex, Antigravity다. Gemini CLI는 기본 파일이 `GEMINI.md`인데 저장소에 `.gemini/settings.json`이 없어 읽지 않는다(근거 조사 §1).
- 저장소가 가진 템플릿은 세 개다: `.agents/skills/skill-authoring/assets/skill-template.md`, `docs/reviews/README.md`의 리뷰 기록 템플릿, `.github/pull_request_template.md`. 스펙, 계획, ADR, 런북, 조사 문서의 템플릿은 없다.
- 계획 골격(Goal, Architecture, Global Constraints, `### Task N`, `- [ ] **Step N`)은 superpowers 6.4.1 writing-plans 스킬의 헤더를 따른다. 이 플러그인은 Claude Code에만 있다.
- 계획 폴더가 PR 구성에 따라 달라진다. 계획은 첫 커밋에서 active로 옮기고(`.agents/skills/git-workflow/SKILL.md` Start 3) 리뷰 전에 completed로 옮기므로(`.agents/skills/git-workflow/references/review-and-merge.md:7`) 계획 01~11은 병합 뒤 `main`에 active가 남지 않았다. 코드 PR과 결과 PR로 나뉜 계획 12는 active에 둔 채 코드 PR이 병합됐다(`docs/plans/plan-2026-10-15-12-access-modes.md`). 그래서 `main`의 active는 비어 있기도 하고 아니기도 하다. `AGENTS.md:5`와 `.github/pull_request_template.md:7`은 active를 가리킨다.
- 상태 표기가 제각각이다. 스펙은 "승인됨", "승인", "대체됨", "부분 대체"를, ADR은 "Accepted"를 쓴다. 메타데이터 줄의 키도 스펙마다 다르다(상태, 구현 계획, 범위, 출처, 대체 범위, 근거 조사, 적용 시점).
- 낡은 경로와 상태가 남아 있다.
  - GCP 설계 8행은 계획 04를 "진행 중"이라고 적는다.
  - 웹 UI 설계 4행은 완료된 계획 10·11을 backlog에 있다고 적고, 6행은 계획 11을 아직 시작 전으로 적는다.
  - 접속 방식 설계는 병합됐는데도 3행이 "초안"이고, 4행은 active에 있는 계획 12를 backlog 경로로 가리킨다.
  - ADR 0006의 3행은 날짜 자리에 "계획 12 병합일"이 남아 있다.
  - 완료된 계획 01~04의 Sequence 줄은 backlog 경로를 가리킨다.
  - 이 경로들은 링크가 아닌 백틱 표기라서 `tests/repo.bats`의 상대 링크 검사가 잡지 못한다.
- 레이블(`AGENTS.md:39`) 표기가 여섯 가지 이상이다: `| Verified |`, `**Verified:**`, `**Verified**`, `- Verified:`, `**Verified (로컬):**`, 제목 꼬리의 "(Verified, 날짜)". 조사 문서는 `Reported`를 더 쓴다. "repository notes"가 어디까지인지 정해져 있지 않다.
- 언어 규칙(`AGENTS.md:40`)은 스펙, 계획, 조사, 리뷰, PR 본문을 다루지 않는다. 실제로는 스펙과 조사는 한국어, 리뷰는 영어, 계획은 제목 영어·본문 한국어다.
- 계획 04는 2,502줄, 계획 10은 2,261줄, 계획 12는 1,807줄이다. 계획 04는 README, 런북, ADR 전체를 본문에 복사했다.
- `AGENTS.md:57`은 PR의 CI 통과를 Progress log에 적으라고 한다. CI가 끝난 뒤 다시 커밋해야 하는 순환이라 계획 10 리뷰에서 P1(R1-F1)으로 지적됐다.
- superpowers는 기본으로 `docs/superpowers/specs/`와 `docs/superpowers/plans/`에 쓴다. `AGENTS.md`에는 이 기본값을 덮는 문장이 없다.
- 문서 배치는 OCI 설계 §5(78-129행)에서 정했고 GCP 설계 §5가 "OCI와 같다"로 이어받았다. 문서 구조 자체를 다룬 ADR은 없다.
- ADR 0004는 결정 2(24-29행)에서 "문구·형식만 확인하는 테스트"를 새로 쓰지 않게 하고(26행), 결정 4에서 상대 링크 검사와 문서 경로 검사는 남겼다(31행).
- 문서는 2026-10-16에 ADR 6개, 스펙 6개(이 스펙과 함께 읽기의 스펙 제외), 계획 12개(active 1, backlog 1, completed 10), 런북 5개, 조사 1개(이 스펙의 근거 조사 제외), 리뷰 기록 10개와 단일 파일(ARCHITECTURE, 리뷰 README)이다.
- 지금 문서 검사는 세 가지다. `tests/repo.bats`의 상대 링크 검사(추적 중인 모든 Markdown, 코드 블록 밖의 Markdown 링크), 문서 경로 검사(`scripts/`, 스킬, `AGENTS.md` 안의 `docs/...md`만), `CLAUDE.md` = `@AGENTS.md` 검사다.
- `tests/helpers.bash:50-52`의 `frontmatter` 함수가 이미 YAML front matter를 awk로 읽는다(스킬 검사가 쓴다).

## 3. 문서 타입 레지스트리

`docs/README.md`를 문서 지도로 새로 만들고, 그 안의 `## 문서 타입` 표를 레지스트리로 쓴다. 사람과 에이전트는 이 표를 읽고 타입을 고른다. `tests/repo-docs.bats`와 `make new-doc`도 같은 표를 읽는다. 그래서 타입 정보는 이 한 곳에만 있다.

### 3.1 파일 이름 (D6)

모든 타입 문서의 이름은 한 양식을 따른다.

```text
<코드>-<YYYY-MM-DD>-<slug>.md            번호가 없는 타입
<코드>-<YYYY-MM-DD>-<번호>-<slug>.md     번호가 있는 타입(plan은 NN, adr은 NNNN)

예:
docs/specs/spec-2026-10-15-doc-system.md
docs/plans/plan-2026-10-15-13-doc-system-foundation.md
docs/decisions/adr-2026-10-13-0004-test-scope.md
docs/runbooks/rbk-2026-10-07-operations.md
```

- 날짜는 문서를 처음 만든 날이다. 이름에 날짜가 없던 기존 문서는 그 파일이 처음 커밋된 날(`git log --diff-filter=A --follow --format=%as`의 마지막 줄)을 쓴다(N4).
- `<slug>`는 `[a-z0-9]+(-[a-z0-9]+)*`다. 코드는 3~4자 영어 소문자이고 타입끼리 겹치지 않는다.
- 이름을 바꾸지 않는 단일 파일: `README.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, `docs/reviews/README.md`(N3).
- 얻는 것: 파일 이름만 봐도 타입과 날짜를 안다. 링크, 검색 결과, 에이전트가 받은 경로 목록처럼 폴더가 잘려 보이는 곳에서 특히 쓸모 있다. 검사와 생성 명령이 정규식 하나를 쓴다.
- 치르는 것: 폴더 이름과 코드가 겹친다. 기존 문서 이름과 참조가 모두 바뀌고, 지난 PR 본문·댓글의 GitHub 링크가 깨진다(11절). 폴더는 사람이 둘러보기 좋으므로 그대로 둔다.

### 3.2 레지스트리 표

| 타입 | 코드 | 번호 | 위치 | 상태 값 | 필수 키 | 새 문서 | 성격 | 언어 | 템플릿 |
|---|---|---|---|---|---|---|---|---|---|
| spec | spec | 없음 | `docs/specs/` | draft, approved, superseded | status, date | 허용 | 기록 | 한국어 | `.agents/skills/doc-authoring/assets/spec.md` |
| plan | plan | NN | `docs/plans/` | backlog, active, completed, dropped | status, spec | 허용 | 진행 중엔 갱신, 끝나면 기록 | 제목 영어, 본문 한국어 | `.agents/skills/doc-authoring/assets/plan.md` |
| adr | adr | NNNN | `docs/decisions/` | proposed, accepted, superseded, deprecated | status, date | 허용 | 기록 | 한국어 | `.agents/skills/doc-authoring/assets/adr.md` |
| runbook | rbk | 없음 | `docs/runbooks/` | current, retired | status, reviewed | 허용 | 계속 고침 | 한국어 | `.agents/skills/doc-authoring/assets/runbook.md` |
| research | rsch | 없음 | `docs/research/` | snapshot | status | 허용 | 기록(고정) | 한국어 | `.agents/skills/doc-authoring/assets/research.md` |
| review | rev | 없음 | `docs/reviews/` | final | status | 금지 | 동결 | 영어 | 없음 |

- `docs/ARCHITECTURE.md`는 표 밖의 단일 파일이다. front matter(`status: current`, `reviewed`)는 갖지만 이름 양식과 템플릿은 없다.
- 셀 안의 백틱과 앞뒤 공백은 파서가 지운다.
- `새 문서`가 금지인 타입(review)은 `make new-doc`이 거부한다. 기존 파일은 이름과 front matter만 맞추고 본문은 그대로 둔다. 리뷰 기록은 계획 09부터 PR 댓글이다(`docs/reviews/README.md:3`).
- 템플릿은 `doc-authoring` 스킬의 `assets/`에 둔다. 스킬 템플릿을 `skill-authoring/assets/`에 둔 ADR 0003의 선례를 따른다. 그래서 문서 작업에 필요한 규칙과 템플릿이 스킬 하나에 모인다.
- `docs/` 아래 파일은 단일 파일(N3)을 빼고 모두 표의 한 타입에 속해야 한다. 표에 없는 폴더(예: `docs/superpowers/`)에 파일이 생기면 검사가 실패한다.
- `docs/README.md`의 나머지 절은 한국어로 쓴다: 타입 고르는 법, 저장소 밖 문서(`README.md`, `AGENTS.md`, 스킬, PR 템플릿)의 위치, 새 타입을 더하는 법(7절).

## 4. 메타데이터

메타데이터는 파일 맨 위의 YAML front matter에 한 줄에 하나씩 쓴다. 키와 값은 영어 소문자이고 본문은 한국어다. GitHub은 front matter를 표로 보여 준다.

```markdown
---
status: approved
date: 2026-10-13
amended-by: docs/specs/spec-2026-10-13-github-pr-workflow.md
---

# 에이전트 기반 Git·리뷰 정책 — 설계
```

| 키 | 값 | 쓰는 타입 |
|---|---|---|
| `status` | 타입별 상태 값 | 모든 타입과 ARCHITECTURE |
| `date` | `YYYY-MM-DD`, 마지막으로 상태가 바뀐 날 | spec, adr |
| `spec` | 근거 문서의 저장소 기준 경로, 없으면 `none` | plan |
| `reviewed` | `YYYY-MM-DD`, 내용을 실제와 마지막으로 대조한 날 | runbook, architecture |
| `superseded-by` | 대체한 문서의 경로. `status: superseded`이면 필수 | spec, adr |
| `amended-by` | 일부를 대체한 문서의 경로 하나, 또는 `[경로, 경로]` | spec, adr |

- 키는 이 여섯 개만 쓴다. 스킬 front matter의 허용 키 검사(`tests/skills.bats`)와 같은 방식이다.
- 지금 본문 첫머리에 있는 "상태" 줄은 front matter로 옮기고 지운다. 상태를 한 곳에만 두기 위해서다. 구현 계획, 근거 조사, 대체 범위 같은 나머지 머리 줄은 본문에 남긴다.
- 문서를 대체하는 커밋은 두 문서를 함께 고친다. 새 문서는 본문의 "대체 범위"에 무엇을 대체하는지 적는다. 옛 문서에는 `status: superseded`와 `superseded-by`(전체) 또는 `amended-by`(일부)를 단다.

## 5. 타입별 규칙

### 5.1 spec

- 언제 쓰나: 여러 구성 요소의 관계나 다른 에이전트가 기대는 인터페이스를 바꿀 때. 브레인스토밍 → 스펙 → 계획 순서를 따른다.
- 템플릿 절: 목적과 범위(사용자 결정, 범위 밖, 완료 조건), 근거가 된 사실, 설계(필요한 만큼의 절), 보안, 테스트와 검증, 위험과 대응, 계획 분할, Open questions. 머리 줄에 구현 계획, 근거 조사, 대체 범위를 둔다. Google 설계 문서와 superpowers 스펙에서 가져왔고, 이 저장소의 기존 스펙들과 같은 순서다.
- 승인된 스펙은 구현 중에 발견한 오류를 그 자리에서 고칠 수 있다. 고친 사실은 계획의 Progress log에 남긴다. 결정을 바꾸려면 새 스펙이나 ADR을 쓰고 `amended-by`를 단다.

### 5.2 plan

- 계획 파일은 모두 `docs/plans/`에 둔다(D2). 상태는 폴더가 아니라 `status`가 말한다.

| 상태 | 언제 | 누가 |
|---|---|---|
| backlog | 스펙과 함께 쓸 때 | 계획 작성자 |
| active | 계획 브랜치의 첫 커밋 | 실행하는 에이전트 |
| completed | 모든 Task가 끝나고 리뷰를 부르기 전 | 실행하는 에이전트 |
| dropped | 하지 않기로 했을 때. 본문 맨 위에 이유 한 줄 | 사람의 결정에 따라 |

- 이유: 지금은 파일을 두 번 옮기는데, `main`의 active는 PR 구성에 따라 비기도 하고 차기도 하며(2절), 옮길 때마다 다른 문서의 경로가 낡는다. 진행 중인 계획은 그 계획 브랜치와 PR에서 보인다.
- 템플릿 절: 머리(Goal, Architecture, Spec, Sequence), Global Constraints, Review Focus, File Structure, `### Task N`(Files, Interfaces, `- [ ] **Step N:**`, 검증 명령), Progress log(`| 날짜 | 표기 | 내용 |`). 지금 계획들이 쓰는 superpowers 골격을 저장소 소유로 옮긴 것이다. superpowers 전용 줄("REQUIRED SUB-SKILL")은 도구 중립 문장으로 바꾼다.
- 제목은 영어, 본문은 한국어다. `Progress log`처럼 스킬과 `AGENTS.md`가 이름으로 가리키는 제목이 영어이기 때문이다.
- 계획 하나는 Task 3~5개다([GitHub PR 워크플로](spec-2026-10-13-github-pr-workflow.md) 1절 결정 4). 기존 파일을 통째로 복사하지 않고, 새로 쓰는 내용과 바뀌는 부분만 적는다. 끝낸 Step은 체크한다.
- 번호는 모든 로컬·원격 브랜치를 훑어 가장 큰 값 + 1로 정한다(`make new-doc`, 8.2절). 두 자리다(`scripts/check-git.sh:14`).

### 5.3 adr

- 언제 쓰나: 되돌리기 비싼 기술 결정, 대안을 검토한 결정, 기존 규칙을 바꾸는 결정.
- 템플릿 절: 맥락과 문제, 검토한 대안, 결정, 결과(확인 방법 포함). MADR 4.0.0의 필수 절을 한국어로 옮겼다.
- 수락한 ADR의 결정 문장은 고치지 않는다. 결정이 바뀌면 새 ADR로 대체한다. 측정 결과처럼 결정을 바꾸지 않는 사실은 뒤에 덧붙일 수 있다(ADR 0005의 `## VM 측정`에 계획 11의 측정을 덧붙인 방식, ADR 0006의 `## 이전 결과`).

### 5.4 runbook

- 사람이 따라 하는 절차다(Diátaxis의 how-to).
- 템플릿 절: 목적과 언제 쓰나, 사전 조건, 절차(번호), 확인, 되돌리기. 절차가 여러 개인 런북은 절차마다 `##`를 두고 그 아래에 같은 `###` 절을 둔다.
- 스크립트, 스킬, 다른 문서가 이름이나 번호로 가리키는 제목은 바꾸지 않는다. 2026-10-16에 확인한 것:
  - `rbk-2026-10-12-operations.md`: `## Incident log`, `## Exposure audit`, `## 비용 점검`, `## 정지된 VM`, `## 접속 방식 바꾸기 (Access mode change)`, `## 에이전트 연결`, `### 점검 기록 (Exposure audit)`
  - `rbk-2026-10-12-gcp-vm.md`: 절 번호. 스크립트와 스킬이 "section 8"처럼 번호(3, 5, 7, 8)로 가리키므로 번호를 바꾸거나 절을 끼워 넣지 않는다.
  - `rbk-2026-10-12-bootstrap.md`: `## ssh 모드 순서`와 bm-recover 스킬이 가리키는 단계 번호(1, 4)
  - 정확한 목록은 계획 14가 `grep`으로 다시 만든다.
- 절차를 실제로 따라 해 보거나 고치면 `reviewed`를 그날로 바꾼다.

### 5.5 research

- 특정 날짜의 조사 스냅샷이다. 쓴 뒤에는 고치지 않는다. 사실이 바뀌면 새 조사를 쓴다.
- 템플릿 절: 질문과 결론 요약, 방법, 발견(주장 문장을 제목으로), 시사점. 머리 줄에 기준 커밋과 표기 규칙을 둔다.

### 5.6 ARCHITECTURE와 README

- `docs/ARCHITECTURE.md`: 조감도, 코드 지도, 불변 조건, 경계와 교차 관심사(matklad). 파일은 링크보다 이름으로 가리킨다.
- 루트 `README.md`: 무엇인지, 빠른 시작, `docs/README.md` 링크. `AGENTS.md`의 규칙을 되풀이하지 않는다(지금 `README.md:21-30`과 `AGENTS.md:9-10`이 겹친다). 레지스트리 바깥이지만 `docs/README.md`가 위치를 안내한다.

### 5.7 AGENTS.md

- 지도로 쓴다. 명령, 불변 조건, 안전, Git, 문서·스킬로 가는 길만 둔다. 세부는 스킬과 `docs/README.md`로 보낸다.
- 24,000바이트를 넘지 않는다. Antigravity가 규칙 파일을 자르는 한도이고, 네 도구의 한도 중 가장 작다(근거 조사 §1). 지금은 8,278바이트다.

## 6. 공통 작성 규칙

### 6.1 언어

| 영어 | 한국어 |
|---|---|
| `AGENTS.md`, `CLAUDE.md`, 스킬, 코드·주석·스크립트 메시지·테스트 이름, front matter의 키와 값, 계획의 제목, 커밋 메시지, PR 제목과 본문, `.github/` 파일, `docs/reviews/`(동결) | `README.md`, `docs/README.md`, ARCHITECTURE, 런북, ADR, 스펙, 조사, 계획 본문 |

### 6.2 레이블

- 어휘: `Verified`(직접 확인), `Command`(실행한 명령), `Assumption`(확인하지 않은 전제), `Open question`(사람이 정할 일), `Reported`(2차 보도). `Reported`는 지금 조사 문서만 쓰는 것을 정식으로 받아들인다.
- 표기: 문단이나 목록 항목 첫머리에 `**Verified:**`처럼 굵게 쓰고 쌍점을 붙인다. 날짜가 필요하면 `**Verified (2026-10-15):**`. 표에서는 `표기` 열에 레이블만 쓴다.
- 범위: 한국어 문서에서 외부 시스템, 환경, 도구 동작에 대한 사실을 적을 때 쓴다. `README.md`, `AGENTS.md`, 스킬에는 쓰지 않아도 된다.
- 검사하지 않는다(결정 2). 기존 문서의 옛 표기는 계획 15가 이 형식으로 바꾼다(D1, 9절). 리뷰 기록과 조사 문서는 바꾸지 않는다(D9).

### 6.3 증거를 남기는 곳

- 계획 브랜치: Task마다 `make check` 결과와 핵심 명령 결과를 계획의 Progress log에 적는다. PR의 CI(`check`, `pr-rules`) 결과는 PR 본문의 Verification에 적는다(D4). PR 본문은 CI 뒤에 고쳐도 커밋이 생기지 않으므로 순환이 없다.
- work 브랜치: 계획이 없으므로 PR 본문의 Verification에 적는다. 결정은 ADR로 남긴다.
- 함께 바뀌는 곳: `AGENTS.md:41`, `AGENTS.md:57`(리뷰 규칙 3번), `branch-review` 스킬, `bm-upgrade` 스킬("active plan's Progress log or a new ADR"), `skill-authoring` 스킬("the plan's Progress log or an ADR").

### 6.4 경로 표기

- 저장소 안 문서는 상대 링크나 저장소 기준 경로를 백틱으로 적는다.
- 문서 경로 검사(8.3절)는 추적 중인 모든 Markdown에서 코드 블록 밖의 `docs/...md` 표기를 찾는다. 지금은 `scripts/`, 스킬, `AGENTS.md`만 본다.
- 아직 없는 파일을 예시로 들 때는 코드 블록 안에 쓴다. 코드 블록 밖의 경로는 모두 실제 파일이어야 한다.

### 6.5 도구 기본 경로보다 저장소 규칙이 우선

- `AGENTS.md`에 "스펙은 `docs/specs/`, 계획은 `docs/plans/`에 쓴다. 도구나 플러그인의 기본 경로(예: `docs/superpowers/`)보다 이 규칙이 우선한다"를 적는다. superpowers는 사용자 설정이 우선한다고 밝히고 있다(근거 조사 §2).
- 표에 없는 위치에 문서가 생기면 검사가 실패한다(8.3절 검사 2).

### 6.6 새 문서는 템플릿에서 시작

- `make new-doc`으로 만든다. 옆 문서를 복사하지 않는다. 기록 문서의 옛 형식이 퍼지지 않게 하기 위해서다.
- 템플릿의 빈칸은 `{{...}}`로 표시한다. 생성 명령이 날짜, 번호, slug를 채우고, 나머지는 작성자가 채운다. 남은 `{{`는 검사가 잡는다.

## 7. 새 문서 타입을 더하는 규칙

1. 기존 타입으로 안 되는지 먼저 본다. 위치나 생애 주기(상태 값)가 기존 타입과 다를 때만 새 타입을 만든다.
2. PR 하나에 레지스트리 행(겹치지 않는 3~4자 코드 포함), 템플릿(`doc-authoring/assets/<type>.md`), 필요하면 `AGENTS.md` 지도 한 줄을 함께 넣는다. 검사와 생성 명령은 표를 읽으므로 코드를 고칠 필요가 없다.
3. 상태 값이 기존 타입에 없는 새 생애 주기라면 ADR로 이유를 남긴다.
4. 타입을 그만 쓸 때는 `새 문서` 열을 `금지`로 바꾼다. 새 파일은 막히고 기존 파일은 남는다.
5. front matter 키를 더해야 하면 4절의 표와 검사의 허용 키 목록을 같은 PR에서 고친다.

## 8. 강제

### 8.1 `doc-authoring` 스킬

- `.agents/skills/doc-authoring/SKILL.md`(영어)와 `assets/`의 템플릿 다섯 개(spec, plan, adr, runbook, research). `.claude/skills/doc-authoring` 심볼릭 링크를 둔다.
- 내용: 레지스트리를 읽고 타입을 고르는 법, `make new-doc`, 메타데이터와 상태 바꾸기, 대체, 언어와 레이블, 증거 위치, 새 타입 더하기. 표의 내용은 되풀이하지 않고 `docs/README.md`를 가리킨다.
- `tests/skills.bats`의 규칙("Use when", 1,024자, 500줄, 모든 번들 파일을 SKILL.md에 언급)을 지킨다. `AGENTS.md`의 `## Skills`와 `README.md`의 스킬 목록에 더한다.
- `AGENTS.md`의 `## Skills`에 "문서를 만들거나 상태를 바꾸거나 새 문서 타입을 더할 때: `doc-authoring`"을 더한다.

### 8.2 `make new-doc`

- `make new-doc TYPE=<type> SLUG=<slug>`가 `scripts/create-doc.sh`를 실행한다. 스크립트 이름은 스크립트·테스트 구조 설계의 `<동사>-<대상>` 규칙을 따른다.
- 동작:
  1. 레지스트리에서 타입 행을 읽는다. 없는 타입과 `새 문서`가 금지인 타입은 거부한다.
  2. 날짜는 오늘(`YYYY-MM-DD`)이다. `NN`과 `NNNN`은 `git for-each-ref refs/heads refs/remotes`의 모든 브랜치에서 그 위치의 번호를 모아 가장 큰 값 + 1이다. 이름을 바꾸기 전의 브랜치도 있으므로 옛 이름(`YYYY-MM-DD-NN-`, `NNNN-`)과 새 이름의 번호를 모두 읽는다. 결과가 맞으려면 먼저 `git fetch origin`을 해야 한다고 출력한다.
  3. 템플릿을 복사하며 `{{date}}`, `{{number}}`, `{{slug}}`를 채운다. 파일이 이미 있으면 덮어쓰지 않고 실패한다.
  4. 만든 경로를 출력한다.
- 스크립트는 저장소 스크립트 규칙(`AGENTS.md` Invariants, 함께 읽기의 스펙)을 따르고, 테스트를 먼저 쓴다.

### 8.3 검사

새 `tests/repo-docs.bats`가 레지스트리를 읽어 반복문으로 검사한다(ADR 0004 결정 3). 파일 이름은 스크립트·테스트 구조 설계의 규칙(저장소 전체 검사는 `repo-` 접두어)을 따른다. 실패 메시지는 파일, 어긋난 값, 허용 값, 고치는 곳(`docs/README.md`)을 함께 출력한다.

1. 레지스트리 표를 읽을 수 있고, 코드가 겹치지 않으며, 새 문서를 허용하는 타입마다 템플릿 파일이 있다.
2. `docs/` 아래 모든 파일은 단일 파일(N3)을 빼고 정확히 한 타입의 위치와 파일 이름(3.1절)에 맞는다.
3. front matter: 있다, 허용 키만 쓴다, 필수 키가 있다, `status`가 그 타입의 값이다, 날짜는 `YYYY-MM-DD`다, `spec`·`superseded-by`·`amended-by`의 경로가 있다, `superseded`이면 `superseded-by`가 있다.
4. 번호가 겹치지 않는다(ADR의 `NNNN`, 계획의 `NN`).
5. 타입 문서에 `{{`가 남아 있지 않다.
6. 추적 중인 모든 Markdown의 코드 블록 밖 `docs/...md` 경로가 있다. `tests/repo.bats`의 기존 문서 경로 검사를 이 파일로 옮기고 범위를 넓힌다.

`tests/repo.bats`에 두 가지를 더한다.

7. `.gemini/settings.json`의 `context.fileName`에 `AGENTS.md`가 있다. 기존 `CLAUDE.md` 검사와 같은 종류다.
8. `AGENTS.md`는 24,000바이트 이하다.

### 8.4 새 ADR: 구조 검사의 범위

- ADR 0004 결정 2의 "문구·형식만 확인하는 테스트" 금지를 일부 대체한다. ADR 0004에는 `amended-by`를 단다.
- 허용하는 구조 검사:
  - 위치와 파일 이름
  - 메타데이터의 키와 값
  - 경로가 가리키는 파일의 존재
  - 채우지 않은 템플릿 표지
  - 에이전트가 읽는 도구 설정 파일(`CLAUDE.md`, `.gemini/settings.json`)
  - 도구가 자르는 크기 한도
  - 짝 파일의 존재(스크립트와 테스트, 함께 읽기의 스펙)
- 계속 금지: 섹션 이름, 문장, 레이블, 언어를 확인하는 테스트와, 문서 문구를 되풀이하는 변경 감지 테스트.
- 이유: 2절의 문제(상태 표기, 낡은 경로, active 경로)는 모두 메타데이터와 위치 문제였고, 네 도구 중 하나가 템플릿을 무시해도 이 검사가 잡는다. 문장을 되풀이하는 테스트를 막으려던 ADR 0004의 취지는 그대로 지킨다.

## 9. 소급 적용 (D1)

가능한 만큼 최대한 바꾼다. "가능하지 않다"는 바꾸면 기록이 사실과 달라지는 경우뿐이다.

| 대상 | 바꾸는 것 | 계획 |
|---|---|---|
| 모든 타입 문서(단일 파일 제외) | 3.1절의 이름으로 `git mv`, 저장소 안 모든 참조 갱신 | 14 |
| 모든 계획 | `docs/plans/{backlog,completed}/`에서 `docs/plans/`로 옮김 | 14 |
| 모든 타입 문서와 ARCHITECTURE | front matter 추가, 본문의 상태 줄 삭제, 낡은 경로와 상태 문구(2절의 예) 수정 | 14 |
| 리뷰와 조사를 뺀 모든 타입 문서, ARCHITECTURE, 루트 README | 레이블 표기 통일(6.2절), `AGENTS.md`와 겹치는 문장 정리(README). 절 구성은 그대로 둔다(D9) | 15 |
| 리뷰 | 이름과 front matter(`status: final`)만. 본문은 그때의 영어 기록 그대로 | 14 |

**바꾸지 않는 것** (바꾸면 기록이 사실과 달라진다)
- 증거: 명령, 출력, 커밋 SHA, 날짜, 인용, 측정값
- 결정의 내용: ADR의 결정 문장, 스펙의 사용자 결정
- 완료 계획의 체크박스: 어떤 Step을 실제로 했는지 기록이 없으면 체크하지 않는다. 완료 여부는 front matter의 `completed`가 말한다.
- 계획 본문에 복사된 파일 내용(계획 04, 10): 그때 계획한 내용의 기록이다.
- 기록 문서 안의 옛 스크립트 이름: 스크립트·테스트 구조 설계가 스크립트 이름을 바꾸지만, 기록 문서에는 그때의 실제 이름이 맞다.
- 스크립트, 스킬, 다른 문서가 이름이나 번호로 가리키는 런북 제목(5.4절)

**참조 갱신**
- 이름을 바꾸면 고칠 곳: 문서 안의 링크와 백틱 경로, `AGENTS.md`, 스킬, `.github/pull_request_template.md`, 스크립트 머리 주석의 스펙 경로(`check-git.sh:2` 등), 스크립트 메시지의 런북 경로(`access-check.sh`, `bootstrap-vm.sh`, `lib/common.sh`, `remote/bootstrap.sh`, `status.sh`, `tunnel.sh`, `verify-vm.sh`), 테스트의 런북 경로(`cloud_neutral.bats`, `vm_ops.bats`), CI 워크플로 주석. 정확한 목록은 계획 14가 `git grep`으로 다시 만든다.
- 계획 폴더를 합치면 함께 바뀌는 곳: `AGENTS.md:5`, `AGENTS.md:46`(Map), GCP 설계 4행, git-workflow 스킬 Start 3, `review-and-merge.md:7`, `.github/pull_request_template.md:7`, `branch-review` 스킬, `scripts/review.sh`의 계획 리뷰 문구.
- 지워진 문서를 가리키는 기록 문서의 경로는 현재 경로로 고친다. 대상이 없으면 경로 표기를 풀어 쓴다.

**본문을 옮길 때 내용을 잃지 않게**
- 계획 15는 절을 옮기지 않는다(D9). 레이블 커밋은 낱말을 바꾸지 않는다. 바뀌는 것은 레이블과 그 괄호 내용의 위치, 레이블이 덮는 문장을 따로 떼는 줄바꿈과 목록 기호(표에서는 새 행), 그때 바뀌는 연결 어미, 레이블이 술어였던 문장의 술어, 변형 레이블(`**Assumption 확인:**`)을 옮길 때 레이블 뒤에 남기는 괄호 말(`(이 Step에서 확인)`)뿐이다(`git diff --word-diff`로 확인).
- 옛 형식이 다시 퍼지는 문제는 템플릿, 스킬의 "옆 문서를 복사하지 않는다", `make new-doc`으로 막는다(6.6절).

## 10. 계획 분할과 순서

| 계획 | 범위 | 시작 조건 |
|---|---|---|
| 13 문서 체계 기반 | `.gemini/settings.json`과 `tests/repo.bats`의 두 검사(8.3절 7·8), `docs/README.md`(레지스트리), 템플릿 다섯 개, `doc-authoring` 스킬, `scripts/create-doc.sh`와 `make new-doc`과 테스트, 새 ADR, `AGENTS.md`의 지도·언어·레이블·경로 우선 문장 | 계획 11 병합 뒤(D5). 충족됨 |
| 14 이름·메타데이터 소급과 검사 | 모든 문서 이름 변경과 참조 갱신, 계획 폴더 통합, front matter, 낡은 경로, `tests/repo-docs.bats`(8.3절 1~6), 6.3절의 증거 위치 변경과 함께 바뀌는 스킬·PR 템플릿·`AGENTS.md` | 계획 13과 계획 12 결과 PR(Task 8) 병합 뒤 |
| 15 본문 소급 | 9절 표의 본문 행: 레이블 통일, README의 중복 정리(절 구성은 D9로 제외) | 계획 14 병합 뒤 |

- 계획 11(PR #6, `4c84dba`)과 계획 12의 문서(PR #7, `4a184f1`)와 코드(PR #8, `87e86d4`)는 병합됐다.
- 계획 12의 Task 8(VM 이전)은 결과 PR(`plan/12-access-mode-migration`)로 남는다. 그 PR은 계획 12 파일을 completed로 옮기고 ADR 0006, 접속 방식 설계, `rbk-2026-10-12-operations.md`, `rbk-2026-10-12-gcp-vm.md`를 고친다. 계획 14가 같은 파일의 이름을 바꾸므로 계획 14는 그 PR이 병합된 뒤에 시작한다. 계획 13은 기존 문서를 옮기지 않으므로 지금 시작할 수 있다.
- 계획 13 병합부터 계획 14 병합까지는 두 규칙이 섞인다. 새 문서는 `make new-doc`으로 새 이름을 쓰고, 기존 문서는 옛 이름과 폴더에 둔다. 문서 검사(8.3절 검사 1~6)는 계획 14가 켠다. 계획 13의 새 ADR과 계획 14의 계획 파일도 새 이름으로 만든다. `docs/README.md`는 이 기간을 한 줄로 밝히고, 계획 14가 그 줄을 지운다. 계획 13의 계획 파일은 레지스트리가 생기기 전에 쓰므로 옛 규칙(`docs/plans/backlog/`)을 따르고, 계획 14가 함께 옮긴다.
- 계획 14의 이름 변경 목록은 시작할 때 `git grep`으로 다시 만든다.
- 2026-10-16 현재 계획 번호는 12까지 쓰였다(로컬·원격 브랜치 전부의 `docs/plans`를 `git ls-tree`로 확인). 13~15는 이 스펙, 16·17은 스크립트·테스트 구조 설계가 쓴다. ADR은 0006까지 있으므로 새 ADR은 0007이다. 번호는 모두 계획을 쓸 때 다시 확인한다.

## 11. 위험과 대응

| 위험 | 대응 |
|---|---|
| `AGENTS.md` 수정이 자동 모드에서 "Instruction Poisoning"으로 막힘(계획 10 때 있었음) | 바꿀 문장을 사용자에게 먼저 보여 주고 승인을 받는다 |
| 계획 12 결과 PR과 같은 파일을 고쳐 충돌 | 10절의 순서. 계획 14 전에 `git fetch`와 `git grep`으로 대상 목록을 다시 만든다 |
| 레지스트리 표 형식이 깨져 검사·생성이 모두 멈춤 | 파서가 어느 행이 왜 틀렸는지 출력한다. 표 형식은 `doc-authoring` 스킬에 예시와 함께 적는다 |
| 기록 문서에 옛 경로가 많아 경로 검사가 대량 실패 | 계획 14의 첫 Task가 `git grep`으로 목록을 만들고 일괄 고친다 |
| 검사가 급한 수정을 막음 | 메타데이터와 위치만 보므로 고치는 데 한 줄이면 된다. 실패 메시지가 고칠 곳을 알려 준다 |
| 레지스트리를 무시하고 플러그인 기본 경로에 문서를 씀 | 6.5절의 `AGENTS.md` 문장과 8.3절 검사 2 |
| 템플릿과 레지스트리가 어긋남 | 검사 1(템플릿 존재)과 `make new-doc`의 테스트가 실제 템플릿으로 문서를 만들어 검사 3을 통과하는지 본다 |
| 이름 변경으로 지난 PR 본문·댓글의 GitHub 링크가 깨짐 | 받아들인다. 저장소 안 참조는 모두 고치고, 파일 이력은 `git log --follow`로 이어진다 |
| 본문을 템플릿에 맞추다 내용을 잃음 | 9절의 커밋 분리와 줄 목록 비교 |

## 12. Open questions

1. (결정됨, 2026-10-16) N1~N4(1절): 타입 코드, 번호 위치, 이름을 바꾸지 않는 단일 파일, 날짜가 없던 문서의 날짜는 초안대로 한다.
2. (결정됨, 2026-10-15) 계획 템플릿에 ExecPlan 절을 더하지 않는다(D7).
3. (결정됨, 2026-10-15) `docs/reviews/`는 그 자리에 둔다(D8). 파일 이름은 D1에 따라 새 양식으로 바꾼다.
