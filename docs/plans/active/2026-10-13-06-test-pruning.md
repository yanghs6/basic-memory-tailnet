# 06 Test Pruning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** bats 테스트 237개 중 꼭 필요한 147개만 남긴다. 65개는 지우고, 25개는 같은 동작을 검사하는 대표 테스트에 병합한다. AGENTS.md 불변식, 데이터 안전, 각 진입점의 대표 성공 경로, 조용한 실패·실제 회귀, Git·리뷰 정책을 지키는 테스트는 하나도 잃지 않는다.

**Architecture:**
- 테스트 파일별로 판정한 목록(아래 Task 1~4)을 그대로 적용한다. 판정 기준은 "판정 기준" 절에 있다.
- Task 1~4는 서로 다른 파일만 바꾼다. 그래서 구현 서브에이전트 4개를 각자의 격리 worktree에서 병렬로 돌린다.
- 구현 에이전트마다 별도의 검증 에이전트를 붙인다. 검증 에이전트는 파일을 고치지 않고 판정한다.
- 컨트롤러가 네 커밋을 계획 브랜치로 cherry-pick한다. 그다음 ADR과 Progress log를 쓰고, 브랜치 전체를 검증 에이전트 하나가 다시 본다.

**Tech Stack:** bats-core 1.14.0 + bats-support/assert, kcov(`make coverage`), shellcheck 0.11.0, shfmt 3.12.0, GNU Make

**Spec:** 별도 스펙 없음. 이 계획의 "판정 기준"과 Task별 목록이 2026-10-13 사용자에게 제시한 조정안이다. 사용자는 "테스트 조정을 진행하세요"로 진행을 지시했다. 아래 두 선택지는 사용자가 따로 고르지 않아 추천안을 적용했다.
- Q1-B: 문서 정합성 검사 중 상대 링크 검사(`repo.bats` L233)만 남긴다.
- Q2-A: ADR 0003 결정 7이 `tests/skills.bats`에 맡긴 스킬 규칙 검사는 모두 남긴다.

**Sequence:** 계획 6. 전제: `main` 5561329. 계획 05(`plan/05-vm-rollout`)는 tests를 바꾸지 않으므로 병행할 수 있다.

## 판정 기준

**유지 (하나라도 해당하면 남긴다)**
- K1 AGENTS.md 불변식: 127.0.0.1 바인딩, Funnel 금지, 공개 인그레스 0, digest 고정, 비밀값 비출력(`mask`), macOS bash 3.2, 스크립트 머리 규칙
- K2 데이터 안전: 백업 삭제·덮어쓰기 금지, `.prev-*` 보존, restore 확인, 롤백, 노트 유실 방지
- K3 각 스크립트·Make 진입점의 대표 성공 경로 1개
- K4 조용히 넘어가거나 파괴적으로 끝날 실패 경로, 실제로 일어난 회귀
- K5 머지 절차가 기대는 Git·리뷰 정책

**삭제·병합 후보**
- R1 다른 테스트와 같은 동작을 검사하는 중복 테스트
- R2 문구·형식만 확인하는 테스트(`set -e`만으로도 실패는 그대로 일어남)
- R3 스텁·헬퍼 자체를 검사하는 테스트
- R4 입력값만 바꾼 변형 테스트 → 대표 테스트의 반복문으로 병합
- R5 상수·문서 문구를 되풀이하는 변경 감지 테스트
- R6 usage 문구

## Global Constraints

