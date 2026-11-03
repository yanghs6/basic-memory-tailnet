---
status: backlog
id: 52n5kx0q
spec: docs/specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md
---

# 52n5kx0q Codex Memory Project Keys Implementation Plan

> [agent-memory-mirror 계획](plan-2026-10-22-mk823xbp-agent-memory-mirror.md) Progress log 2026-10-28 행이 "프로젝트 키로 나누는 후속 계획을 따로 둔다"고 약속한 계획이다. 2026-11-02 저장소 재검토 4장의 판단을 사용자가 승인했다. 실행은 기억 색인 캐시 작업 뒤다(Sequence).

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** Codex의 rollout 기억은 그 세션의 프로젝트 키로, 모든 프로젝트를 합친 공통 파일은 `_global`로 올라가고, 사용자는 공통 Codex 파일만 따로 뺄 수 있다.

**Architecture:**
- rollout 파일의 `cwd:` 줄을 기존 `project_key_for_dir`에 넣어 키를 정하고, 처음 정한 키를 상태 파일 `codex-keys.tsv`에 고정한다. worktree가 지워져도 노트가 다른 키로 옮겨 가지 않게 하기 위해서다.
- 공통 파일(`memory_summary.md`, `raw_memories.md`, `memories_v2`의 파일 등)은 지금처럼 `_global/codex/<기기>/`에 둔다.
- `BM_MEMORY_EXCLUDE`가 키 전체(`acme-widget`)에 더해 `<키>/<에이전트>` 형식(`_global/codex`)을 받는다. 그러면 홈 폴더 Claude 기억을 살리면서 공통 Codex 파일만 뺄 수 있다.
- 색인의 `is_mine`은 Codex에서도 현재 키와 `_global`의 "이 기기 codex" 노트를 숨긴다.

**Spec:** `docs/specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md` (§3.2 키 규칙 5와 경로 트리, §3.3 상태 파일, §3.4 색인, §3.6, §4.2). Task 1이 이 절들을 고친다.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 기억 색인 캐시 작업(2026-11-02 재검토 2차 후속 W10, 계획 미작성)이 병합됐다. 두 작업이 `scripts/show-memory-index.sh`와 `scripts/sync-agent-memory.sh`를 함께 바꾸기 때문이다.
- 사용자가 Codex 기억을 올리는 쪽을 유지한다. 아예 올리지 않기로 정하면 이 계획을 `dropped`로 닫고 그 결정을 스펙에 적는다.
- Task 5(실제 동기화)는 감독 세션이 VM 작업 창을 줄 때 한다. 1 GB VM에 쓰기가 몰리기 때문이다.

## 배경

- **Verified (2026-11-02, `scripts/sync-agent-memory.sh:256-268`):** `collect_codex`는 Codex 파일을 모두 `_global`로 보낸다. `_global`이 제외되면 Codex 전체를 건너뛴다(`:259`).
- **Verified (같은 날, `scripts/lib/agent-memory.sh:62-81`):** `project_key_for_dir`는 홈 폴더를 `_global`, origin이 있는 폴더를 `owner-repo`, origin이 없는 폴더를 `local-<이름>`으로 바꾼다. `is_excluded`(`:113-118`)는 키 전체만 맞춘다.
- **Verified (같은 날, 스펙 `:234`, `:391-393`):** 스펙 §3.2 규칙 5는 "Codex 기억은 프로젝트별로 나뉘지 않으므로 모두 `_global`에 둔다"다. 그래서 지금 `BM_MEMORY_EXCLUDE=_global`은 모든 Codex 기억과 홈 폴더에서 연 Claude 세션의 기억을 함께 뺀다. 스펙 `:54`에 따라 Codex 기억은 아직 한 번도 올라가지 않았다.
- **Verified (2026-11-02, 파일 수만 셈):** `~/.codex/memories/rollout_summaries/*.md` 27개가 모두 `cwd:` 줄을 정확히 하나씩 갖는다. 서로 다른 값은 9개이고, 그중 하나는 홈 폴더, 하나는 지금 없는 경로, 하나는 worktree 경로다. 하위 폴더는 없다.
- **Verified (같은 날, `scripts/show-memory-index.sh:36-37`):** `is_mine`은 Codex에서 `_global/codex/<이 기기>`만 숨긴다. 키를 나누면 같은 기기의 Codex rollout이 Codex 색인에 다시 보인다.
- **Verified (같은 날, `scripts/sync-agent-memory.sh:125`):** `key_taken`은 Claude용 `keys.tsv`만 본다. Codex 키를 따로 두면 Claude 폴더와 Codex rollout이 같은 키를 써도 경로의 에이전트 칸이 달라 충돌하지 않는다.
- **Assumption:** 지금 상태 파일에 `/codex/` 줄이 없으므로, 첫 동기화는 `FULL=1` 없이 새 경로를 쓴다. 실행당 5개라 여러 번 돌아야 한다.

## Global Constraints

