---
status: backlog
spec: docs/specs/spec-2026-10-15-script-test-layout.md
---

# 19 Invariant Enforcement Implementation Plan

> 2026-10-22 에이전트 개발 시스템 평가(저장소 밖 기록)에서 나온 백로그 초안입니다. 실행하려면 먼저 사용자 승인이 필요합니다. 설계가 큰 항목은 아니어서 brainstorming과 새 스펙 없이 이 계획으로 시작할 수 있지만, 배경의 Open question 두 개(Task 2의 표지 이름, Task 4의 목록 위치)를 먼저 정합니다. Task 4의 `AGENTS.md` 수정은 그 Task를 시작할 때 따로 OK를 받습니다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** `AGENTS.md`의 불변식 가운데 기계로 볼 수 있는 것은 위반하면 실패하는 검사가 지키고, 테스트 무결성(테스트 삭제와 `skip` 추가)도 같은 방식으로 지킨다. 검사로 볼 수 없는 불변식은 이유와 함께 목록에 남는다.

**Architecture:**
- 새 검사는 지금 자리에 더한다. 저장소 전체 규칙은 `tests/repo-*.bats`(Task 1, 3), PR 단위 규칙은 `pr-rules` 잡의 새 단계와 새 스크립트 `scripts/check-tests.sh`(Task 2)다. 새 잡은 만들지 않는다. 잡을 더하면 ruleset의 필수 검사 목록을 GitHub에서 바꿔야 한다.
- 기존 검사를 넓힐 수 있으면 넓힌다(shebang은 strict mode 검사에, Makefile·Dockerfile 이미지는 compose digest 검사에). 입력만 다른 경우는 반복문 하나로 쓴다(ADR 0004 결정 3).
- 지금 동작을 고정하는 테스트는 쓰자마자 통과한다. 그래서 실패 확인은 계획 17 Task 11처럼 커밋하지 않는 심은 위반으로 한다(`docs/plans/plan-2026-10-21-17-test-cleanup.md:447-454`).

**Spec:** `docs/specs/spec-2026-10-15-script-test-layout.md` (§6 테스트 배치와 이름, §9 검사). Task 2는 `docs/specs/spec-2026-10-13-github-pr-workflow.md` §6(CI의 `pr-rules` 내용)을 고친다. 테스트 허용 범위는 [ADR 0004](../decisions/adr-2026-10-13-0004-test-scope.md) 결정 1~3과 [ADR 0007](../decisions/adr-2026-10-16-0007-structure-checks.md) 결정 2·3이다.

**Sequence:** 계획 19. 다음을 모두 만족한 뒤 시작한다.
- 사용자가 이 계획과 Open question 1·2를 승인했다. 앞선 계획에 기대지 않는다.
- 계획 18(public text guard)도 `.github/workflows/pr-rules.yml`과 아마 `scripts/check-pr.sh`를 고친다. 둘 중 늦게 병합되는 쪽이 `git merge origin/main`으로 단계 목록과 `check-pr.sh` 충돌을 푼다. 계획 18이 먼저 병합되면 Task 4 목록의 VM IP·세션 링크 행을 그 결과대로 적는다.

## 배경

