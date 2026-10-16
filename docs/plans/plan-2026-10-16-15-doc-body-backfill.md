---
status: completed
spec: docs/specs/spec-2026-10-15-doc-system.md
---

# 15 Doc Body Backfill Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 없다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 리뷰 기록과 조사 문서를 뺀 문서의 레이블 표기를 스펙 6.2절 형식으로 통일하고, 루트 `README.md`에서 `AGENTS.md`를 되풀이하는 문장을 링크로 바꾸며, 기존 문서의 절 구성을 바꾸지 않는다는 사용자 결정(D9)을 스펙에 남긴다.

**Architecture:**
- 사용자 결정(2026-10-16): 스펙 9절의 "절 이름과 순서를 템플릿에 맞춤"은 하지 않는다. 기존 문서는 절 번호(§N)와 제목으로 서로 인용하므로(리뷰를 빼고 177행·16파일, 2026-10-16 Codex 집계) 순서를 바꾸면 인용이 틀어지고, 옛 ADR에 없는 절은 내용을 지어내야 한다. 템플릿은 새 문서에만 쓴다. 이 결정은 문서 체계 스펙 1절(D9), 6.2절, 9절, 10절에 적는다(새 ADR이 아니라 스펙 안의 사용자 결정, 사용자 선택).
- 레이블은 기계적으로 바꿀 수 없다. 문장 중간의 괄호 레이블은 그 문단이나 목록 항목의 첫머리로 옮겨야 하므로, 아래 규칙으로 한 곳씩 고치고 다른 낱말은 바꾸지 않는다.
- Task 1(레이블)은 Task 2·3(README, 스펙)과 고치는 파일이 겹치지 않으므로 함께 실행할 수 있다.

**Spec:** `docs/specs/spec-2026-10-15-doc-system.md` (특히 §5.5, §5.6, §6.2, §9, §10)

