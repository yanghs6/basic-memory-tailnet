---
status: backlog
spec: docs/specs/spec-2026-10-23-q3jxc77k-doc-ids-and-draft-board.md
---

# e3svnr3h Document IDs and Draft Board Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 모든 문서가 무작위 8자 ID로 구분되고, 승인 전 초안은 Basic Memory 초안 보드에 있으며, 기존 문서·git 이력·PR #1~#20까지 새 이름을 쓴다.

**Architecture:**
- `scripts/lib/docs.sh`가 ID를 만들고 `make new-id`·`make new-doc ID=`가 쓴다. 문서 검사, 브랜치·트레일러 검사가 ID를 받는다.
- 기존 문서는 일회용 이전 스크립트로 이름과 인용을 바꾸고, 대응표를 [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md) 부록에 남긴다.
- 이력은 일회용 재작성 스크립트가 `main`을 커밋 순서대로 다시 만들어 경로·내용·메시지·SHA 인용을 바꾸고, 에이전트가 force-push한다(사용자 1회 허가).

**Spec:** `docs/specs/spec-2026-10-23-q3jxc77k-doc-ids-and-draft-board.md` (§3.1~§3.6, §5, §7). 결정: `docs/decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md`.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 이 계획·스펙·ADR을 담은 docs PR이 병합됐다.
- **Reported (2026-10-23, 감독 세션이 전달한 사용자 결정):** 이 개편이 모든 계획보다 먼저다. 다른 계획의 코드 작업은 이 계획의 코드 PR이 병합된 뒤 시작한다.
- Task 2를 시작하기 전에 감독 세션이 다른 세션의 열린 PR과 브랜치를 정리한다(이름 변경과 충돌하므로).
- Task 4는 코드 PR이 병합되고, 스펙 §3.5의 조건을 모두 만족하고, 사용자가 날짜를 정한 뒤 한다.

## 배경

- **Verified (2026-10-23, 읽기 전용 전수 조사):** 번호에 기대는 곳은 스펙 §2에 있다. 도구는 `scripts/lib/docs.sh:95-112`, `scripts/create-doc.sh:31-46`, 검사는 `tests/repo-docs.bats:9,88-98,120-132`, `scripts/check-git.sh:12`, `scripts/lib/git.sh:19`, `scripts/check-pr.sh:32-40`이다. 템플릿의 `{{number}}`는 `plan.md:6,17,23,39`, `adr.md:6`에 있다.
- **Verified (2026-10-26):** `main`은 커밋 158개, merge 커밋 12개다. PR은 #1~#20이고, 머신 계정 코멘트 87개와 GitGuardian 코멘트 3개가 있다. 룰셋은 `bypass_actors`가 비어 있어 Enforcement를 꺼야 push할 수 있다(`docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md` "긴급 변경").
- 사용자 결정(스펙 §1): 고유 ID, 초안은 Basic Memory, 소급 적용, 가급적 이력 재작성, 에이전트가 force-push까지(이번 한 번, `AGENTS.md`는 고치지 않음), 만료 기본값 없음, 바꿀 수 있는 것은 모두 재작성.

## Global Constraints

