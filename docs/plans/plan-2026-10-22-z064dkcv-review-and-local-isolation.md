---
status: completed
id: z064dkcv
spec: docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md
---

# z064dkcv Review Runner and Local Stack Isolation Implementation Plan

> 2026-10-22 에이전트 개발 시스템 평가(저장소 밖 기록)의 D6·D7 발견으로 만든 백로그 초안입니다. 실행하려면 사용자 승인과 `## 배경` 끝의 Open question 1~3 결정이 먼저 있어야 합니다. Task 1~3은 스펙 8절이 정한 리뷰 흐름 안에서 리뷰어 입력과 코멘트 머리를 넓히는 일이므로 새 스펙 없이 이 계획으로 진행할 수 있습니다. Task 4에서 (b)안(worktree마다 project name과 포트)을 고르면 brainstorming → 스펙 → 계획 순서를 먼저 거칩니다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 교차 벤더 리뷰가 명시하고 기록한 모델과 추론 강도로 돌고 `make check` 결과를 보게 하며, 두 worktree가 로컬 스택 하나를 조용히 나눠 쓰지 못하게 한다.

**Architecture:**
- `scripts/review-branch.sh`가 `REVIEW_MODEL`·`REVIEW_EFFORT`(기본값은 리뷰어별 상수)를 리뷰어 CLI에 넘긴다. 리뷰한 head에서 `make check`를 돌려 결과를 prompt에 넣고, 모델·강도·check 결과를 meta 파일에 남긴다. 리뷰어 CLI의 stdin은 `/dev/null`로 닫는다.
- `scripts/post-review.sh`는 코멘트 머리의 모델·강도·check 결과를 손 입력 대신 meta 파일에서 읽는다.
- 새 `scripts/check-local-stack.sh`는 `local-up`·`local-down` 전에, compose project의 컨테이너가 다른 디렉터리 것이면 거부한다(Open question 3의 (a)안).

**Spec:** `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md` (8절 "게시": 코멘트 머리에 리뷰 도구와 모델, base와 head SHA, 회차). 이 스펙이 고친 `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md` (5절: 리뷰어 명령, 체크리스트 3 "`make check`가 통과하는가"). Task 4에는 근거 스펙이 없다. `AGENTS.md:10`의 문장 규칙을 검사로 바꾸는 일이다.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- [public-text-guard 계획](plan-2026-10-22-v9whrbs6-public-text-guard.md)(`docs/plans/plan-2026-10-22-v9whrbs6-public-text-guard.md`)이 병합됐다. 두 계획이 모두 `scripts/post-review.sh`를 고치므로 18을 먼저 한다.
- 사용자가 Open question 1~3을 정했다.

## 배경