- AGENTS.md: "never weaken a test to make it pass". 이 계획은 유지 목록의 테스트 본문을 바꾸지 않는다. 바꿔도 되는 것은 병합 대상 테스트에 입력값과 assertion을 더하는 것뿐이다.
- 병합은 원래 테스트의 **입력값과 assertion을 모두 옮긴다**. 병합하려면 대상 테스트의 구조를 크게 바꿔야 하면, 병합하지 말고 두 테스트를 그대로 둔 뒤 보고한다.
- 삭제한 테스트만 쓰던 헬퍼 함수, 파일 상수, `setup` 줄, 스텁 옵션은 함께 지운다. 아직 다른 곳에서 쓰는 것은 지우지 않는다. 지우기 전에 `grep -rn '<이름>' tests/`로 사용처를 확인한다.
- `scripts/`, `Makefile`, `compose.yaml`, 스킬, AGENTS.md는 바꾸지 않는다. Task 5의 ADR과 이 계획 파일만 예외다.
- `make check`(lint + 전체 테스트 + 커버리지 80% 이상, `scripts/` 아래 모든 실행 파일이 최소 한 테스트에서 실행됨)가 통과해야 한다.
- 커밋 트레일러: `Assisted-by: claude-code claude-opus-5-5`, `Plan: 06`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`는 쓰지 않는다.
- 격리 worktree에 `.env`나 `backups/`를 만들거나 복사하지 않는다.

## Review Focus

1. **병합하면서 입력값이 빠져 회귀 방지력이 사라짐.** 예: `999.1.1.1`, 절대 경로 아카이브, tailscale이 없는 새 VM. → 각 Task의 "병합" 항목에 옮길 입력값을 적었다. 검증 에이전트가 grep으로 하나씩 확인한다.
2. **두 파일이 서로를 "남는 쪽"으로 지목해 동작이 어느 테스트에도 남지 않음.** → 아래 "교차 파일 생존 목록"에 남는 쪽을 고정했다. 최종 검증 에이전트가 목록 전체를 확인한다.
3. **불변식(K1) 테스트가 지워짐.** → 최종 검증 에이전트가 K1 목록(Task 5 Step 4)이 남았는지 확인한다.
4. **고아 헬퍼·상수·스텁 옵션이 남거나, 아직 쓰는 것을 지움.** → 각 Task 검증에서 grep으로 확인한다. `make lint`가 스텁과 `helpers.bash`의 문법 오류를 잡는다.
5. **문서가 지워진 테스트를 계속 "검사됨"이라고 말함.** 예: `skill-authoring`의 "(tested)", ADR 0003 결정 7. → 최종 검증 에이전트가 문서에 나오는 테스트 이름과 "(tested)" 규칙을 대조한다.

## 교차 파일 생존 목록

| 동작 | 지우는 테스트 | 남기는 테스트 |
|---|---|---|
| `.env` 변수 누락 시 실패와 main 체크아웃 안내 | `common.bats` L40 | `vm_ops.bats` L45 (Task 2가 안내 assertion을 옮김) |
| 누락 명령 이름 출력 | `common.bats` L28 | `review_bash_guard.bats` L135 |
| `make probe`는 노트를 쓰지 않음 | `verify_mcp.bats` L130 | `vm_ops.bats` L126 |
| 아카이브가 없을 때 restore 실패 | `main_checkout.bats` L113 | `backup_restore.bats` L291 (본문 그대로) |
| `main_checkout_root` | `common.bats` L123, L130, L137, L144 | `main_checkout.bats` L71, L92, L101 |
| 모델 캐시 제외 | `backup_restore.bats` L76, `common.bats` L103 | `backup_restore.bats` L83 |
| `manifest_cmd`의 find 실패 | `common.bats` L114 | `backup_restore.bats` L184 |
| `make help` 출력 | `repo.bats` L64, `main_checkout.bats` L61 | 없음 (R6, 의도적으로 둘 다 지움) |

## File Structure

```
tests/backup_restore.bats tests/common.bats tests/main_checkout.bats          Task 1
tests/vm_ops.bats tests/bootstrap.bats tests/stubs/{id,fallocate,mkswap,free}  Task 2
tests/verify_mcp.bats tests/repo.bats tests/cloud_neutral.bats                Task 3
tests/check_git.bats tests/review.bats tests/review_bash_guard.bats tests/skills.bats  Task 4
docs/decisions/0004-test-scope.md, 이 계획 파일                                 Task 5 (컨트롤러)
```

줄 번호(Lnn)는 `main` 5561329 기준으로, 각 `@test` 줄의 번호다. 작업할 때는 줄 번호가 아니라 테스트 이름으로 찾는다.

---

### 시작: 브랜치와 worktree (컨트롤러)

- [x] `git worktree add .claude/worktrees/plan-06-test-pruning -b plan/06-test-pruning main` (5561329)
- [ ] 첫 커밋으로 이 계획 파일을 `docs/plans/active/`에 추가한다.

```bash
git add docs/plans/active/2026-10-13-06-test-pruning.md
git commit -m "docs: add plan 06 test pruning" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: none"
```

### 병렬 실행 방식 (컨트롤러)

- Task 1~4는 파일이 겹치지 않으므로 구현 에이전트 4개를 동시에 띄운다. 각 에이전트는 Agent `isolation: "worktree"`로 실행한다.
- 구현 에이전트는 먼저 `git switch -c plan/06-test-pruning-t<N> <계획 커밋 SHA>`를 실행한다.
- 구현 에이전트가 끝나면 그 Task 전용 **검증 에이전트**를 따로 띄운다. 검증 에이전트는 파일을 고치지 않는다.
  - 검증 에이전트는 커밋 diff를 이 계획과 대조한다.
  - 구현 에이전트의 worktree에서 `make -C <worktree> check`를 직접 실행한다.
  - 판정은 PASS 또는 FAIL이고, FAIL이면 근거 `path:line`을 붙인다.
- FAIL이면 같은 구현 에이전트에게 수정을 맡기고, 검증 에이전트를 새로 띄워 다시 판정한다.
- 네 Task가 모두 PASS하면 컨트롤러가 `git cherry-pick`으로 계획 브랜치에 옮긴다(Task 5).

---

### Task 1: backup_restore, common, main_checkout

**Files:**
- Modify: `tests/backup_restore.bats`, `tests/common.bats`, `tests/main_checkout.bats`

**Interfaces:**
- Produces: `common.bats` L40을 지운다. 그 안내 assertion은 Task 2가 `vm_ops.bats` L45로 옮긴다.
- Produces: `main_checkout.bats` L113을 지운다. `backup_restore.bats` L291은 본문을 바꾸지 않는다.

- [ ] **Step 1: `tests/backup_restore.bats` (28 → 23)**
  - 삭제:
    - L76 `backup excludes the model cache from the tar command`
    - L309 `restore prints usage without an argument`
    - L390 `restore on a VM without previous data says nothing is live when it fails before the swap`
  - 병합:
    - L217 `restore works on a fresh VM without existing data` → L423 `restore writes the VM .env and succeeds on a recreated VM with no data, compose or .env`
      - L217의 복원 내용 assertion(`restored.md`의 내용 확인)을 L423에 옮긴 뒤 L217을 지운다.
      - L423의 아카이브에 그 파일이 없으면 L217의 아카이브 준비 줄도 함께 옮긴다.
    - L277 `restore refuses an archive holding an absolute path before touching the VM` → L263
      - L263을 `../` 경로와 절대 경로 두 입력을 도는 반복문으로 바꾼다.
      - 두 입력 모두 원래 assertion을 지킨다: 실패, 그리고 ssh 호출 없음.
      - 이름은 `restore refuses an archive holding a ../ or absolute path before touching the VM`으로 바꾼다.
  - L291은 본문을 바꾸지 않는다(교차 파일 생존 목록).
- [ ] **Step 2: `tests/common.bats` (20 → 3)**
  - 유지:
    - L53 `mask hides short values completely`. L48 `mask keeps only a 4-character prefix of long values`의 assertion을 여기에 합친다. 이름은 `mask hides short values completely and keeps only a 4-character prefix of long ones`로 바꾼다.
    - L58 `remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST`
    - L92 `manifest_cmd lists every file's sha256 sorted by path`
  - 삭제: L11, L17, L23, L28, L34, L40, L66, L74, L80, L86, L103, L114, L123, L130, L137, L144
  - 정리: 남은 세 테스트가 `docker` 스텁을 쓰지 않으면 `setup`의 `setup_stubs`에서 `docker`를 뺀다. 파일 안의 고아 헬퍼도 지운다.