- 스크립트 규칙(`AGENTS.md` Invariants): `#!/usr/bin/env bash` 다음 줄 `set -euo pipefail`, `scripts/lib/` 라이브러리 source, 고칠 방법을 담은 `die`, macOS bash 3.2, `x="$(fn)"` 뒤 `|| exit 1`, 이름 붙인 상수.
- 테스트를 먼저 쓴다. 범위는 `docs/decisions/adr-2026-10-13-a878ypj5-test-scope.md`를 따른다. 인터페이스가 바뀌어 기존 기대값을 고칠 때는 커밋 본문에 이유를 적는다.
- ID 알파벳은 `0123456789abcdefghjkmnpqrstvwxyz`, 길이 8이다. 정규식은 `[0-9a-hjkmnp-tv-z]{8}`이다.
- 문서 이름은 `<코드>-<YYYY-MM-DD>-<ID>-<slug>.md`, front matter `id`는 필수이고 이름의 ID와 같다.
- 이 계획의 브랜치는 `plan/26-doc-ids`, 모든 커밋의 트레일러는 `Plan: 26`이다. 이 계획 파일의 이름이 Task 2에서 바뀌어도 트레일러는 그대로 두고, Task 4의 재작성이 새 ID로 바꾼다.
- 일회용 스크립트(이전, 재작성)는 저장소에 넣지 않는다. 세션 스크래치 디렉터리에 두고, 실행 명령과 결과를 Progress log에 남긴다.
- Progress log와 PR에는 VM의 IP, 로컬 절대 경로, 세션 id를 쓰지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 26`, `Task: <N|review|none>`.

## Review Focus

1. slug 안의 숫자(`ipv6-egress`, `plan-01-local-foundation` 같은 리뷰 slug, 날짜)를 번호로 잘못 바꾸지 않는다. Task 2의 이전 스크립트가 경로와 대응표의 정확한 패턴만 바꾸고, 남은 후보 grep을 사람이 확인한다.
2. 이름을 손으로 `git mv`하면서 front matter `id`를 같이 바꾸지 않으면, `make check`가 두 값을 모두 담은 메시지로 실패한다. Task 2의 `repo-docs.bats` 테스트가 고정한다.
3. 대문자, `i`·`l`·`o`·`u`, 7자나 9자 ID를 쓴 브랜치와 트레일러는 거부된다. Task 1의 `check-git.bats`·`check-pr.bats` 표가 고정한다.
4. 재작성에서 merge 커밋의 두 부모, 파일 모드(실행 권한), 심볼릭 링크가 그대로다. Task 4의 검증 1과 시험 clone 실행이 고정한다.
5. 계획 02~05의 옛 번호를 그 커밋 시점의 번호로 바꾼다. Task 4가 번호를 바꾼 커밋 전후의 표본 diff를 사람이 확인한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `scripts/lib/docs.sh`, `tests/lib-docs.bats` | `new_doc_id`, `doc_id_taken`, `DOC_ID_PATTERN`, 타입 표 파서(`번호` 열 제거) | 1, 2 |
| `scripts/create-doc.sh`, `tests/create-doc.bats`, `.agents/skills/doc-authoring/assets/*.md` | `ID=` 처리, `{{id}}` 채움, 템플릿의 `id` 키, 번호 코드 제거 | 1 |
| `scripts/create-id.sh`, `tests/create-id.bats` | `make new-id` | 1 |
| `Makefile` | `new-id`, `new-doc ID=` | 1 |
| `scripts/lib/git.sh`, `scripts/check-git.sh`, `scripts/check-pr.sh` 및 각 bats | 브랜치·`Plan` 패턴(전환 기간엔 두 형식) | 1, 5 |
| `tests/repo-docs.bats` | 이름의 ID, front matter `id` 일치·유일, `id` 허용 키 | 1, 2 |
| `docs/README.md` | 타입 표와 이름 규칙 | 2 |
| `docs/**/*.md` 전부 | 이름 변경, `id` 추가, 인용 갱신 | 2 |
| `docs/decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md` | 대응표 부록, `accepted` | 2 |
| `tests/repo-cloud-neutral.bats`, 런북 경로를 쓰는 스크립트 | 새 런북 이름 | 2 |
| `AGENTS.md`, `.agents/skills/{doc-authoring,git-workflow,branch-review,script-authoring}/…`, `.claude/agents/branch-reviewer.md`, `.github/pull_request_template.md`, `scripts/review-branch.sh` | 규칙, 초안 보드 흐름, ID 표기 | 3 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/26-doc-ids` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: ID tooling and checks that accept both forms

**Files:**
- Create: `scripts/create-id.sh`, `tests/create-id.bats` (`make new-script NAME=create-id`)
- Modify: `scripts/lib/docs.sh`, `scripts/create-doc.sh`, `Makefile`(`new-id`, `new-doc`의 `ID`), `scripts/lib/git.sh:19`, `scripts/check-git.sh:12,34,38,57`, `scripts/check-pr.sh:32-40`, `tests/repo-docs.bats:9`, `.agents/skills/doc-authoring/assets/*.md`(front matter `id: {{id}}`, `{{number}}` → `{{id}}`)
- Test: `tests/lib-docs.bats`, `tests/create-doc.bats`, `tests/create-id.bats`, `tests/check-git.bats`, `tests/check-pr.bats`, `tests/lib-git.bats`, `tests/repo-docs.bats`