- **Reported (2026-10-22 평가):** D3은 2.5/5다. 사용자가 치는 Make 타깃 다섯 개(`help`, `fmt`, `test`, `local-down`, `local-logs`)를 실행하는 테스트가 없어서다. 평가는 이 다섯 개만 테스트하면 D3이 5.0이 된다고 본다.
- **Reported (2026-10-22 평가):** D4의 엄격 기준 불변식 비율은 10/31(32%)이다. `make check`를 통과한 주입 위반은 다른 스크립트의 raw `ssh -L`, `common.sh`를 source하지 않는 최상위 스크립트, `Makefile`의 digest 없는 이미지, 불변식 테스트 삭제와 `skip` 추가다. PR #16의 220 → 138 테스트 감소는 승인된 정리였지만 기계 신호 없이 병합됐다.
- **Verified (2026-10-22, `7a3748d`):** 다섯 타깃은 `Makefile:34-35`, `:44-45`, `:47-48`, `:64-65`, `:67-68`의 인라인 레시피다. `tests/repo-make.bats`의 `make_in`(`:21-24`)은 `local-up`(`:55`), `verify`·`probe`(`:74`)만 실행한다.
- **Verified (2026-10-22):** `git grep -c '^@test '`의 합은 `47dbbc7` 220, `6452041` 138, 지금 139다(PR #10이 하나 더함). `tests/`에 `skip` 줄은 없다.
- **Verified (2026-10-22):** 지금 트리는 Task 3의 네 규칙을 이미 지킨다.
  - 추적되는 셸 파일 92개 가운데 첫 줄이 `#!/usr/bin/env bash`나 `#!/usr/bin/env bats`가 아닌 것은 source되는 `tests/helpers.bash`뿐이다.
  - 최상위 스크립트 21개가 모두 `"$SCRIPT_DIR/lib/<topic>.sh"`를 source한다.
  - `-L`은 `scripts/lib/vm.sh:103-104`의 `-L "$(forward_spec …)"` 두 곳뿐이다.
  - `Makefile:25-26`과 `tools/Dockerfile:2,4`는 digest로 고정돼 있다. `Makefile:27`의 `TOOLS_IMAGE := bm-tools:local`은 `Makefile:38`이 직접 빌드한다.
- **Verified (2026-10-22):** 평가가 제안한 "모든 `-L`" 검사를 그대로 쓰면 `scripts/remote/provision-vm.sh:96,119`의 `curl -fsSL`도 걸린다. 검사는 ssh에 한정한다(Task 3).
- **Verified (2026-10-22):** ADR 0004 대체 범위(`docs/decisions/adr-2026-10-13-0004-test-scope.md:59`)는 "모든 Make 타깃이 help에 나옴" 검사를 `##`·`.PHONY` 검사(`tests/repo-make.bats:26`)로 바꿨다. 그래서 `help` 테스트는 대표 한 줄만 본다.
- **Verified (2026-10-22):** 레이아웃 스펙 §1 사용자 결정 2(강제 수준 B: 위치·이름·짝 파일만)는 구조 검사의 범위다. Task 3의 shebang, digest, `-L` 검사는 그 결정이 아니라 ADR 0004 결정 1의 "AGENTS.md 불변식: 127.0.0.1 바인딩, digest 고정, 스크립트 머리 규칙"에 기댄다. source 검사는 §9 항목 3(라이브러리의 `common.sh`)을 최상위 스크립트로 넓힌 것이다.
- **Verified (2026-10-22):** `AGENTS.md`는 9,841바이트이고 한도는 24,000바이트다(`tests/repo-config.bats:6`, `:135-140`). 평가가 적은 `:118`은 PR #10 뒤 `:135`로 밀렸다.
- **Assumption:** 평가의 B2-M 표로 다시 세면 Task 3 뒤 행 5·6·7·8이 E가 되어 14/31(45%), 계획 18의 두 행(VM IP, 세션 링크)까지 더하면 16/31(52%)이다. 평가 보고서의 "약 17/31"과 한 행 차이가 난다. Task 2는 행 2(테스트 약화 금지)를 N에서 P로만 올린다.
- **Open question 1:** Task 2의 표지. 추천은 `Tests-Removed: <이유>` 하나로 `@test` 감소와 새 `skip`을 모두 덮는 것이다. 기존 트레일러(`Assisted-by`, `Review-Finding`)와 같은 꼴이고, PR 본문 트레일러 문단에 있으면 squash 커밋에 남아 `main` 이력에서 이유를 찾을 수 있다. 대안은 `Tests-Skipped`를 따로 두는 것이다. 구분은 되지만 표지가 둘이 된다.
- **Open question 2:** Task 4의 prose-only 목록 위치.
  - A(추천): 새 ADR에 두고 `AGENTS.md` 제목 아래 한 줄로 가리킨다. 네 도구가 매 세션 읽는 `AGENTS.md`를 짧게 두고, 검사가 생겨 목록이 바뀌어도 `AGENTS.md`를 고칠 필요가 없다. 크기 한도 때문은 아니다(9,841/24,000바이트).
  - B: `AGENTS.md` Invariants 아래 절. 한 파일에서 보이지만 매 세션 컨텍스트가 늘고, 목록이 바뀔 때마다 `AGENTS.md` 수정 OK가 필요하다.

## Global Constraints

- ADR 0004 결정 1: 새 테스트는 AGENTS.md 불변식, 데이터 안전, 스크립트·Make 진입점의 대표 성공 경로 1개, 조용히 넘어갈 실패 경로, 머지 절차가 기대는 Git 정책 가운데 하나를 지킨다. 결정 2: 중복, 문구·형식만 보는 테스트, 스텁·도우미 자체, 상수 되풀이, usage 문구 테스트는 쓰지 않는다.
- ADR 0007 결정 2: 섹션 이름, 문장, 레이블, 언어를 확인하는 테스트는 쓰지 않는다(Task 4에 새 테스트가 없는 이유). 결정 3: 실패 메시지는 파일, 어긋난 값, 허용 값, 고칠 곳을 함께 출력한다.
- 레이아웃 스펙 §6: 저장소 전체 규칙은 `tests/repo-<topic>.bats`에 둔다. 새 스크립트는 `make new-script`로 만들고 짝 테스트 `tests/<name>.bats`를 둔다.
- 워크플로: `tests/repo-github.bats:9-25`(표현식은 `env:`로만 넘김, 여러 줄 `run:` 금지, 읽기 권한만, 잡 이름 없음)와 `:27-44`(ruleset 필수 검사 = 워크플로 잡 id). 새 단계는 기존 `pr-rules` 잡 안에 둔다.
- `AGENTS.md` 수정은 사용자 OK가 필요하고, 크기는 24,000바이트 이하로 둔다.
- 테스트는 `make test`나 `make check`로만 돌린다. 실제 트리에서 `make fmt`를 테스트용으로 돌리지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 19`, `Task: <N|review|none>`.

## Review Focus

1. ssh 검사의 경계: 연속 줄의 단독 `-L`(`scripts/lib/vm.sh:103-104` 모양), `ssh -NL` 같은 묶음 옵션, `-o LocalForward=`는 잡고, ssh가 없는 줄의 `curl -fsSL`은 잡지 않는다. 기대 동작은 앞의 셋이 파일:줄과 함께 not ok, 마지막은 통과다. Task 3이 심은 위반과 실제 트리 통과로 고정한다.
2. 테스트 수의 기준점: 브랜치가 `git merge origin/main`으로 받은 main 쪽 테스트 삭제는 PR 탓이 아니므로 기준은 `git merge-base`다. 하나를 지우고 하나를 더한 PR은 수가 같아 통과한다. 이것은 알려진 한계로 Task 2의 ADR에 적는다. Task 2의 통과 반복문이 병합 경우를 고정한다.
3. 표지의 모양: 값이 빈 `Tests-Removed:`, 트레일러 문단이 아닌 본문 중간의 `Tests-Removed:`는 표지가 아니다(`Assisted-by`와 같은 파싱). Task 2의 실패 반복문이 고정한다.
4. 변수 없이 레시피에 쓴 이미지(`$(DOCKER_RUN) <image>:<tag> …`): 기대 동작은 실패다. Task 3의 digest 검사가 `$(DOCKER_RUN)` 다음 단어도 본다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `tests/repo-make.bats` | 다섯 타깃의 대표 성공 경로 | 1 |
| `scripts/check-tests.sh` (새 파일) | merge-base 대비 `@test` 수와 새 `skip`, `Tests-Removed` 표지 | 2 |
| `tests/check-tests.bats` (새 파일) | 위 스크립트의 짝 테스트 | 2 |
| `scripts/lib/git.sh`, `scripts/check-pr.sh`, `tests/lib-git.bats`, `tests/check-pr.bats` | PR 본문 트레일러 파싱을 라이브러리로 옮김 | 2 |
| `.github/workflows/pr-rules.yml` | 새 단계 "Test count and skips" | 2 |
| 새 ADR, `docs/specs/spec-2026-10-13-github-pr-workflow.md`(`amended-by`), `.agents/skills/git-workflow/SKILL.md`, `docs/ARCHITECTURE.md` | 결정 기록과 동반 문서 | 2 |
| `tests/repo-scripts.bats` | shebang, 최상위 스크립트 source, ssh `-L` | 3 |
| `tests/repo-config.bats` | compose·Makefile·Dockerfile 이미지 digest | 3 |
| `AGENTS.md`, 새 ADR 또는 `AGENTS.md` 절 | 제목의 과장 수정, prose-only 목록 | 4 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/19-invariant-enforcement` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Make target tests

**Files:**
- Modify: `tests/repo-make.bats` (새 테스트 두 개를 `:88` 뒤에)

- [ ] **Step 1: 테스트 작성.** `linked_worktree_with_makefile`(`:6-9`), `make_in`(`:21-24`), `setup_stubs docker`를 쓴다. 이미지 이름 같은 기대값은 `Makefile`에서 읽는다(상수 되풀이 금지).
  - "make help prints each target with its ## description": `make_in "$LINKED_WT" help`가 성공하고, 출력에 `check` 줄과 `Makefile`의 `check:` 줄에서 읽은 설명이 있다. 타깃 전체를 세지 않는다(배경의 ADR 0004 대체 범위).
  - "make fmt, test, local-down and local-logs run their docker command in the checkout they run from": 경우마다 하위 셸에서 fixture를 새로 만들고 `make_in` 뒤 stub log를 본다.
    - `fmt`: fixture에 추적되지 않은 `probe.sh`를 둔다. 한 줄에 `-v <LINKED_WT>:/repo`, `SHFMT_IMAGE` 값, `-w probe.sh`가 있다. docker는 stub이고 마운트는 fixture라서 실제 트리는 바뀌지 않는다.
    - `test`: `docker build -q -t <TOOLS_IMAGE> tools`가 `<TOOLS_IMAGE> bats tests`보다 먼저다(`assert_log_order`).
    - `local-down`은 정확히 `docker compose -f compose.yaml down`, `local-logs`는 정확히 `docker compose -f compose.yaml logs --tail=200`이다.
- [ ] **Step 2: 실패 확인(심은 결함, 커밋하지 않음).** `Makefile`에 결함을 하나씩 심는다: `help`의 awk `FS`를 깨뜨림, `fmt`의 `-w`를 `-d`로, `local-down`의 `down`을 `stop`으로, `local-logs`의 `--tail=200` 삭제, `test`의 `tools-image` 의존 삭제.
  Run: `make test`
  Expected: 경우마다 새 테스트만 not ok이고 메시지가 그 경우를 말한다. 되돌린 뒤 `git status --short`가 비어 있다.
- [ ] **Step 3: 최소 구현.** 없음. 테스트가 이미 있는 레시피를 실행한다.
- [ ] **Step 4: 통과 확인.**
  Run: `make check`
  Expected: exit 0, ok 141, not ok 0, 커버리지 80% 이상
- [ ] **Step 5: 커밋.** `git commit -m "test: run the help, fmt, test, local-down and local-logs targets" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 19" --trailer "Task: 1"`

### Task 2: Test integrity guard

**Files:**
- Create: `scripts/check-tests.sh`, `tests/check-tests.bats` (`make new-script NAME=check-tests`)
- Create: ADR (`make new-doc TYPE=adr SLUG=test-integrity-guard`)
- Modify: `scripts/lib/git.sh` (`scripts/check-pr.sh:15-19`의 `trailer_values`와 `:46-50`의 squash 메시지 트레일러 파싱을 옮겨 받음, 함수 색인 갱신), `scripts/check-pr.sh`, `tests/lib-git.bats`(옮긴 파싱 경우), `tests/check-pr.bats:12`
- Modify: `.github/workflows/pr-rules.yml` (`:27-31` 뒤에 단계 하나)
- Modify: `docs/specs/spec-2026-10-13-github-pr-workflow.md` (front matter `amended-by`만), `.agents/skills/git-workflow/SKILL.md:32`, `docs/ARCHITECTURE.md:53`

**Interfaces:**
- Produces: `scripts/check-tests.sh BASE`(env `PR_TITLE`, `PR_BODY`). 통과하면 exit 0과 `OK:` 한 줄, 위반이면 `report_problems`로 목록과 exit 1. `scripts/lib/git.sh`의 PR 본문 트레일러 파서(이름은 구현 때 정함)와 `trailer_values KEY TRAILERS`.
- Task 4가 쓰는 이름: 트레일러 `Tests-Removed` (Open question 1).

동작:
1. `git merge-base BASE HEAD`가 기준점이다. 없으면 고칠 방법과 함께 `die`.
2. 기준점과 `HEAD`에서 `tests/*.bats`의 `^@test ` 수를 센다(`git grep -c`; 맞는 줄이 없는 리비전은 0, git 오류는 `die`).
3. `git diff -U0 <기준점> HEAD -- 'tests/*.bats' tests/helpers.bash`에서 더해진 `skip` 줄(`^\+[[:space:]]*skip([[:space:]]|$)`)을 파일:줄로 모은다.
4. 수가 줄었거나 새 `skip`이 있으면 PR 본문 트레일러 문단의 `Tests-Removed`에 빈 값이 아닌 이유가 있어야 한다. 없으면 "N -> M", `skip` 줄, 고칠 방법("PR 본문 마지막 문단에 `Tests-Removed: <reason>`을 더한다. 본문을 고치면 `pr-rules`가 다시 돈다")을 출력한다.
5. `pr-rules.yml`의 새 단계 "Test count and skips"는 "PR title and trailers" 단계(`:27-31`)처럼 `env:`로 `PR_TITLE`과 `PR_BODY`를 받고 `scripts/check-tests.sh origin/main`을 실행한다.

- [ ] **Step 1: 실패하는 테스트 작성.** `tests/check-tests.bats`는 `tests/check-git.bats:4-7`처럼 `init_git_repo`로 시작하고, main에 `@test` 두 개짜리 `tests/a.bats`를 커밋한다.
  - "passes when the branch keeps or adds tests, also after it merges a main that removed one": 경우 반복문(그대로, 하나 더함, main이 하나 지운 뒤 브랜치가 main을 병합).
  - "fails when the branch removes a @test or adds a skip unless the PR body's trailer paragraph carries Tests-Removed with a reason": 지움 → 실패하고 출력에 `2 -> 1`; `skip "x"` 더함 → 실패하고 출력에 `tests/a.bats:<줄>`; 지움 + 트레일러 문단의 `Tests-Removed: merged into a loop` → 통과; 빈 `Tests-Removed:` → 실패; 본문 중간 문단의 표지 → 실패.
  - `tests/lib-git.bats`: `tests/check-pr.bats:12`의 파싱 경우(CRLF, 가로줄 위의 트레일러, 트레일러만 있는 본문)를 옮긴 파서에 대해 검사한다(레이아웃 스펙 §7.2: 라이브러리 함수 동작은 그 짝 테스트에서 한 번). `check-pr.bats:12`는 대표 경우 하나만 남긴다.
- [ ] **Step 2: 실패 확인.**
  Run: `make test`
  Expected: `check-tests.bats`의 두 테스트는 템플릿의 `die "not implemented"`로, `lib-git.bats`의 새 테스트는 파서가 아직 없어서 not ok다.
- [ ] **Step 3: 최소 구현.** 위 동작 1~5. 파서를 옮긴 뒤 `check-pr.sh`가 그것을 부른다. ADR에는 표지 이름, merge-base 기준, `@test` 감소와 `skip`을 한 표지로 덮는 이유, 알려진 한계(지우고 같은 수를 더함, 단언 약화)를 적고 PR 워크플로 스펙 §6을 일부 대체한다고 쓴다. 같은 커밋에서 스펙에 `amended-by`를 단다. `git-workflow` 스킬 `:32`의 `pr-rules` 설명과 `docs/ARCHITECTURE.md:53`의 도구 목록에 새 검사를 더한다.
- [ ] **Step 4: 통과 확인.**
  Run: `make check`
  Expected: exit 0, not ok 0, 커버리지 80% 이상(`scripts/check-tests.sh`도 실행됨)
  Run: `PR_TITLE='test: probe' PR_BODY="$(printf 'Assisted-by: <tool> <model>\nPlan: 19\n')" scripts/check-tests.sh origin/main` (값은 실제 도구로)
  Expected: exit 0, `OK:` 줄에 늘어난 수
  push 뒤: 이 PR에서 `pr-rules`가 새 단계와 함께 통과한다.
- [ ] **Step 5: 커밋.** `git commit -m "ci: fail pull requests that remove or skip tests without a Tests-Removed reason" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 19" --trailer "Task: 2"`. 파서 이동을 따로 커밋하면 `refactor:`로 같은 트레일러를 단다.

### Task 3: Static invariant checks

**Files:**
- Modify: `tests/repo-scripts.bats` (`:44-55`의 strict mode 테스트를 넓히고 이름을 바꿈, `:15` 옆에 패턴 상수, `:108` 뒤에 새 테스트 두 개)
- Modify: `tests/repo-config.bats` (`:9-10`의 패턴 상수, `:22-35`의 digest 테스트를 넓히고 이름을 바꿈)

동작:
1. "every executable shell file starts with #!/usr/bin/env bash and enables strict mode": `:44-55`와 같은 파일 집합에서 첫 줄이 정확히 `#!/usr/bin/env bash`다.
2. "every script in scripts/ sources common.sh or a scripts/lib library": `scripts/*.sh`마다 주석이 아닌 source 줄이 있고, 그 경로가 `/lib/<topic>.sh`로 끝나며 `scripts/lib/<topic>.sh`가 있다. `:99-108`(라이브러리는 `common.sh`를 source)과 합쳐 전이적으로 성립한다.
3. "every ssh -L in scripts/ and the Makefile goes through forward_spec": 주석이 아닌 줄에서 (가) `"$(forward_spec `이 바로 뒤에 오지 않는 단독 `-L`, (나) `ssh`가 있는 줄의 `L`을 포함한 묶음 옵션(`-NL`), (다) `LocalForward`를 위반으로 보고 파일:줄과 "`forward_spec`이나 `tunnel_args`(`scripts/lib/vm.sh:89-106`)로 만든다"를 출력한다.
4. "every image in compose.yaml, the Makefile and tools/Dockerfile is pinned by digest": compose는 지금 검사 그대로다. `Makefile`의 `^[A-Z_]+_IMAGE := ` 값은 `@sha256:<64 hex>`로 끝난다. 단, `docker build … -t $(VAR)` 레시피가 빌드하는 변수는 빼고, 그 변수는 `Makefile`에서 읽는다. `$(DOCKER_RUN)` 다음 단어는 `$(…_IMAGE)` 변수다. `tools/Dockerfile`의 `FROM`은 모두 `<image>@sha256:<64 hex>`다.

- [ ] **Step 1: 검사 작성.** 위 1~4.
- [ ] **Step 2: 실패 확인(심은 위반, 커밋하지 않음).**
  - 평가의 주입: `scripts/show-status.sh`에 `ssh -N -L 0.0.0.0:18737:127.0.0.1:8737 "$BM_VM_HOST"`를 부르는 함수, 짝 테스트까지 갖춘 새 `scripts/show-uptime.sh`(source 없음), `Makefile:26`의 digest 삭제
  - 더하는 위반: `ssh -NL …` 한 줄, `-o LocalForward=…` 한 줄, `scripts/show-logs.sh` 첫 줄을 `#!/bin/bash`로, 없는 `lib/nope.sh`를 source하는 스크립트, `tools/Dockerfile`의 `FROM debian:13`, 레시피에 변수 없이 쓴 이미지
  Run: `make test`
  Expected: 네 검사가 모두 not ok이고, 메시지가 심은 파일:줄을 하나씩 말한다. `scripts/remote/provision-vm.sh:96,119`는 나오지 않는다. 되돌린 뒤 `git status --short`가 비어 있다.
- [ ] **Step 3: 최소 구현.** 없음. 지금 트리는 네 규칙을 지킨다(배경).
- [ ] **Step 4: 통과 확인.**
  Run: `make check`
  Expected: exit 0, ok 143(Task 2의 테스트 수 별도), not ok 0, 커버리지 80% 이상
- [ ] **Step 5: 커밋.** `git commit -m "test: check shebangs, script sources, ssh forwards and tool image digests" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 19" --trailer "Task: 3"`

### Task 4: AGENTS.md heading and prose-only invariants

**Files:**
- Modify: `AGENTS.md:12` (제목), `AGENTS.md:12-18` (목록을 가리키는 한 줄, `Tests-Removed` 안내)
- Create: ADR(`make new-doc TYPE=adr SLUG=prose-only-invariants`, Open question 2의 A안) 또는 `AGENTS.md` Invariants 아래 절(B안)

**Interfaces:**
- Consumes: Task 1~3의 검사 이름과 Task 2의 트레일러 이름

- [ ] **Step 1: 사용자 OK.** 바꿀 제목과 목록 위치(Open question 2)를 보여 주고 OK를 받는다.
- [ ] **Step 2: 제목 수정.** "enforced by the tests/repo-*.bats files"를 뺀다. 지금도 검사는 `repo-*.bats`만이 아니라 짝 테스트(`tests/open-tunnel.bats:19`), `tools/coverage.sh:20-29`, CI `pr-rules`, ruleset에 있고, 일부 규칙은 어디에도 없다. 예: `## Invariants (never weaken a test to make it pass; a pull request that removes or skips tests carries Tests-Removed: <reason>)`, 마지막 항목은 "`make check` and CI `pr-rules` check these rules; the rules no check can see, and why, are in <ADR 링크>". `script-authoring` 스킬 `:16`이 이 절을 "AGENTS.md Invariants"로 부르므로 그 이름은 유지한다.
- [ ] **Step 3: prose-only 목록.** 그날 트리를 기준으로 한 행씩 확인해 적는다. 시작 목록(`AGENTS.md` 행: 이유):
  - `:9` 커밋마다 `make check`: CI가 PR head에서 같은 명령을 돌린다. 커밋마다 막으려면 도구별 hook이 필요하다.
  - `:12` 테스트 약화 금지: Task 2는 삭제와 `skip`만 본다. 약해진 단언은 리뷰가 본다.
  - `:13` 공개 인그레스 0, ssh 모드의 방화벽 규칙, VM당 한 모드: VM·클라우드 상태라서 `make verify`/`make probe`와 `docs/runbooks/rbk-2026-10-12-operations.md`의 노출 점검이 본다. `make check`는 볼 수 없다.
  - `:14` 릴리스 노트를 읽은 뒤에만 고정 변경, `bm-upgrade`로만 업그레이드: 산출물이 남지 않는 절차다.
  - `:15` `die`와 고칠 방법이 있는 메시지, `:16` 빈 배열 전개와 `|| exit 1`, `:17` 이름 붙인 상수와 비밀값 비출력: 판단이 필요하거나 grep으로 정할 수 없다. 비밀값은 기존 경로만 동작 테스트가 있다.
  - `:18` 테스트 먼저: 순서는 이력에만 있다. Progress log와 리뷰가 본다.
  - `:21-27` Safety의 실행 규칙: 저장소 산출물이 아니라 에이전트의 행동이다.
  - `:28` VM IP, `:35` 세션 링크: 계획 18의 결과대로 적는다.
  - `:32` `main` 밖의 force-push·rebase, `git gc`, 다른 브랜치 삭제: ruleset은 `main`만 지킨다.
  - `:33` `Review-Finding` 형식: Follow-ups.
  - `:39-40` 레이블과 언어: ADR 0007 결정 2가 검사를 금지한다.
- [ ] **Step 4: 통과 확인.** 새 테스트는 없다(ADR 0007 결정 2).
  Run: `make check`
  Expected: exit 0. 문서 검사(링크, docs 경로, front matter)와 `AGENTS.md` 크기 검사가 통과한다. `wc -c AGENTS.md`가 24,000 이하다.
- [ ] **Step 5: 커밋.** `git commit -m "docs: say which invariants checks enforce and list the prose-only ones" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 19" --trailer "Task: 4"`

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- `AGENTS.md:33`의 `Review-Finding`/`SDD-T…` 형식: `check-git.sh`가 값이 있을 때 형식을 보면 싸게 E가 된다. 다만 **Verified (2026-10-22):** 이력의 값에 `SDD-final-I1` 같은 것이 있어 `SDD-T<task>-F<n>`과 맞지 않으므로 형식부터 정해야 한다.
- 지우고 같은 수를 더하는 PR, 약해진 단언: 이름 기준 비교나 변이 검사는 비용이 커서 미룬다.
- `COVERAGE_MIN`(`Makefile:28`)이나 `tools/coverage.sh`를 낮추는 변경: 무결성의 다른 경로이지만 이 계획 밖이다.
- 공개 텍스트(IP, tailnet 이름, 세션 링크, 도구 서명 줄): 계획 18.
- `check-pr.sh`와 `check-tests.sh`를 로컬에서 부르는 Make 타깃: 지금은 usage 줄에만 있다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