- [ ] **Step 3: `tests/main_checkout.bats` (11 → 5)**
  - 유지:
    - L37 `make reads the main checkout .env, not the worktree .env, from a linked worktree`. 여기에 L45 `make ignores a worktree .env when the main checkout has none`를 두 번째 단계로 합친다: main 체크아웃의 `.env`를 지운 뒤 worktree의 값이 쓰이지 않음을 확인한다.
    - L71, L92, L101, L122
  - 삭제: L30, L52, L61, L84, L113
  - 정리:
    - L52만 쓰던 `GIT_CEILING_DIRECTORIES` export를 지운다.
    - L30만 쓰던 `cp Makefile "$MAIN_REPO/Makefile"`을 지운다.
    - 둘 다 남은 테스트가 쓰지 않는지 먼저 확인한다.
- [ ] **Step 4: 개수와 전체 검사**

```bash
grep -c '^@test' tests/backup_restore.bats tests/common.bats tests/main_checkout.bats
make check
```

Expected:
- `23`, `3`, `5`
- `make check` 종료 코드 0. 커버리지 보고에서 kcov 측정 줄을 잃는 곳은 `scripts/restore.sh:89` 하나다.

- [ ] **Step 5: 커밋**

```bash
git add tests/backup_restore.bats tests/common.bats tests/main_checkout.bats
git commit -m "test: keep only essential backup, restore, common and main-checkout tests" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: 1"
```

