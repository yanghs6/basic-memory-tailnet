---
status: backlog
id: {{id}}
spec: {{근거 스펙의 저장소 기준 경로, 없으면 none}}
---

# {{id}} {{Title in English}} Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** {{이 계획이 끝나면 무엇이 되는가. 한 문장}}

**Architecture:**
- {{접근 방식. 두세 줄}}

**Spec:** `{{근거 스펙 경로}}` ({{특히 읽을 절}})

**Sequence:** 계획 {{id}}. 다음을 모두 만족한 뒤 시작한다.
- {{앞선 PR이나 계획의 병합 같은 조건}}

## Global Constraints

- {{스펙이 정한 저장소 전체 요구사항. 한 줄에 하나, 값은 스펙에서 그대로 옮긴다}}
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: {{id}}`, `Task: <N|review|none>`.

## Review Focus

1. {{어느 Task의 테스트도 다루지 않지만 스펙이 함의하는 입력이나 실패, 그때 기대하는 동작, 그것을 고정하는 테스트를 둔 Task}}

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `{{경로}}` | {{한 줄}} | {{N}} |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/{{id}}-{{slug}}` 브랜치를 만든다(`git-workflow` 스킬의 Start).
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
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- {{이 계획 밖으로 미룬 일. 없으면 "없음"}}

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