- 스크립트 규칙(`AGENTS.md` Invariants): `#!/usr/bin/env bash` 다음 줄 `set -euo pipefail`, `scripts/lib/` 라이브러리 source, 고칠 방법을 담은 `die`, macOS bash 3.2, `x="$(fn)"` 뒤 `|| exit 1`, 이름 붙인 상수(`script-authoring` 스킬).
- 테스트를 먼저 쓴다. fake 명령은 `tests/stubs/`, 녹화 응답은 `tests/fixtures/<테스트 이름>/`에 둔다.
- 노트 제목, 기억 본문, 회사·고객 이름, 실제 `cwd:` 값은 Progress log, PR, 코멘트에 쓰지 않는다. 개수와 키 모양(`owner-repo`, `local-<이름>`)만 쓴다.
- 쓰기 속도 조절은 그대로 둔다: 실행당 5개, 쓰기 사이 3초, 90초 제한, 연속 2회 무응답이면 중단(`scripts/sync-agent-memory.sh:47-54`).
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 52n5kx0q`, `Task: <N|review|none>`.

## Review Focus

1. rollout의 `cwd:`가 지금 없는 worktree이면 키가 `local-<worktree 이름>`이 되어 회사 키 제외를 빠져나갈 수 있다. Task 2는 worktree 경로(`/.claude/worktrees/<이름>`, `-wt/<이름>`)에서 main checkout을 찾아 그 키를 쓰고, 찾지 못하면 `_global`로 보낸다. Task 2의 "deleted worktree" 테스트가 고정한다.
2. 한 번 정한 키는 `cwd`가 바뀌거나 사라져도 바뀌지 않는다. 키가 바뀌면 다음 동기화가 옛 노트를 지우고 새로 쓰기 때문이다(스펙 `:240`). Task 2의 "pinned key" 테스트가 고정한다.
3. `_global/codex` 제외는 홈 폴더 Claude 기억을 빼지 않는다. Task 3의 제외 테스트가 고정한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `docs/specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md` | 키 규칙 5, 경로 트리, 상태 파일, 색인, 제외 형식 | 1 |
| `scripts/lib/agent-memory.sh`, `tests/lib-agent-memory.bats` | rollout `cwd:` 읽기, worktree에서 main checkout 찾기, `<키>/<에이전트>` 제외 | 2, 3 |
| `scripts/sync-agent-memory.sh`, `tests/sync-agent-memory.bats` | `codex-keys.tsv`, rollout은 키 폴더로, 공통 파일은 `_global` | 2, 3 |
| `scripts/show-memory-index.sh`, `tests/show-memory-index.bats`, `tests/fixtures/show-memory-index/` | Codex `is_mine` | 3 |
| 운영 런북, `.env.example`, `docs/ARCHITECTURE.md` | 키와 제외 설명 | 4 |
| 이 계획 | Progress log, `status` | 5 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/52n5kx0q-codex-memory-keys` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Spec amendment

**Files:**
- Modify: `docs/specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md`

- [ ] **Step 1: 바뀌는 문장 목록.** 스펙의 §3.2 규칙 5(`:234`)와 경로 트리(`:213-216`, `:225`), §3.3 상태 파일(`:268`), §3.4 숨김 규칙(`:320`), §3.6(`:371`), §4.2(`:391-393`)에서 바꿀 문장과 새 문장을 표로 만든다. 사용자 결정 1~8의 문장은 바꾸지 않는다.
- [ ] **Step 2: 사용자 승인.** 표를 사용자에게 보이고 승인을 받는다. 특히 제외 형식 `<키>/<에이전트>`와 지워진 worktree 처리(main checkout 키, 못 찾으면 `_global`)를 묻는다. 승인을 Progress log에 적는다.
- [ ] **Step 3: 고치고 확인.** 승인받은 문장으로 고치고 날짜를 단 한 줄을 남긴다. Run: `make check`. Expected: exit 0.
- [ ] **Step 4: 커밋.** `git commit -m "docs: split Codex memory into project keys in the mirror spec" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 52n5kx0q" --trailer "Task: 1"`

### Task 2: Codex key from the rollout cwd, pinned

**Files:**
- Modify: `scripts/lib/agent-memory.sh`, `scripts/sync-agent-memory.sh`
- Test: `tests/lib-agent-memory.bats`, `tests/sync-agent-memory.bats`

- [ ] **Step 1: 실패하는 테스트 작성.** rollout fixture는 bats setup이 만든다(지금처럼). 테스트:
  - "a Codex rollout goes to the key of its cwd": origin이 있는 가짜 저장소를 `cwd:`로 둔 rollout이 `agent-memory/<owner-repo>/codex/<기기>/rollout_summaries/<파일>`로 간다.
  - "a Codex rollout from the home folder or without a cwd line goes to _global".
  - "a Codex rollout from a deleted worktree uses the main checkout key, else _global".
  - "a pinned Codex key survives a changed or deleted cwd": `codex-keys.tsv`에 적힌 키가 다음 실행에서도 그대로다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 테스트만 실패한다.