### Task 2: vm_ops, bootstrap

**Files:**
- Modify: `tests/vm_ops.bats`, `tests/bootstrap.bats`, `tests/stubs/id`, `tests/stubs/fallocate`, `tests/stubs/mkswap`, `tests/stubs/free`

**Interfaces:**
- Consumes: Task 1이 `common.bats` L40을 지운다. 그래서 `require_env`의 main 체크아웃 안내 문구는 이 Task가 지킨다.

- [ ] **Step 1: `tests/vm_ops.bats` (32 → 16)**
  - 유지: L15, L31, L45, L54, L63, L92, L112, L119, L126, L142, L158, L172, L192, L207, L225, L257
  - 삭제: L38, L70, L77, L136, L167, L179, L217, L234, L241, L248, L264
  - 병합:
    - L84 `verify confirms the public IP refuses SSH, HTTP, HTTPS and the MCP port` → L54. 공인 IP 포트 거부 assertion과 프로브 4회 개수 assertion을 옮긴다.
    - L102 `verify probes public ports without -G on Linux` → L92. Linux로 한 번 더 실행해 `-G`가 없음을 확인하는 두 번째 실행을 넣는다. 이름은 `verify bounds the public probe's connect time with -G on macOS only`로 바꾼다.
    - L149 `verify rejects a malformed public IP before probing` → L158. `999.1.1.1`을 L158의 반복 입력에 넣고, nc 호출 없음 assertion도 옮긴다.
    - L186 `verify treats a refused connection message as closed`, L198 `verify treats an ICMP reject from the VM firewall as closed` → L192
      - L192를 세 메시지(refused, timed out, ICMP reject)를 도는 반복문으로 바꾼다.
      - 이름은 `verify treats refused, timed out and ICMP-rejected connections as closed`로 바꾼다.
  - L45 `deploy requires the VM settings from .env`에 assertion을 하나 더한다. `require_env`가 출력하는 main 체크아웃 안내 문구(`scripts/lib/common.sh`의 `require_env` 본문에서 실제 문구를 확인)를 assertion으로 옮긴다. 출처는 `common.bats` L40이다.