**Interfaces:**
- Produces (`scripts/lib/docs.sh`):
  - `DOC_ID_PATTERN='[0-9a-hjkmnp-tv-z]{8}'`
  - `random_doc_id -> <8자>`: `LC_ALL=C tr -dc` 방식으로 `/dev/urandom`에서 만든다. 테스트가 함수를 다시 정의해 값을 고정할 수 있게 분리한다.
  - `doc_id_taken ROOT ID -> exit 0이면 이미 쓰임`: `doc_paths`의 모든 `docs/` 아래 이름에서 `-<ID>-`를 찾는다.
  - `new_doc_id ROOT -> 쓰이지 않은 ID`: `random_doc_id`를 최대 `DOC_ID_MAX_TRIES`(이름 붙인 상수)번 다시 부른다.
- Produces (Make): `make new-id`는 ID 하나를 출력한다. `make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]`.
- Produces (`scripts/lib/git.sh`): `PLAN_PATTERN`이 `^([0-9]{2}|[0-9a-hjkmnp-tv-z]{8}|none)$`를 받는다. `LEGACY_PLAN_PATTERN`을 따로 두어 Task 5에서 지울 곳을 한 곳으로 모은다. `BRANCH_PATTERN`도 같은 방식이다.

- [ ] **Step 1: 실패하는 테스트 작성.**
  - `lib-docs.bats`:
    - "random_doc_id prints 8 characters from the id alphabet": 100번 뽑아 모두 `DOC_ID_PATTERN`에 맞는지 본다.
    - "new_doc_id skips an id that a file on another branch already uses": `random_doc_id`를 첫 번째는 쓰인 ID, 두 번째는 새 ID를 내도록 다시 정의하고, 원격 추적 브랜치에 그 ID의 파일을 둔다.
    - "new_doc_id gives up after DOC_ID_MAX_TRIES taken ids": 실패하고 원인을 알린다.
  - `create-doc.bats`:
    - `make new-doc with ID= names the file and fills {{id}} with that id`: 만든 문서의 front matter에 `id: <그 ID>`가 있고, 자동으로 채우는 자리표시자(`{{date}}`, `{{id}}`, `{{slug}}`, `{{number}}`)가 남지 않는다. 작성자가 채우는 `{{제목}}` 같은 칸은 그대로다. 모든 타입에 대해 확인한다.
    - "make new-doc rejects a malformed or already used ID"
    - 기존 번호 테스트(`:48-83`)는 "without ID= a new unused id is used"로 바꾼다. 커밋 본문에 이유(인터페이스 변경)를 적는다.
  - `create-id.bats`: "prints one id and nothing else".
  - `check-git.bats`·`check-pr.bats`·`lib-git.bats`: 표에 `plan/k7m2x9qa-x`, `Plan: k7m2x9qa`를 허용 사례로, `plan/K7M2X9QA-x`, `plan/k7m2x9q-x`, `plan/k7m2x9qai-x`, `Plan: k7m2x9qi`를 거부 사례로 더한다. 옛 형식 `plan/26-x`, `Plan: 26`도 아직 허용 사례다.
  - `repo-docs.bats`: `ALLOWED_KEYS`에 `id`가 있다. 이름이 새 형식인 문서는 front matter `id`가 이름의 ID와 같아야 한다(옛 형식 이름은 Task 2 전까지 검사하지 않음).
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 테스트만 실패한다.
- [ ] **Step 3: 최소 구현.** Interfaces대로 구현한다.
  - `create-doc.sh`는 숫자 열이 있는 타입에서도 번호 대신 ID를 쓴다(타입 표의 `번호` 열은 Task 2에서 지운다). 머리 주석과 사용법 줄을 고친다.
  - 템플릿(`skill-authoring` 스킬로 편집): 모든 템플릿 front matter에 `id: {{id}}`를 더하고, `plan.md`·`adr.md`의 `{{number}}`를 `{{id}}`로 바꾼다. Task 2가 `id`를 필수로 만들기 전에 새 문서가 그 규칙을 지키게 하기 위해서다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: give new documents random ids and accept id branches and trailers" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 26" --trailer "Task: 1"`

### Task 2: Rename every document and update every reference

**Files:**
- Modify: `docs/` 아래 모든 타입 문서(이름, front matter `id`, 본문 인용), `docs/README.md`(타입 표, 이름 규칙), `scripts/lib/docs.sh`(`DOC_TYPES_HEADER`), `tests/repo-docs.bats`, `tests/lib-docs.bats`, `tests/repo-cloud-neutral.bats:6,31`, 런북 경로를 쓰는 스크립트(`scripts/bootstrap-vm.sh:55,57`, `scripts/verify-vm.sh:111,113,134`, `scripts/lib/vm.sh:53`), 스킬·`AGENTS.md`·`README.md`·`docs/ARCHITECTURE.md`의 경로와 번호, `.github/workflows/*.yml` 주석, `tests/repo-config.bats:5`
- Modify: [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md)(대응표 부록, `status: accepted`, `date`)

**Interfaces:**
- Consumes: Task 1의 `new_doc_id`(ID 할당), `DOC_ID_PATTERN`.
- Produces: 대응표(옛 타입·번호, 옛 이름, 새 ID, 새 이름). Task 4의 재작성 스크립트가 이 표를 입력으로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성.** `repo-docs.bats`:
  - 모든 타입 문서의 이름이 `<코드>-<날짜>-<ID>-<slug>.md`다.
  - front matter `id`가 이름의 ID와 같다. 다르면 두 값을 모두 담아 실패한다.
  - 같은 ID가 두 파일에 있으면 실패한다.
  - 타입 표에 `번호` 열이 없다(`lib-docs.bats`의 표 행도 바꾼다).
  - 번호 중복 검사(`:88-98`)와 번호 열 검사(`:78`)는 지운다. 이유를 커밋 본문에 적는다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 이름 테스트가 문서 62개를 실패로 나열한다.
- [ ] **Step 3: 이전 스크립트 작성과 실행(스크래치).**
  - 문서마다 `new_doc_id`로 ID를 받아 대응표를 만든다. 이 계획, 스펙, [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md)도 포함한다.
  - `git mv`로 이름을 바꾸고 front matter 첫 키 다음에 `id`를 넣는다. 리뷰 기록 slug의 `plan-NN-`는 뺀다.
  - 저장소 전체(문서, 스킬, `AGENTS.md`, `README.md`, 스크립트, 테스트, 워크플로)에서 다음을 바꾼다. 코드 블록 안도 포함한다.
    - 옛 경로(상대 링크, 백틱 경로, front matter 값)를 새 경로로 바꾼다.
    - 대응표의 정확한 패턴("계획 NN", "ADR NNNN", `Plan: NN`, `plan/NN-…`, 계획 제목 `# NN`, ADR 제목 `# ADR NNNN:`)을 slug와 ID 표기로 바꾼다. 사람이 읽는 인용은 "<slug> 계획", "<slug> ADR"이다.
  - 바꾸지 않는 패턴 목록을 둔다: 개수("ADR 6개"), 분수("계획 1/5"), 연도, "결정 N", "Task N", 리뷰 ID, PR "#NN".
  - 스크립트는 바꾼 곳 수와, 남은 숫자 후보(`계획 [0-9]`, `ADR [0-9]`, `plan/[0-9]`, `Plan: [0-9]`)의 목록을 출력한다.
- [ ] **Step 4: 사람 확인.** 남은 후보 목록을 사용자와 함께 보고, 번호 인용이면 고치고 아니면 그대로 둔다. 목록과 처리를 Progress log에 적는다.
- [ ] **Step 5: 대응표와 규칙.**
  - [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md) 부록에 대응표를 적는다. 옛 이름은 경로·확장자 없이 날짜·번호·slug를 띄어 쓴다.
  - `docs/README.md`의 타입 표에서 `번호` 열을 지우고 이름 규칙 문단을 ID 기준으로 고친다. `DOC_TYPES_HEADER`를 맞춘다.
  - [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md)을 `status: accepted`로 바꾼다.
- [ ] **Step 6: 통과 확인.**
  - Run: `make check`. Expected: exit 0.
  - Run: 남은 후보 grep(Step 3과 같은 패턴)과 옛 이름 grep. Expected: [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md) 부록과 Step 4에서 남기기로 한 곳 밖에서 0건. 결과를 Progress log에 `Verified`로 적는다.
- [ ] **Step 7: 커밋.** 이름 변경 커밋과 인용 갱신 커밋을 나눈다. 리뷰어가 `git log --follow`로 이름 변경을 볼 수 있게 하기 위해서다. 트레일러는 `Plan: 26`, `Task: 2`.

### Task 3: Rules, skills, templates and the draft board flow

**Files:**
- Modify: `AGENTS.md`(Git 절, Notes 절, 초안 보드 한 줄), `.agents/skills/doc-authoring/SKILL.md`, `.agents/skills/git-workflow/SKILL.md`와 `references/review-and-merge.md`, `.agents/skills/branch-review/SKILL.md`, `.agents/skills/script-authoring/SKILL.md:66`, `.claude/agents/branch-reviewer.md`, `.github/pull_request_template.md`, `scripts/review-branch.sh:8,27,128`, `scripts/post-review.sh:4,17`

**Interfaces:**
- Consumes: `make new-id`, `make new-doc ID=`, 새 이름 규칙.
- Produces: `doc-authoring` 스킬의 초안 흐름 절(스펙 §3.3). 프로젝트 키를 얻는 명령(`git remote get-url origin` 정규화)과 기기 이름(`BM_MEMORY_DEVICE` 또는 `hostname -s` 소문자)을 그대로 적는다.

- [ ] **Step 1: 스킬.** `skill-authoring` 스킬로 편집한다. 템플릿은 Task 1에서 이미 바꿨다.
  - `doc-authoring`에 초안 흐름을 쓴다. 순서는 보드 조회, `make new-id`, `write_note`, SilverBullet 검토, 승인 뒤 `make new-doc ID=`, 노트 갱신이다.
  - 쓰기 규칙(주인만 씀, 고치기 전 다시 읽기, 만료 없음, 삭제는 승인 뒤)과 터널이 꺼졌을 때의 동작을 함께 쓴다.
- [ ] **Step 2: 규칙.** `AGENTS.md`를 스펙 §3.6대로 바꾼다. `tests/repo-config.bats:135`의 크기 테스트가 통과해야 한다.
- [ ] **Step 3: 통과 확인.** Run: `make check`. Expected: exit 0. `tests/repo-skills.bats`가 템플릿 이름을 확인한다.
- [ ] **Step 4: 초안 보드 확인(사용자와 함께, 완료 조건 7).**
  - 사용자가 `make tunnel`을 켠다.
  - 이 세션이 시험 초안 노트(`agent-drafts/yanghs6-basic-memory-tailnet/spec-<ID>-draft-board-check`)를 `write_note`로 만든다.
  - 다른 벤더 에이전트(`codex exec </dev/null`, 강도 low)가 `search_notes(metadata_filters={"project": …, "draft": true})`로 그 노트를 찾는다.
  - 사용자가 SilverBullet에서 같은 노트를 본다(스펙 §2의 Assumption).
  - 결과를 Progress log에 적고, 사용자 OK 뒤 시험 노트를 지운다.
- [ ] **Step 5: 커밋.** `git commit -m "docs: move drafts to the Basic Memory draft board and document ids in the rules and skills" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 26" --trailer "Task: 3"`

### Code PR: review and merge

- [ ] PR 본문 Verification에 Task 1~3의 `make check`, 남은 후보 grep, 초안 보드 확인, CI(`check`, `pr-rules`)를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰(`make review ... </dev/null`)를 하고, 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

### Task 4: History rewrite (agent, once, OK at every step)

**Files:**
- 저장소 파일은 바꾸지 않는다. 결과는 Task 5의 결과 PR에 적는다.

- [ ] **Step 1: 조건 확인.** 열린 PR 0개(`gh pr list --state open`), 감독 세션이 확인한 다른 세션의 브랜치·worktree 0개, 사용자가 정한 날짜. 하나라도 아니면 멈추고 사용자에게 알린다. 그대로 대응표로 끝낼지 사용자가 정한다.
- [ ] **Step 2: clone 준비.** 세션 스크래치에 `git clone --mirror`를 두 개(`backup`, `work`) 만든다. `backup`은 끝까지 손대지 않는다.
- [ ] **Step 3: 재작성 스크립트 작성(스크래치).**
  - 입력: [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md) 대응표, Task 2의 치환 규칙, 시대별 번호 대응(계획 02~05의 번호를 바꾼 커밋을 찾아 그 전과 후의 대응).
  - `git rev-list --reverse --topo-order main`을 따라 커밋마다 다음을 한다.
    - 원래 tree를 `git ls-tree -r`로 읽어 경로를 바꾸고, 바뀐 blob만 변환해 `git hash-object -w`로 쓴다. 변환은 경로, 번호, `main` 안 앞선 커밋의 SHA다.
    - 모드와 심볼릭 링크를 유지해 `git mktree`로 새 tree를 만든다.
    - 메시지를 같은 규칙으로 바꾸고, `GIT_AUTHOR_*`·`GIT_COMMITTER_*`를 원래 값으로 둔 채 `git commit-tree -p <새 부모>...`로 커밋한다.
    - 옛 SHA → 새 SHA를 기록한다.
  - 같은 blob은 한 번만 변환한다.
- [ ] **Step 4: 시험 실행.** `work` clone의 복사본에서 먼저 돌리고, 스펙 §3.5 3단계의 검증 다섯 가지를 실행한다. 어긋나면 고쳐 다시 돈다.
- [ ] **Step 5: 본 실행과 검증.** `work` clone에서 돌리고 검증 다섯 가지를 다시 한다. 결과(명령, 건수, 표본 diff)를 사용자에게 보이고 OK를 받는다.
- [ ] **Step 6: push(OK).**
  - Enforcement를 끈다(머신 계정 권한이 없으면 사용자가 Settings에서).
  - `git ls-remote origin main`이 Step 1의 SHA와 같은지 보고, `work` clone에서 `main`을 force-push한다.
  - Enforcement를 켠다. 런북 4절의 확인 명령으로 규칙 5개를 확인한다.
- [ ] **Step 7: PR #1~#20 수정(OK).** 제목·본문·머신 계정 코멘트에 같은 치환을 `gh pr edit`과 `gh api`로 적용한다. 코멘트의 base·head SHA는 `main`에 있는 것만 바꾼다. 코멘트마다 치환 건수를 남긴다.
- [ ] **Step 8: clone 맞추기(OK).**
  - main checkout에서 `git fetch origin && git reset --hard origin/main`을 실행한다. 그 전에 `.env`와 `backups/`가 남는지 `git status --ignored`로 확인한다.
  - 다른 Mac에서 할 명령을 사용자에게 알린다.
  - 사용자 메모리 색인에 대응표 위치를 한 줄 더한다.

### Task 5: Reject the legacy forms and record the results (results PR)

**Files:**
- Modify: `scripts/lib/git.sh`(`LEGACY_PLAN_PATTERN` 제거), `scripts/check-git.sh`, `scripts/check-pr.sh`, 각 bats, 이 계획(Progress log, `status`), [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md)("이전 결과" 절)

- [ ] **Step 1: 실패하는 테스트 작성.** `check-git.bats`·`check-pr.bats`·`lib-git.bats`의 옛 형식 사례(`plan/26-x`, `Plan: 26`)를 거부 사례로 옮긴다. 이유를 커밋 본문에 적는다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 옮긴 사례만 실패한다.
- [ ] **Step 3: 최소 구현.** 옛 형식 허용을 지운다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0.
- [ ] **Step 5: 기록.** [doc-ids-and-draft-board ADR](../decisions/adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md)에 "이전 결과" 절(재작성 여부, 검증 결과, 남은 것)을 더하고, 이 계획의 `status`를 `completed`로 바꾼다. 새 ID 형식의 work 브랜치에서 커밋·push하고 PR을 연다.

## Follow-ups

- 다른 저장소와 전역 지침에 초안 보드를 적용할지 정한다(스펙 §1 범위 밖).
- 에이전트 기억 미러의 색인 hook이 초안 보드를 함께 보여 줄지 [agent-memory-mirror 계획](plan-2026-10-22-mk823xbp-agent-memory-mirror.md) 담당 세션과 정한다. 그 계획이 helper를 만들면 `doc-authoring`의 프로젝트 키·기기 이름 명령을 helper로 바꾼다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