**Sequence:** 계획 15. 다음을 모두 만족한 뒤 시작한다.
- 계획 14(PR #13, `eda0d92`)가 병합됐다(충족).
- 열린 PR #10(`work/docker-log-rotation`)은 `docs/ARCHITECTURE.md`를 고친다. 이 계획도 그 파일의 레이블을 고치므로 나중에 병합되는 쪽이 `git merge origin/main`으로 충돌을 푼다.

## Global Constraints

- 고치지 않는 곳: 리뷰 기록(`docs/reviews/`), 조사 문서(`docs/research/`, 스펙 5.5절 "쓴 뒤에는 고치지 않는다"), 코드 블록, 백틱 안의 인용(예: 문서 체계 스펙 2절의 옛 표기 예시), 증거(명령, 출력, SHA, 날짜, 측정값), 결정 문장, 절 제목과 번호(D9). 단 레이블 꼬리가 붙은 제목은 규칙 L3대로 꼬리만 옮긴다.
- 레이블 형식(스펙 6.2절): 문단이나 목록 항목 첫머리에 `**Verified:**`처럼 굵게 쓰고 쌍점을 붙인다. 날짜·출처·버전이 필요하면 괄호에 넣는다: `**Verified (2026-10-12, 0.23.2):**`. 표의 `표기` 열에는 레이블만 쓴다.
- 어휘: `Verified`, `Command`, `Assumption`, `Open question`, `Reported`.
- 테스트를 새로 쓰지 않는다(레이블과 언어 검사는 ADR 0004가 금지, ADR 0007 결정 2). 확인은 scratch 스크립트와 `git diff --word-diff`로 한다.
- 테스트는 `make test`/`make check`로만 돌린다. `git add`하기 전에 `git status`를 본다. 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 15`, `Task: <N|review|none>`.
- PR: 브랜치 `plan/15-doc-body-backfill`, 제목 `docs: unify note labels and trim README duplication`, 본문은 문단과 목록 항목마다 한 줄로 쓰고 마지막 문단은 `Assisted-by`와 `Plan: 15`다.

## Review Focus

1. **레이블을 옮기다 사실의 범위가 바뀜.** 한 문단에 확인한 사실과 확인하지 않은 사실이 섞여 있는데 앞에 `**Verified:**`를 붙이면 둘 다 확인한 것처럼 읽힌다. → 규칙 L2의 "레이블이 다른 사실이 섞이면 항목을 나눈다"와 Task 1 Step 3의 word-diff 확인.
2. **레이블의 날짜·출처를 잃음.** `(**Verified**, 2026-10-12, 실제 …)`의 날짜와 출처가 옮기며 빠진다. → 규칙 L2: 괄호 안의 다른 내용은 모두 레이블의 괄호로 옮긴다.
3. **인용 예시나 코드까지 바꿈.** 스펙 2절은 옛 표기를 예시로 인용한다. → 백틱 안과 코드 블록은 고치지 않는다. Step 3의 목록 확인에서 남는 줄로 남긴다.
4. **README에서 사람에게 필요한 안내가 사라짐.** 규칙을 지우면 사람이 어디서 찾는지 모른다. → Task 2는 문장을 지우는 대신 `AGENTS.md`의 해당 절 링크로 바꾼다.
5. **표 칸의 레이블.** 표의 셀 안 괄호 레이블은 셀 첫머리로 옮긴다(L5). 표의 `표기` 열은 그대로 둔다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `docs/ARCHITECTURE.md`, `docs/runbooks/*`, `docs/decisions/*`, `docs/plans/*`(이 계획 제외), `docs/specs/*`(문서 체계 스펙 제외) | 레이블 표기 | 1 |
| `README.md` | `AGENTS.md` 중복 문장을 링크로 | 2 |
| `docs/specs/spec-2026-10-15-doc-system.md` | D9와 6.2·9·10절, 이 파일의 레이블 | 3 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/15-doc-body-backfill` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [x] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: 레이블 표기 통일

**Files:**
- Modify: 아래 목록의 파일(리뷰, 조사, README, 문서 체계 스펙, 이 계획은 제외)
- Test: 없음(Global Constraints). `make check`가 링크와 경로 검사를 다시 본다.

**Interfaces:**
- Consumes: 없음
- Produces: 없음

- [x] **Step 1: 목록 만들기 (scratch 스크립트, 커밋하지 않음)**

저장소 밖 scratch 폴더에 `label-list.sh`를 두고 worktree를 인자로 실행한다. 6.2절과 다른 레이블이 있는 줄을 `파일:줄: 내용`으로 출력한다.

```bash
set -euo pipefail
cd "$1"
LABELS='Verified|Command|Assumption|Open question|Reported'
for f in $(git ls-files 'docs/*.md' README.md | grep -vE '^docs/(reviews|research)/'); do
  awk -v f="$f" -v labels="$LABELS" '
    /^```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      bad = 0
      if (line ~ ("\\*\\*(" labels ")( \\([^)]*\\))?\\*\\*([^:]|$)")) bad = 1
      if (line ~ ("\\*\\*(" labels ") [^(*][^*]*:\\*\\*")) bad = 1
      if (line ~ ("^(- |> )?(" labels "):")) bad = 1
      if (line ~ ("^#.*\\((" labels "),")) bad = 1
      if (bad) print f ":" NR ": " substr(line, 1, 150)
    }' "$f"
done
```

2026-10-16 `eda0d92`에서 43줄이 나왔다. 그중 몇 줄은 이미 맞는 형식인데 정규식이 잡은 것이다(예: 괄호 안 출처에 쌍점이 있는 `**Verified (https://…):**`, 표의 `| Verified |`). 줄마다 아래 규칙에 맞는지 보고, 맞으면 그대로 둔다.

- [x] **Step 2: 규칙대로 고치기**

- L1 (블록 머리): 줄에 레이블만 있는 `**Verified**`, `**Verified (저장소)**`는 쌍점을 붙인다: `**Verified:**`, `**Verified (저장소):**`.
- L2 (문장 속 괄호 레이블): `…없습니다(**Verified**).`, `…(**Verified**, 2026-10-12, 실제 …).`, `…(**Open question**).`는 레이블을 그 문단이나 목록 항목의 첫머리로 옮겨 `**Verified (2026-10-12, 실제 …):** …`로 쓰고 원래 괄호를 지운다. 괄호 안의 다른 내용(날짜, 버전, 출처)은 모두 레이블의 괄호로 옮긴다. 항목이 이미 다른 레이블로 시작하거나 레이블이 다른 사실이 섞여 있으면, 다른 낱말은 그대로 두고 사실마다 목록 항목을 나눈다. 레이블이 술어인 문장(`…는 **Open question**입니다.`)은 `**Open question:** …는 아직 정하지 않았다.`처럼 레이블을 앞으로 빼고 술어만 바꾼다.
- L3 (제목 꼬리): `## 근거 (Verified, 2026-10-13 웹 조사)`는 제목을 `## 근거`로 두고 그 바로 아래 첫 줄에 `**Verified (2026-10-13 웹 조사):**`를 쓴다. 절이 목록이면 그 줄 다음에 목록이 온다.
- L4 (변형): `**Assumption 확인:** X`는 `**Assumption:** (이 Step에서 확인) X`로 쓴다.
- L5 (표 칸): 표 셀 안의 괄호 레이블은 그 셀의 첫머리로 옮긴다(L2와 같은 방법). `표기` 열은 그대로 둔다.

2026-10-16에 확인한 대상 파일: `docs/ARCHITECTURE.md`(4곳), ADR 0001·0003·0004·0005, 계획 02·05·08, 런북 accounts·bootstrap·gcp-vm·operations·github, 접속 방식 설계, 스크립트·테스트 구조 설계. 문서 체계 스펙은 Task 3이 고친다.

- [x] **Step 3: 확인**

Run: scratch `label-list.sh`
Expected: 남는 줄은 Step 1에서 "이미 맞는 형식"으로 판정한 줄뿐이다. 남긴 줄과 이유를 Progress log에 적는다.

Run: `git diff --word-diff=porcelain | grep -E '^[-+][^-+]'`
Expected: 바뀐 낱말은 레이블, 옮긴 괄호 내용, L2의 술어("…입니다" → "…않았다")뿐이다.

Run: `make check`
Expected: exit 0.

- [x] **Step 4: 커밋**

```bash
git status --short
git add -u docs
git commit -m "docs: put note labels at the start of their paragraph, as spec 6.2 says" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 15" --trailer "Task: 1"
git push
```

### Task 2: README의 `AGENTS.md` 중복

**Files:**
- Modify: `README.md`
- Test: 기존 상대 링크 검사

**Interfaces:**
- Consumes: 없음
- Produces: 없음

- [x] **Step 1: 중복 문장을 링크로 바꾸기**

- "빠르게 시작하기"의 "`local-up`은 고정된 컨테이너 이름과 포트를 쓰므로 한 번에 한 작업 트리에서만 실행합니다." → "명령마다의 규칙(한 번에 한 worktree에서만 돌리는 명령, 승인이 필요한 명령)은 AGENTS.md의 Commands에 있습니다."(AGENTS.md는 루트의 그 파일로 가는 상대 링크로 쓴다)
- "VM 구축 순서" 첫 문단 "VM이나 클라우드 자원을 바꾸는 명령(…)은 사람이 승인한 뒤에만 실행합니다. `.env`와 `backups/`는 main 체크아웃에만 둡니다(…)." → "VM이나 클라우드를 바꾸는 명령의 승인 규칙과 `.env`·`backups/`를 두는 곳은 AGENTS.md의 Safety에 있습니다."(같은 링크)
- 실행 예시(코드 블록), 사전 요구사항, 웹 UI 안내, VM 구축 순서 목록, 스킬 목록은 그대로 둔다.

- [x] **Step 2: 확인과 커밋**

Run: `make check`
Expected: exit 0.

```bash
git add README.md
git commit -m "docs: point the README at AGENTS.md instead of repeating its rules" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 15" --trailer "Task: 2"
git push
```

### Task 3: 스펙에 D9 남기기

**Files:**
- Modify: `docs/specs/spec-2026-10-15-doc-system.md`
- Test: 기존 검사(front matter, 경로)

**Interfaces:**
- Consumes: 없음
- Produces: 없음

- [x] **Step 1: 스펙 고치기**

- 1절 사용자 결정 목록 끝에 새 묶음을 더한다: "**사용자 결정 (2026-10-16, 계획 15 범위)**", "D9. 기존 문서의 절 구성(이름, 순서, 번호)은 바꾸지 않고, 템플릿은 새 문서에 쓴다. 이유: 다른 문서가 절 번호와 제목으로 인용하고(리뷰를 빼고 177행·16파일, 2026-10-16), 스크립트와 스킬이 런북 제목과 번호를 가리키며, 옛 ADR에 없는 절은 내용을 지어내야 한다. 계획 15는 레이블 표기(6.2절)와 README의 중복만 정리하고, 리뷰 기록과 조사 문서(5.5절)는 레이블도 그대로 둔다."
- 6.2절 "기존 문서의 옛 표기는 계획 15가 이 형식으로 바꾼다. 리뷰는 바꾸지 않는다." → "기존 문서의 옛 표기는 계획 15가 이 형식으로 바꾼다. 리뷰 기록과 조사 문서는 바꾸지 않는다(D9)."
- 9절 표의 계획 15 행 → 대상 "리뷰와 조사를 뺀 모든 타입 문서, ARCHITECTURE, 루트 README", 바꾸는 것 "레이블 표기 통일(6.2절), `AGENTS.md`와 겹치는 문장 정리(README). 절 구성은 그대로 둔다(D9)".
- 9절 "본문을 옮길 때 내용을 잃지 않게"의 첫 항목 → "계획 15는 절을 옮기지 않는다(D9). 레이블 커밋은 레이블과 그 괄호 내용의 위치만 바뀌어야 한다(`git diff --word-diff`로 확인)."
- 10절 표의 계획 15 행 범위 → "9절 표의 본문 행: 레이블 통일, README의 중복 정리(절 구성은 D9로 제외)".
- 2절의 `**Verified (저장소)**` 블록 머리에 쌍점을 붙인다(L1). 같은 절의 옛 표기 예시(백틱 안)는 그대로 둔다.

- [x] **Step 2: 확인과 커밋**

Run: `make check`
Expected: exit 0.

```bash
git add docs/specs/spec-2026-10-15-doc-system.md
git commit -m "docs: record that plan 15 keeps the section structure of existing documents (D9)" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 15" --trailer "Task: 3"
git push
```

### Finish: review and hand-off

- [x] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 계획 16·17: 스크립트·테스트 구조 설계(다른 세션).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-16 | Command | 시작: `plan/15-doc-body-backfill`을 `origin/main` `eda0d92`(PR #13 병합)에서 만듦(worktree `repo-structure` 재사용). 범위는 사용자 결정대로 처음 A안(레이블, README, 스펙 D9; 새 ADR 없음). Codex도 같은 범위를 권함(새 ADR로 남기자는 수정은 사용자가 고르지 않음). 계획 파일은 따로 커밋하지 않고 첫 작업 커밋(Task 2)에 넣음(사용자 결정). 실행: Task 1은 별도 worktree의 서브에이전트, Task 2·3은 이 worktree에서 병렬. |
| 2026-10-16 | Verified | Task 2 `5fb99ea`: README 30·47행이 되풀이하던 `AGENTS.md` Commands·Safety 규칙을 그 절을 가리키는 문장으로 바꿈. 이 계획 파일(`make new-doc TYPE=plan`으로 만듦)도 이 커밋에 넣음. |
| 2026-10-16 | Verified | Task 3 `a5bdd7d`: 스펙 1절에 D9(사용자 결정 2026-10-16)를 적고, 2절 블록 머리에 L1을 적용하고, 6.2·9·10절을 D9에 맞춤. |
| 2026-10-16 | Verified | Task 1(서브에이전트, 별도 worktree, Task 2·3과 병렬): `fc52ebe`를 cherry-pick해 `1a31a21`, 파일 16개, 레이블 37곳. `label-list.sh`에 남은 줄은 이미 맞는 형식(ADR 0002 16행, 계획 07 22·28~30행: 괄호 안의 쌍점이나 URL을 스크립트가 잘못 읽음)과 백틱 안의 예시(이 계획, 스펙 2절)뿐. |
| 2026-10-16 | Verified | 판정(L2가 거칠었음): 레이블을 문단·항목 첫머리로 옮기자, 원래 한 문장만 덮던 레이블이 같은 문단의 지시문이나 결정까지 덮은 곳이 11곳(ADR 0001 2, ARCHITECTURE 신뢰 경계 1, accounts 4, github 2, gcp-vm 6절 1, operations 비용 점검 1). 레이블이 덮던 문장을 하위 항목이나 별도 문단으로 떼어 원래 범위로 되돌림. ADR 0001에서는 문장을 나누며 연결 어미 두 개("하고,", "실패했고,")가 바뀜. 모르는 사실에 붙은 술어는 L2의 "아직 정하지 않았다" 대신 "아직 확인하지 못했다"로 씀(ARCHITECTURE 1, operations 2). 정할 일인 accounts의 최소 권한 조합은 그대로 둠. 스펙 9절의 word-diff 문장을 이 범위에 맞춤. 틀렸을 때 비용: 문장 몇 개의 위치. |
| 2026-10-16 | Verified | 판정(문단 가운데의 레이블): 이미 6.2절 표기로 쓴 레이블 27개가 문단, 항목, 표 칸, 괄호의 가운데에 있음(scratch `label-mid.sh`, 파일 9개). 그대로 둠: 스펙 2절이 꼽은 옛 표기가 아니고, 저마다 바로 뒤의 내용만 덮으며, 첫머리로 옮기면 범위가 넓어지고(Review Focus 1) 표 칸은 나눌 수 없음. 틀렸을 때 비용: 27곳을 나누는 작업 한 번. |
| 2026-10-16 | Verified | 위 수정 뒤 `make check`: exit 0, 213 ok, 0 not ok, 커버리지 94.51%. `git diff 1a31a21^ --word-diff=plain`으로 바뀐 낱말이 레이블, 옮긴 괄호 내용, 목록 기호, 연결 어미 두 개, 술어뿐임을 확인. |
| 2026-10-16 | Verified | 최종 리뷰(opus, `eda0d92..fee934f`): 수정 후 병합 가능, Critical 0, Important 1, Minor 5. 옮긴 레이블 37곳의 날짜와 출처가 모두 남았고, 코드 블록·백틱·제목 번호·리뷰 기록·조사 문서는 바뀌지 않았음을 확인받음. |
| 2026-10-16 | Verified | I1 수정 `3fba341`(`Review-Finding: SDD-final-I1`): Step 1 정규식이 굵게 쓴 레이블만 찾아, 굵지 않은 옛 표기 10곳이 남아 있었음(ADR 0006, 접속 방식 스펙 2, 웹 UI 스펙 2, 계획 10 2, 계획 04, 계획 05 2). 계획 05의 Verified 행에 섞인 Assumption 문장은 계획 12처럼 새 행으로 뗌. 넓힌 scratch `label-plain.sh`에 남은 줄은 다른 곳의 레이블을 가리키는 명사("스펙 §3의 Assumption", "Open question 3")와 인용뿐. |
| 2026-10-16 | Verified | 사용자 결정: 문단 가운데 레이블 27곳을 그대로 둔다는 위 판정을 뒤집고, 레이블 자리에서 나눠 첫머리로 옮김(B). `b1df1a0`: 파일 7개, 24곳. 레이블은 하위 항목이나 별도 문단이 되어 전과 같은 범위를 덮음. 표 칸 3곳(ADR 0003, 계획 14, bootstrap의 문제 해결 표)은 칸을 나눌 수 없어 그대로 둠. `label-mid.sh`에는 그 3곳만 남음. |
| 2026-10-16 | Verified | M5 수정(`Review-Finding: SDD-final-M5`): 스펙 D9에 제목 꼬리 레이블(L3) 예외를 적고, 9절 word-diff 문장에 표의 새 행과 L4의 괄호 말을 더함. |
| 2026-10-16 | Verified | 판정(M1): 계획 12의 "실제 키가 아니다."는 Assumption 행에 둠. 감지된 값이 테스트용 가짜 값이라는 것 자체가 대시보드로 확인할 가정이므로, 그 결론을 Verified 행으로 옮기면 확인하지 않은 것을 확인했다고 적게 됨. 틀렸을 때 비용: 한 문장이 실제보다 덜 확실하게 읽힘. |
| 2026-10-16 | Verified | 판정(M2): Open question이나 Assumption 바로 뒤에서 그것을 어떻게 확인하는지, 틀리면 어떻게 되는지 말하는 문장은 그 레이블 안에 둠(ARCHITECTURE·ADR 0001·operations의 IPv4와 IAP 요금 질문, 계획 04의 `fallocate` 가정). 질문과 그 해소 방법은 한 묶음이다. 틀렸을 때 비용: 문장 몇 개의 위치. |
| 2026-10-16 | Verified | 미룬 Minor(사용자가 정함): M3 gcp-vm 2절 표의 이미지 행은 칸에 레이블만 있어 쌍점 뒤가 빔. M4 ADR 0004의 `**Verified (2026-10-13):**` 블록 머리와 다음 줄 `**Command:**` 사이에 빈 줄이 없어 한 줄로 보임. |
| 2026-10-16 | Verified | 리뷰 수정 뒤 `make check`: exit 0, 213 ok, 0 not ok, 커버리지 94.51%. |