- [ ] **Step 2: `tests/bootstrap.bats` (25 → 15)**
  - 유지: L19, L68, L83, L93, L111, L123, L133, L142, L162, L185, L195, L207, L234, L257, L287
  - 삭제: L42, L170, L176, L267, L278
  - 병합:
    - L58 `installs tailscale with the official script when missing` → L19
      - L19에서 tailscale 스텁을 빼서 완전히 새 VM으로 만든다. L58의 준비 줄과 "공식 스크립트로 설치" assertion을 옮긴다.
      - 이렇게 해야 `scripts/remote/bootstrap.sh`의 tailscale 설치 줄이 계속 실행된다.
    - L222 `sets up swap before installing docker` → L19. 스왑 설정이 docker 설치보다 먼저라는 순서 assertion을 옮긴다(GCP 스펙 §7.4 1단계).
    - L33 `skips the docker install when docker exists`, L101 `only refreshes hostname and Tailscale SSH when already on the tailnet` → L111. 두 테스트의 refute·assert를 L111에 옮긴다.
    - L247 `keeps a single fstab line when bootstrap runs twice` → L257
      - L257에서 bootstrap을 두 번 실행한다.
      - fstab이 정확히 [기존 줄, 스왑 줄 하나]인지 확인한다.
      - 이름은 `keeps other fstab entries and a single swap line after them, even when run twice`로 바꾼다.
- [ ] **Step 3: 스텁 옵션 정리**
  - 대상: `ID_STUB_GROUPS`(`tests/stubs/id`), `FALLOCATE_STUB_EXIT`(`tests/stubs/fallocate`), `MKSWAP_STUB_EXIT`(`tests/stubs/mkswap`), `FREE_STUB_SWAP_USED_MB`(`tests/stubs/free`)
  - 각 옵션을 `grep -rn '<옵션>' tests/`로 확인하고, 사용처가 스텁 자신뿐이면 그 옵션 코드만 지운다. 스텁 파일 자체는 지우지 않는다.
  - 이미 쓰이지 않던 `FREE_STUB_AVAILABLE_MB`는 범위 밖이므로 두고, 보고에만 적는다.
- [ ] **Step 4: 개수와 전체 검사**

```bash
grep -c '^@test' tests/vm_ops.bats tests/bootstrap.bats
make check
```

Expected:
- `16`, `15`
- `make check` 종료 코드 0. kcov 측정 줄을 잃는 곳은 `scripts/verify-vm.sh`의 usage die, `scripts/bootstrap-vm.sh`의 업로드 실패 정리 두 줄, `scripts/remote/bootstrap.sh`의 "이미 docker 그룹" 분기 두 줄 정도다.

- [ ] **Step 5: 커밋**

```bash
git add tests/vm_ops.bats tests/bootstrap.bats tests/stubs/id tests/stubs/fallocate tests/stubs/mkswap tests/stubs/free
git commit -m "test: keep only essential VM operation and bootstrap tests" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: 2"
```

### Task 3: verify_mcp, repo, cloud_neutral

**Files:**
- Modify: `tests/verify_mcp.bats`, `tests/repo.bats`, `tests/cloud_neutral.bats`

- [ ] **Step 1: `tests/verify_mcp.bats` (23 → 14)**
  - 유지: L14, L20, L33, L39, L47, L54, L61, L71, L80, L87, L101, L113, L123, L144
  - 삭제: L94, L130, L138, L150, L159, L166, L176, L182
  - 병합: L26 `sends the session id from initialize on every later request` → L14. `Mcp-Session-Id` 개수 assertion을 옮긴다.
- [ ] **Step 2: `tests/repo.bats` (31 → 22)**
  - 유지: L14, L38, L49, L58, L74, L79, L88, L95, L108, L117, L126, L131, L153, L158, L167, L174, L182, L201, L206, L233, L251, L288
  - 삭제: L26, L64, L140, L147, L265, L273, L280, L307
  - 병합: L43 `every Make target has a ## description` → L49
    - L49를 Makefile의 **모든** 타깃을 도는 반복문으로 바꾼다. 각 타깃에 `##` 설명이 있고 `.PHONY`에 선언됐는지 확인한다.
    - 이름은 `every Make target has a ## description and is declared .PHONY`로 바꾼다.
  - L233이 쓰는 `markdown_files()`, `markdown_links()`는 남긴다(Q1-B). 삭제한 테스트만 쓰던 헬퍼나 상수가 있으면 지운다.
- [ ] **Step 3: `tests/cloud_neutral.bats` (4 → 3)**
  - 삭제: L27 `the scan passes a clean directory`
  - 유지: L17, L35, L41
- [ ] **Step 4: 개수와 전체 검사**