- [ ] **Step 3: 최소 구현.** rollout 파일에서 첫 `cwd:` 줄만 읽는 함수, worktree 경로에서 main checkout을 찾는 함수, `codex-keys.tsv`(rollout 상대 경로, 키) 읽기·쓰기를 더한다. `codex-keys.tsv`는 `state.tsv`와 같은 방식(`.partial` 뒤 이름 바꾸기)으로 쓴다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** Progress log에 RED·GREEN 명령과 결과를 적어 같은 커밋에 넣는다. `--trailer "Task: 2"`

### Task 3: Shared Codex files, agent-scoped exclusion and the index

**Files:**
- Modify: `scripts/lib/agent-memory.sh`, `scripts/sync-agent-memory.sh`, `scripts/show-memory-index.sh`
- Test: `tests/lib-agent-memory.bats`, `tests/sync-agent-memory.bats`, `tests/show-memory-index.bats`, `tests/fixtures/show-memory-index/`

- [ ] **Step 1: 실패하는 테스트 작성.**
  - "shared Codex files stay in _global": `memory_summary.md`, `raw_memories.md`, v2 파일이 `_global/codex/<기기>/`로 간다.
  - "excluding _global/codex drops only the shared Codex files": 홈 폴더 Claude 기억과 프로젝트 키 rollout은 남는다.
  - "excluding a project key drops its Codex rollouts too".
  - "the Codex index hides this device's codex notes in the current key and _global".
  - 기존 테스트 가운데 `_global/codex` 경로를 기대하는 것(`tests/sync-agent-memory.bats`의 Codex 미러 테스트 등)은 rollout 경로만 새 규칙에 맞게 고친다. 기대를 약하게 바꾸지 않고, 바꾼 테스트 이름을 Progress log에 적는다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 테스트와 경로를 바꾼 테스트만 실패한다.
- [ ] **Step 3: 최소 구현.** `collect_codex`가 rollout과 공통 파일을 나눠 `add_sources`를 부른다. `is_excluded`/`excluded_key`가 `<키>/<에이전트>`를 받는다. `is_mine`의 Codex 조건에 현재 키를 더한다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `--trailer "Task: 3"`

### Task 4: Documents

**Files:**
- Modify: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`(제외 설명과 한계), `.env.example`(`BM_MEMORY_EXCLUDE` 주석), `docs/ARCHITECTURE.md`(필요하면)

- [ ] **Step 1: 고치기.** 런북의 제외 한계 문장을 새 형식으로 바꾸고, `_global` 대신 `_global/codex`를 쓰면 홈 폴더 Claude 기억이 올라간다는 점을 적는다. `.env.example` 주석에 예시 `acme-widget,_global/codex`를 단다.
- [ ] **Step 2: 확인과 커밋.** Run: `make check`. Expected: exit 0. `--trailer "Task: 4"`

### Code PR: review and merge

- [ ] PR 본문 Verification에 Task 1~4의 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 사용자 OK를 받고 `gh pr ready <PR>`을 실행한다. 승인과 squash 병합은 사람만 한다.

### Task 5: First Codex sync (with the user, OK at every step)

**Files:**
- Modify: 이 계획(Progress log, `status`)

- [ ] **Step 1: 제외 값 결정(사용자).** 사용자가 main checkout `.env`의 `BM_MEMORY_EXCLUDE`를 새 형식으로 바꾼다(예: 회사 키와 `_global/codex`). 에이전트는 값을 대화로 받지 않고, 바꿨다는 사실만 적는다.
- [ ] **Step 2: 미리 보기.** `make status`로 메모리·스왑을 적는다. 로컬에서 올라갈 rollout 수와 키 개수를 센다(키 이름은 회사 이름이 섞일 수 있으므로 개수만).
- [ ] **Step 3: 동기화(OK).** `make memory-sync`를 실행한다. 실행당 5개이므로, 남은 수가 0이 될 때까지 사용자 OK를 받고 반복한다. 연속 무응답으로 멈추면 `bm-diagnose` 스킬로 넘어가고 사용자에게 알린다.
- [ ] **Step 4: 확인.** 키마다 `search_notes(search_type="text", metadata_filters={"project": "<키>", "agent": "codex", "mirror": true})` 건수를 로컬 파일 수와 비교한다. Codex 세션에서 `make memory-index MEMORY_AGENT=codex`가 자기 기기 노트를 숨기는지 본다.
- [ ] **Step 5: 결과 PR.** 이 계획의 `status`를 `completed`로 바꿔 새 `plan/52n5kx0q-<slug>` 브랜치에서 커밋·push하고 PR을 연다(`Task: 5`). 키 이름과 노트 제목은 쓰지 않는다.

## Follow-ups

- 미러 노트 metadata·tags 개편(`memory_project`, `tags`)은 이 계획 밖이다(2026-11-02 재검토 W8, 계획 미작성).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