- **Verified (2026-10-22):** `scripts/review-branch.sh:137`(`codex exec review -c 'sandbox_mode="read-only"' --base ...`), `:139`(`codex exec --sandbox read-only -o ...`), `:149`(`claude -p --agent branch-reviewer ...`)는 모델과 추론 강도를 넘기지 않는다. `.claude/agents/branch-reviewer.md:1-13`의 front matter에도 `model`이 없다.
- **Verified (2026-10-22):** 사용자 수준 Codex 기본값은 `model_reasoning_effort = "low"`이다. 그래서 지금 Codex 리뷰는 저장소가 정하지 않은 강도로 돈다.
- **Verified (2026-10-22):** 코멘트 머리의 모델은 사람이나 에이전트가 손으로 넣는다(`scripts/post-review.sh:54`의 `${REVIEW_MODEL:-CLI default model}`). 그렇게 하라는 안내는 `scripts/review-branch.sh:204`와 `.agents/skills/git-workflow/references/review-and-merge.md:13`에 있다. 이 값은 CLI가 실제로 쓴 모델과 연결되지 않고, 강도는 어디에도 남지 않는다.
- **Verified (2026-10-22, codex-cli 0.163.0 `codex exec --help`, `codex exec review --help`):** 두 명령 모두 `-m, --model <MODEL>`과 `-c, --config <key=value>`를 받는다. `codex exec` 도움말에는 "If stdin is piped and a prompt is also provided, stdin is appended as a `<stdin>` block"이라고 적혀 있다.
- **Verified (2026-10-22, Claude Code 2.1.307 `claude --help`):** `--model <model>`과 `--effort <level>`(low, medium, high, xhigh, max)이 있다.
- **Reported (2026-10-07 스펙 5절):** Codex는 `--base`와 사용자 prompt를 함께 받지 못한다. 그래서 변경 리뷰(`codex exec review --base`)에는 check 결과를 prompt로 줄 수 없고, 계획 대조 리뷰에만 줄 수 있다.
- **Reported (2026-10-22 평가):** Codex 교차 리뷰는 최근 8개 PR(#9, #11~#17)에서 지적이 0건이었다. read-only sandbox에 Docker가 없어 `make check`를 돌리지 못했거나(#13, #16), 아예 돌리지 않았다. 같은 기간의 실제 결함은 같은 벤더가 계획 안에서 한 리뷰가 먼저 찾았다.
- **Verified (2026-10-22):** 비대화형 백그라운드 셸에서 시작한 `codex exec`가 `Reading additional input from stdin...`을 찍고, stdin을 `/dev/null`로 돌릴 때까지 멈췄다. `scripts/review-branch.sh`는 리뷰어 CLI의 stdin을 닫지 않는다(`:137`, `:139`, `:149`). 따라서 리뷰어 CLI는 `make review`의 stdin을 그대로 물려받는다.
- **Assumption:** `make review`가 실제로 멈추는지는 시작 방식, 즉 stdin이 닫히지 않는 파이프인지에 달렸다. 에이전트 도구의 백그라운드 실행이 그런지는 확인하지 않았다.
- **Verified (2026-10-22):** `compose.yaml:4`는 `name: basic-memory`, `:15`와 `:45`는 `container_name`을 고정한다. `Makefile:58-62`(`local-up`)와 `:64-65`(`local-down`)는 `-p` 없이 `$(COMPOSE)`를 부르고 아무것도 검사하지 않는다. 규칙은 `AGENTS.md:10`의 문장("run it in one worktree at a time")뿐이다.
- **Reported (2026-10-22 평가):** 그래서 두 번째 worktree의 `make local-up`은 첫 worktree의 스택을 조용히 다시 만든다. 채점자도 이 동작을 실행해 보지는 않았다.
- **Assumption:** 같은 이유로 다른 worktree에서 실행한 `make local-down`은 남의 스택을 멈춘다.
- **Open question 1 (모델과 강도의 기본값):**
  - A: `scripts/review-branch.sh`에 리뷰어별 상수(`DEFAULT_CODEX_MODEL`, `DEFAULT_CLAUDE_MODEL`, `DEFAULT_REVIEW_EFFORT`)를 두고, `REVIEW_MODEL`·`REVIEW_EFFORT`로 덮어쓴다.
  - B: 기본값 없이 두 변수를 필수로 한다.
  - 추천은 A다. 매번 입력하지 않아도 기록이 맞고, 리뷰어 모델을 바꾸는 일이 이미지 pin처럼 리뷰받는 커밋이 된다.
  - 값은 사용자가 정한다. 평가가 읽은 리뷰 기록의 Codex 모델은 `gpt-6.1-sol`이다(**Reported (2026-10-22 평가)**). 강도는 `high`를 추천한다. low보다 느리고 비싸다.
- **Open question 2 (check 결과를 어디서 얻나):**
  - A: `review-branch.sh`가 리뷰 worktree에서 `make check`를 직접 돌린다. 리뷰한 head와 정확히 같다. 대신 `make review`를 돌리는 곳에 Docker가 있어야 하고, 리뷰마다 check 시간만큼 길어진다.
  - B: PR의 CI `check` 결과를 `gh`로 읽는다. Docker는 필요 없다. 대신 head가 push되고 CI가 끝나 있어야 하며, 로컬 브랜치의 head와 다를 수 있다.
  - 추천은 A다. meta 파일이 기록하는 head는 로컬 ref이고, `make check`가 저장소의 검증 진입점이다. 이 계획은 A로 쓴다.
- **Open question 3 (로컬 스택 격리):**
  - (a): `local-up`·`local-down`이 compose project의 컨테이너가 다른 작업 디렉터리 것이면(라벨 `com.docker.compose.project.working_dir`) 거부한다.
  - (b): worktree마다 project name과 포트를 따로 만든다.
  - 추천은 (a)다. 포트는 `.env`의 `BM_PORT`·`SB_PORT`로 고정이다. (b)를 하려면 포트 배정, `local-verify`와 `sb-fonts LOCAL=1`의 포트 찾기, VM과 함께 쓰는 `compose.yaml`의 `container_name`까지 바꿔야 한다. 이 계획은 (a)로 쓴다.

## Global Constraints

- 스크립트 규칙(`AGENTS.md` Invariants):
  - `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`을 쓰고, `scripts/lib/common.sh`를 source한다.
  - 실패는 고칠 방법을 담은 `die`로 낸다.
  - macOS bash 3.2에서 돌아야 하고, `x="$(fn)"` 뒤에는 `|| exit 1`을 붙인다.
  - 숫자에는 이름 붙인 상수를 쓴다.
- 새 스크립트는 `make new-script NAME=<name>`으로 짝 테스트와 함께 만든다(`script-authoring` 스킬).
- 테스트를 먼저 쓴다.
  - `docs/decisions/adr-2026-10-13-a878ypj5-test-scope.md`를 따른다: 대표 성공 경로와, 조용히 넘어가거나 반쪽으로 끝날 실패 경로만 쓴다.
  - 가짜 명령은 `tests/stubs/`에 둔다.
  - 인터페이스가 바뀌어 기존 기대값을 고칠 때는 커밋 본문에 이유를 적는다. 테스트를 약하게 만들지 않는다.
- 리뷰어는 계속 읽기 전용이다. `sandbox_mode="read-only"`, `--sandbox read-only`, `--agent branch-reviewer --permission-mode plan`은 빼지 않는다.
- 공개 PR 코멘트에는 로컬 절대 경로, IP, session id를 넣지 않는다. check 로그의 경로도 코멘트 머리에 넣지 않는다.
- `compose.yaml`의 `127.0.0.1` 바인딩과 이미지 digest는 건드리지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: z064dkcv`, `Task: <N|review|none>`.

## Review Focus

1. 리뷰 worktree에서 돈 `make check`가 main checkout이나 작성자 worktree에 무언가 쓰는가. `.coverage/`는 리뷰 worktree 안에 생기고 정리할 때 함께 지워져야 한다. stub으로는 드러나지 않으니 코드로 확인한다(Task 2).
2. 이 계획 전에 만든 meta 파일(`base`·`head` 두 줄)로 `make review-post`를 돌리면, "CLI default model"로 게시하지 않고 gh를 부르기 전에 멈춘다. Task 3의 테스트가 고정한다.
3. 실패한 `make check`는 리뷰를 멈추지 않는다. 결과는 prompt와 코멘트 머리 양쪽에 `failed (exit N)`으로 남는다. Task 2·3의 테스트가 고정한다.
4. 라벨의 경로와 현재 경로를 비교할 때, 심볼릭 링크(macOS의 `/var`와 `/private/var`) 때문에 같은 worktree를 거부하면 안 된다. 두 쪽 모두 `pwd -P`로 맞춘다. Task 4의 테스트가 고정한다.
5. 게시하는 코멘트 본문에 `REVIEW_OUT_DIR` 경로가 없다. Task 3의 테스트가 고정한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `scripts/review-branch.sh` | 모델·강도 전달, check 실행과 요약, stdin 닫기, meta 기록 | 1, 2 |
| `tests/review-branch.bats` | 위 동작 | 1, 2 |
| `tests/stubs/codex`, `tests/stubs/claude` | `STUB_LOG_STDIN=1`이면 받은 stdin 바이트 수를 기록 | 2 |
| `tests/stubs/make` (새 파일) | `make check` 호출과 종료 코드 흉내 | 2 |
| `scripts/post-review.sh`, `tests/post-review.bats` | 머리의 모델·강도·check를 meta에서 읽음 | 3 |
| `Makefile` | `REVIEW_EFFORT` export, `review`·`review-post` 도움말, `local-up`·`local-down` 검사 | 1, 3, 4 |
| `.agents/skills/git-workflow/references/review-and-merge.md` | 리뷰 절차 문구 | 3 |
| `scripts/check-local-stack.sh`, `tests/check-local-stack.bats` (새 파일) | 다른 디렉터리의 로컬 스택 거부 | 4 |
| `tests/stubs/docker`, `tests/repo-make.bats` | 라벨 조회 출력, make 경로 검사 | 4 |
| `AGENTS.md` | `:10`의 규칙 문장 | 4 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/z064dkcv-review-and-local-isolation` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고, Open question 1~3의 결정을 Progress log에 적는다. push한 뒤 초안 PR을 연다.

### Task 1: Reviewer model and effort

**Files:**
- Modify: `scripts/review-branch.sh:8-10`(머리 주석), `:17`(상수), `:134-141`(`run_codex`), `:147-150`(`claude_review`), `:202`(meta)
- Modify: `Makefile:23`(`REVIEW_EFFORT` export), `Makefile:90`(`review` 도움말)
- Test: `tests/review-branch.bats:30-70`, `:141-190`

**Interfaces:**
- Produces: `make review`가 넘기는 환경변수 `REVIEW_MODEL`, `REVIEW_EFFORT`. meta 파일의 `base`·`head` 다음에 오는 `model <m>`, `effort <e>` 줄.

- [ ] **Step 0:** Codex config reference(https://learn.chatgpt.com/docs/config-file/config-reference)에서 `model_reasoning_effort`의 허용 값을 확인한다. Claude `--effort` 값과의 공통 집합을 상수 `REVIEW_EFFORTS`로 정하고, 결과를 Progress log에 `Verified`로 적는다. **Assumption:** 공통 집합은 `low medium high xhigh`일 것이다.
- [ ] **Step 1: 실패하는 테스트 작성**
  - `:30` 테스트에 두 리뷰어의 기본값을 기대값으로 넣는다. Codex는 `codex exec review -m <기본 모델> -c model_reasoning_effort="<기본 강도>" -c sandbox_mode="read-only" --base main`이 찍히는지, `-o` 호출에도 같은 `-m`·`-c`가 붙는지 본다. Claude는 두 호출 모두에 `--model <기본 모델> --effort <기본 강도>`가 있는지 본다. 두 경우 모두 meta 파일에 `model …`·`effort …` 줄이 있는지 확인한다. `:57`의 기존 기대값이 바뀌는 이유(인자가 늘어남)는 커밋 본문에 적는다.
  - 새 테스트 "passes REVIEW_MODEL and REVIEW_EFFORT to both reviewer calls and records them in the meta file": `REVIEW_MODEL=model-y REVIEW_EFFORT=xhigh`로 두 리뷰어를 돌린다.
  - `:141` 거부 테스트에 case `"unknown effort|REVIEW_EFFORT must be one of"`(`REVIEW_EFFORT=extreme`)를 더한다. 리뷰어 호출이 0번이고 worktree가 하나뿐이어야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 위 세 테스트가 실패한다. `-m`·`--model` 줄과 meta의 `model` 줄이 없고, `extreme`은 거부되지 않고 리뷰가 성공하기 때문이다.
- [ ] **Step 3: 최소 구현.** 상수와 검증을 추가한다. 검증은 worktree를 만들기 전에 하고, 모델 이름은 `[A-Za-z0-9._-]`만 받는다. 이어서 Codex 두 호출에 `-m`과 `-c "model_reasoning_effort=\"$effort\""`를, `claude_review`에 `--model`·`--effort`를 넣고, meta에 두 줄을 쓴다. 머리 주석과 `Makefile:90` 도움말에 두 변수를 적는다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: pass the reviewer model and reasoning effort explicitly and record them" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: z064dkcv" --trailer "Task: 1"`

**Assumption:** `branch-reviewer`에 `model` 키가 없으므로 `--agent`를 쓸 때도 `--model`이 적용될 것이다. Finish의 첫 실제 리뷰에서 확인한다.

### Task 2: Check result for the reviewer, closed stdin

**Files:**
- Create: `tests/stubs/make`. 호출을 `make <args> :: cwd=<dir>`로 기록하고 한 줄을 출력한 뒤 `MAKE_STUB_EXIT`(기본 0)로 끝난다.
- Modify: `scripts/review-branch.sh:99-132`(prompt), `:134-156`(리뷰어 호출의 `</dev/null`), `:183-202`(check 실행, `rm -f`, meta)
- Modify: `tests/stubs/codex:1-6`, `tests/stubs/claude:1-6`. `STUB_LOG_STDIN=1`일 때 `<name> stdin_bytes=<n>` 줄을 따로 기록한다.
- Test: `tests/review-branch.bats`(`setup`의 `setup_stubs`에 `make` 추가)

**Interfaces:**
- Consumes: Task 1의 meta 파일.
- Produces: out 디렉터리의 `<prefix>-check.log`. meta 파일의 `check passed` 또는 `check failed (exit <n>)` 줄.

- [ ] **Step 1: 실패하는 테스트 작성**
  - "gives the reviewer the make check result of the reviewed head and keeps the log": case는 `MAKE_STUB_EXIT` 0과 2, 리뷰어는 codex와 claude다. 확인할 것:
    - `make check :: cwd=$REVIEW_WT`가 한 번 호출된다.
    - check가 실패해도 리뷰는 성공한다.
    - `$OUT-r1-<reviewer>-check.log`에 stub 출력이 들어 있다.
    - meta에 `check passed` 또는 `check failed (exit 2)`가 있다.
    - prompt에 `make check on the reviewed head: <결과>`가 들어 있다. Codex는 `-o` 호출에만, Claude는 두 호출 모두에 들어간다. 실패한 case에서는 stub의 출력 줄도 prompt에 들어 있다.
  - "closes stdin for every reviewer call": `STUB_LOG_STDIN=1 run "$REVIEW" plan/qq4h1djv-git-review-tooling <reviewer> <<<"leaked input"`로 돌린다. 리뷰어 호출마다 `stdin_bytes=0`이 찍히고, 0이 아닌 값은 하나도 없어야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 첫 테스트는 `make check` 호출 줄과 check 로그가 없어서 실패한다. 둘째 테스트는 `stdin_bytes=13`이 찍혀서 실패한다.
- [ ] **Step 3: 최소 구현**
  - worktree를 만든 뒤 `(cd "$WT" && make check) >"$check_log" 2>&1 </dev/null`을 돌리고, 종료 코드를 받아 둔다. 실패해도 `die`하지 않고 `WARNING`만 남긴다.
  - `check_summary`는 결과 한 줄을 만든다. 실패하면 로그의 마지막 `CHECK_TAIL_LINES`(상수)줄을 붙인다. 이 요약을 `plan_prompt`와 `change_prompt`에 넣는다.
  - Codex 두 호출과 `claude_review`에 `</dev/null`을 붙인다.
  - check 로그를 `rm -f` 목록과 `Next:` 안내에 더하고, meta에 `check` 줄을 쓴다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: give the reviewer the make check result of the reviewed head and close its stdin" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: z064dkcv" --trailer "Task: 2"`

### Task 3: Comment header from the meta file

**Files:**
- Modify: `scripts/post-review.sh:4-6`, `:17`(usage), `:51-56`(meta 읽기와 머리)
- Modify: `scripts/review-branch.sh:204`(`Next:` 안내에서 `REVIEW_MODEL=` 제거), `Makefile:93`(`review-post` 도움말)
- Modify: `.agents/skills/git-workflow/references/review-and-merge.md:9-13`. `make review`의 `REVIEW_MODEL`·`REVIEW_EFFORT`와 기본값을 적고, `make review-post`에서는 `REVIEW_MODEL=`을 빼고 머리를 meta에서 읽는다고 쓴다.
- Test: `tests/post-review.bats:12-34`, `:36-51`

**Interfaces:**
- Consumes: Task 1·2의 meta 줄(`model`, `effort`, `check`).
- Produces: 머리 `## Agent review R<n>: <reviewer> (<model>, effort <effort>)`, 그리고 다음 줄 ``Base `<sha>`, reviewed head `<sha>`. make check on the reviewed head: <check>.``

- [ ] **Step 1: 실패하는 테스트 작성**
  - `write_reports`가 meta에 `model gpt-6.1-sol`, `effort high`, `check failed (exit 2)`를 쓴다.
  - 머리 테스트(`:21`)는 `REVIEW_MODEL=other-model`을 둔 채 돌린다. 머리가 meta 값(`gpt-6.1-sol, effort high`)과 check 줄을 담는지, 본문에 `$REVIEW_OUT_DIR`가 없는지 본다(`grep -c -F` 결과 0).
  - `:36` 테스트에 case `"old meta|names no model"`을 더한다. meta에 `base`·`head`만 있으면 실패하고 `refute_stub_called '^gh '`가 통과해야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 머리 테스트는 머리가 `other-model`이고 강도가 없어서 실패한다. old meta case는 gh를 불러서 실패한다.
- [ ] **Step 3: 최소 구현.** `sed -n 's/^model //p'` 같은 방식으로 세 줄을 읽는다. 하나라도 비면 `die "<meta> names no model, effort or check result: rerun make review"`로 멈춘다. 머리를 만들고, 스크립트에서 `REVIEW_MODEL`을 읽는 곳을 모두 지운다. 그다음 안내와 문서 세 곳을 고친다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: head review comments with the recorded model, effort and check result" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: z064dkcv" --trailer "Task: 3"`

### Task 4: Local stack owner check

**Files:**
- Create: `scripts/check-local-stack.sh`, `tests/check-local-stack.bats`(`make new-script NAME=check-local-stack`)
- Modify: `Makefile:58-65`. `local-up`과 `local-down`의 첫 줄에서 `scripts/check-local-stack.sh`를 부른다.
- Modify: `tests/stubs/docker:2`, `:9-12`. 인자에 `com.docker.compose.project.working_dir`가 있으면 `DOCKER_STUB_STACK_DIRS`(기본은 빈 값)를 출력하고 끝난다. 다른 `ps` 출력은 그대로 둔다.
- Modify: `AGENTS.md:10`. 문장을 "`local-up` and `local-down` refuse a stack that another worktree started"로 바꾼다. `AGENTS.md` 수정은 이 계획 승인에 포함해 사용자 OK를 받는다.
- Test: `tests/check-local-stack.bats`, `tests/repo-make.bats:55-72`

**Interfaces:**
- Consumes: `compose.yaml:4`의 `name:`(스크립트가 읽으므로 이름의 출처는 한 곳뿐이다).
- Produces: `scripts/check-local-stack.sh`(인자 없음). 소유자가 없거나 자기 디렉터리면 exit 0, 다른 디렉터리면 `die`.

- [ ] **Step 0: 라벨 확인.** 다른 로컬 스택이 없을 때 자기 worktree에서 `make local-up`을 한 번 돌린다. 그다음 `docker inspect`로 `basic-memory-server`의 `com.docker.compose.project.working_dir` 라벨이 이 worktree 경로인지 보고 `make local-down`한다. 경로는 적지 않고, 일치했는지만 Progress log에 `Verified`로 적는다. **Assumption:** Docker Compose v2는 이 라벨에 compose 파일이 있는 디렉터리의 절대 경로를 넣는다.
- [ ] **Step 1: 실패하는 테스트 작성**
  - `tests/check-local-stack.bats`에 테스트 하나를 쓰고 case를 반복한다. 확인할 case:
    - 컨테이너 없음: 통과.
    - 이 저장소를 가리키는 심볼릭 링크 경로: 통과.
    - 존재하는 다른 디렉터리: 실패. 메시지에 그 경로와 `make local-down`이 있어야 한다.
    - 지워진 디렉터리: `WARNING`을 남기고 통과. 그 worktree는 이미 없으므로 스택을 쓰는 곳이 없다.
  - 모든 case에서 docker 호출은 `ps`뿐이어야 한다(`refute_stub_called '^docker compose'`).
  - `tests/repo-make.bats:55` 테스트는 `compose.yaml`도 `LINKED_WT`에 복사한다. 이어서 `DOCKER_STUB_STACK_DIRS=<존재하는 다른 디렉터리>`로 `make local-up`과 `make local-down`이 실패하고 `docker compose` 호출이 0번인지 본다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 테스트는 스크립트가 빈 템플릿이라 실패한다. make 테스트는 `local-up`이 `docker compose`까지 가서 실패한다.
- [ ] **Step 3: 최소 구현**
  - `require_cmd docker`로 시작하고, `compose.yaml`의 `name:`을 읽는다.
  - `docker ps -a --filter label=com.docker.compose.project=<name>`에 working_dir 라벨만 찍는 `--format`을 붙여 디렉터리 목록을 얻는다.
  - 각 디렉터리를 `pwd -P`로 바꾼 값을 `REPO_DIR`의 `pwd -P`와 비교한다.
  - Makefile 두 타깃과 `AGENTS.md:10`을 고친다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: refuse local-up and local-down on a stack another worktree started" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: z064dkcv" --trailer "Task: 4"`

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge). 이 PR의 리뷰는 새 `make review`로 돌린다. 코멘트 머리에 모델·강도·check 결과가 붙었는지, 리뷰에 걸린 시간이 얼마인지 Progress log에 `Verified`로 적는다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 리뷰 정밀도 집계(PR별 accepted·rejected·deferred 수, 평가 D6 L5). 이 계획은 리뷰 입력만 바꾼다. 효과는 이후 PR 몇 개의 지적 수로 판단한다.
- Codex 변경 리뷰(`codex exec review --base`)에 check 결과를 주는 방법. 스펙 5절의 제약 때문에 빠졌다. 필요하면 변경 리뷰 지시를 계획 대조 리뷰 prompt에 합치는 방안을 따로 검토한다.
- Open question 3의 (b)안(worktree마다 project name과 포트). 두 worktree에서 동시에 로컬 스택이 필요해질 때 다시 본다.
- `make sb-fonts LOCAL=1`, `local-verify`, `local-logs`는 검사하지 않는다. `sb-fonts LOCAL=1`은 자기 worktree의 `.local-data/`에 쓰므로, 다른 worktree가 띄운 스택에는 반영되지 않는다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-27 | Verified | 사용자가 이 계획을 승인했다. `AGENTS.md:10` 문장 수정(Task 4)도 승인에 포함된다. |
| 2026-10-27 | Verified | Open question 1: A를 골랐다. 기본 모델은 Codex `gpt-6.1-sol`, Claude `claude-opus-5-5`이다. 기본 강도는 추천한 `high`가 아니라 `low`로 정했다(사용자 결정). |
| 2026-10-27 | Verified | Open question 2: A를 골랐다. 리뷰 worktree에서 `make check`를 직접 돌린다. |
| 2026-10-27 | Verified | Open question 3: (a)를 골랐다. 다른 worktree가 띄운 스택이면 `local-up`·`local-down`이 거부한다. |
| 2026-10-27 | Verified | 계획 작성 뒤 PR #24(`01eb909`)가 `Makefile`의 `local-up`·`local-down` 위치를 81–89행으로 옮겼고, PR #25가 `scripts/post-review.sh:64-65`에 코멘트 머리 공개 텍스트 검사를 넣었다. 각 Task는 이 줄 번호가 아니라 현재 코드 기준으로 고친다. |
| 2026-10-27 | Verified | Task 1 Step 0: Codex config reference는 `model_reasoning_effort` 값으로 `low`, `medium`, `high`, `xhigh`, `max`, `ultra`를 들고 "Available levels depend on the model and client"라고 적는다. Claude Code 2.1.311의 `claude --help`는 `--effort`에 `low, medium, high, xhigh, max`를 받는다. 공통 집합 `low medium high xhigh max`를 `REVIEW_EFFORTS`로 정했다. 계획의 Assumption(`low medium high xhigh`)과 달리 `max`도 두 쪽에 모두 있어 넣었다. 모델이 지원하지 않는 강도는 리뷰어 CLI가 거부한다. |
| 2026-10-27 | Verified | Task 4 Step 0: 다른 로컬 스택이 없을 때(감독 세션의 슬롯 OK 후) `0f79c08`의 임시 worktree에서 `make local-up`을 돌렸다. `basic-memory-server`·`silverbullet-server`가 healthy였고, 두 컨테이너의 `com.docker.compose.project.working_dir` 라벨과 `docker ps --format`의 같은 라벨이 그 worktree 경로와 일치했다(`pwd -P`로 비교). `make local-down` 후 컨테이너는 0개였다. 서브에이전트가 plan worktree의 `Makefile`을 고치던 중이라 임시 worktree를 썼다. |
| 2026-10-27 | Verified | Task 1~4 완료 후 `make check`: exit 0, bats `1..213` 중 `not ok` 0개, total line coverage 89.26%(최소 80%). Task 커밋은 `9bbd9b9`(Task 1), `5b3fe47`(Task 2), `0f79c08`(Task 3), `ec9f154`(Task 4)이다. |
| 2026-10-27 | Verified | 사용자 OK 후 새 `make review BRANCH=plan/z064dkcv-review-and-local-isolation REVIEWER=codex`로 R1을 돌렸다. exit 0, 226초 걸렸다(리뷰 worktree의 `make check` 포함). meta 파일에 `model gpt-6.1-sol`, `effort low`, `check passed`가 기록됐다. 변경 리뷰와 계획 대조 리뷰 모두 지적 0건, `Verdict: mergeable`이었다. `make review-post`가 게시한 PR #29 코멘트 머리는 `## Agent review R1: codex (gpt-6.1-sol, effort low)`이고, 다음 줄에 base·head SHA와 `make check on the reviewed head: passed.`가 붙었다. Review record도 게시했다. |