```bash
grep -c '^@test' tests/verify_mcp.bats tests/repo.bats tests/cloud_neutral.bats
make check
```

Expected:
- `14`, `22`, `3`
- `make check` 종료 코드 0. kcov 측정 줄을 잃는 곳은 `scripts/verify-mcp.sh`의 알 수 없는 옵션 분기 하나다.

- [ ] **Step 5: 커밋**

```bash
git add tests/verify_mcp.bats tests/repo.bats tests/cloud_neutral.bats
git commit -m "test: keep only essential MCP verify, repo and cloud-neutral tests" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: 3"
```

### Task 4: check_git, review, review_bash_guard, skills

**Files:**
- Modify: `tests/check_git.bats`, `tests/review.bats`, `tests/review_bash_guard.bats`, `tests/skills.bats`

- [ ] **Step 1: `tests/check_git.bats` (17 → 14)**
  - 삭제:
    - L88 `flags extensions.worktreeConfig because it breaks Antigravity`. 남는 테스트는 L96.
    - L108 `flags extensions.worktreeConfig set twice and shows every value`
    - L145 `reports the explicit branch's commits, not HEAD's, from a detached HEAD`. 남는 테스트는 L136.
- [ ] **Step 2: `tests/review.bats` (18 → 11)**
  - 유지: L28, L52, L62, L82, L98, L111, L126, L135, L145, L173, L195
  - 삭제: L70, L204, L210
  - 병합:
    - L44 `claude reviews a codex-authored branch with the read-only reviewer agent` → L52. plan 보고서 assertion을 옮긴다.
    - L91 `allows a same-vendor review only when explicitly requested` → L98. 같은 벤더 허용 실행의 성공 assertion과 WARNING 줄 assertion을 옮긴다.
    - L160 `a failed review removes this round's earlier reports` → L126. 이전 보고서를 미리 만들어 두는 준비 줄과 "실패 후 이전 보고서가 지워짐" assertion을 옮긴다.
    - L186 `a successful review leaves only the final pair of reports` → L28. `.partial`이 남지 않고 최종 보고서 두 개만 있다는 assertion을 옮긴다.
- [ ] **Step 3: `tests/review_bash_guard.bats` (10 → 8)**
  - 병합:
    - L78 `blocks quoting and escapes that the shell would strip into --output` → L84. 세 입력 문자열을 L84의 반복문에 넣는다. 실제 우회 사례(b61ddbf)다.
    - L120 `blocks commands other than git` → L101. `rm`, `make`, 빈 문자열을 L101의 반복문에 넣는다.
- [ ] **Step 4: `tests/skills.bats` (18 → 13)**
  - 유지: L30, L44, L72, L88, L97, L105, L119, L125, L136, L142, L161, L173, L179. ADR 0003 결정 7과 `skill-authoring`의 "(tested)" 규칙을 지키므로 남긴다(Q2-A).
  - 삭제: L23 `at least one repository skill exists`, L186 `the skill-authoring template starts with standard frontmatter`
  - 병합:
    - L53 `skill names are lowercase words joined by single hyphens, at most 64 characters` → L44. 이름은 `skill names match their directories, follow the name format and have descriptions`로 바꾼다.
    - L63 `frontmatter values fit on one line; only metadata holds nested keys` → L72. 반복문 안에 assertion을 더한다.
    - L152 `.claude/skills holds only links to existing canonical skills` → L142
      - L142가 양방향을 모두 검사하게 한다.
      - 이름은 `.agents/skills and .claude/skills link every skill both ways`로 바꾼다.
  - 정리: L186만 쓰던 `TEMPLATE` 상수를 지운다. `MAX_COMPATIBILITY_CHARS`와 `MAX_SKILL_LINES`는 L88과 L97이 계속 쓴다.
- [ ] **Step 5: 개수와 전체 검사**

```bash
grep -c '^@test' tests/check_git.bats tests/review.bats tests/review_bash_guard.bats tests/skills.bats
make check
```

Expected:
- `14`, `11`, `8`, `13`
- `make check` 종료 코드 0. kcov 측정 줄을 잃는 곳은 `scripts/review.sh`의 usage 본문과 `reviewer_tool`의 `*) usage` 두 줄이다.

- [ ] **Step 6: 커밋**

```bash
git add tests/check_git.bats tests/review.bats tests/review_bash_guard.bats tests/skills.bats
git commit -m "test: keep only essential git policy, review and skill tests" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: 4"
```

### Task 5: 통합, ADR, 최종 검증 (컨트롤러)

**Files:**
- Create: `docs/decisions/0004-test-scope.md`
- Modify: 이 계획 파일(Progress log)

- [ ] **Step 1: cherry-pick**

```bash
git cherry-pick <T1 SHA> <T2 SHA> <T3 SHA> <T4 SHA>
grep -c '^@test' tests/*.bats | awk -F: '{ s += $2 } END { print s }'
make check
```

Expected: 충돌 없음(파일이 겹치지 않음). 합계 `147`, `make check` 종료 코드 0.

- [ ] **Step 2: ADR 0004 작성 (한국어)**
  - 맥락: 237개 중 상당수가 문구·중복·변형 테스트였다.
  - 결정: "판정 기준"의 K1~K5만 새 테스트로 쓴다. 변형은 대표 테스트의 반복문으로 쓴다.
  - 결과: 147개로 줄었다. 커버리지는 Step 1에서 측정한 실제 값을 적는다. 잃은 kcov 측정 줄을 목록으로 적는다.
  - 대체 범위: 대체된 OCI 스펙(`docs/specs/2026-10-07-basic-memory-oci-tailscale-design.md`) §9의 "스크립트마다 명령·환경 변수 누락과 원격 단계 실패 테스트" 요구를 이 ADR이 대체한다. GCP 스펙 §9의 테스트 요구(스왑, `status`, 클라우드 중립)는 그대로 지켜진다.
- [ ] **Step 3: Progress log에 `Verified`/`Command`로 기록하고 커밋**

```bash
git add docs/decisions/0004-test-scope.md docs/plans/active/2026-10-13-06-test-pruning.md
git commit -m "docs: record the test scope decision and plan 06 evidence" --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 06" --trailer "Task: 5"
make check-git
```

- [ ] **Step 4: 최종 검증 에이전트 (읽기 전용, 브랜치 전체)**
  - "교차 파일 생존 목록"의 남기는 테스트가 모두 있다.
  - K1 테스트가 모두 남았다:
    - `repo.bats` L14, L38, L74, L79, L131, L158, L201, L288
    - `vm_ops.bats` L63, L112, L119, L142, L158
    - `bootstrap.bats` L68, L83, L133, L142, L162
    - `verify_mcp.bats` L33
    - `common.bats` L53
    - `cloud_neutral.bats` L35, L41
  - 문서와 맞는다:
    - `skill-authoring`의 "(tested)" 규칙마다 검사하는 테스트가 남았다.
    - ADR 0003 결정 7의 목록마다 검사하는 테스트가 남았다.
    - `docs/`·README·AGENTS.md·스킬에 지운 테스트 이름이 남아 있지 않다. `docs/reviews/`와 `docs/plans/completed/`는 기록이므로 제외한다.
  - `scripts/`, `Makefile`, `compose.yaml`, 스킬, AGENTS.md가 바뀌지 않았다: `git diff --stat main...HEAD`
  - `make check`와 `scripts/check-git.sh main plan/06-test-pruning`을 직접 실행한다.
- [ ] **Step 5: 교차 벤더 리뷰와 머지 준비**
  - `git-workflow`의 `references/review-and-merge.md`를 따른다. Codex 리뷰는 비용이 들므로 사용자 승인 후 실행한다.
  - 머지는 사람이 `git merge --no-ff`로 한다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-13 | Verified | 서브에이전트 4개가 테스트 237개를 판정 기준으로 분류(읽기 전용). 사용자가 "테스트 조정을 진행하세요"로 진행을 지시. Q1·Q2는 따로 고르지 않아 추천안(Q1-B, Q2-A)을 적용 |
