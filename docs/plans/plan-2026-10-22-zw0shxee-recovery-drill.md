---
status: backlog
id: zw0shxee
spec: docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md
---

# zw0shxee Recovery Drill and Incident Log Implementation Plan

> 2026-10-22 에이전트 개발 시스템 평가(저장소 밖 기록)에서 나온 backlog 초안입니다. 실행하려면 사용자가 이 계획을 승인하고 "배경" 끝의 Open question 1·2를 정해야 합니다. 구성 요소 사이의 인터페이스는 바꾸지 않으므로 새 스펙 없이 GCP 스펙을 근거로 합니다. Task 4는 VM을 바꾸므로 실행할 때 단계마다 다시 OK를 받습니다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 잘못된 배포를 되돌리는 경로(옛 `image:` 줄 + `make restore`)를 실제 VM에서 한 번 실행해 증거를 남기고, VM 장애를 원인·후속 조치와 함께 운영 런북의 Incident log 한곳에 적는다.

**Architecture:**
- 문서 Task 두 개(Incident log, `bm-diagnose` 실패 목록)는 이미 Progress log에 있는 증거를 옮겨 적는다. 기존 행과 증거는 고치지 않고 열과 행만 더한다.
- 코드 Task 하나(E1)는 restore가 VM의 예상 밖 답을 받으면 컨테이너를 멈추기 전에 끝나게 한다. 테스트를 먼저 쓴다.
- VM Task 하나는 `bm-upgrade`의 롤백 절차를 그대로 한 번 실행한다. 같은 실행이 [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) 이후 바뀐 restore의 VM 재시험을 겸한다. 그래서 Task 3 뒤에 한다.

**Spec:** `docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md` (§1 완료 조건 3, §5의 `bm-upgrade` 행, §8의 4번, §10의 "복원·업그레이드 롤백 중 데이터 손상" 행). 접속 방식은 `docs/specs/spec-2026-10-15-jr59pvyf-access-modes.md`.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 사용자가 이 계획을 승인하고 Open question 1·2를 정했다.
- 다른 브랜치의 `bm-upgrade` 리뷰가 진행 중이 아니다. VM이 main이 고정한 이미지로 돈다.
- VM에 배포된 `compose.yaml`이 main과 같다. 그래야 시험이 되돌아갈 "이전 버전"이 main 하나로 정해진다.
  - **Verified (2026-10-22):** PR #10(`7a3748d`, 컨테이너 로그 상한)은 병합됐고, 그 VM 배포 기록은 저장소 문서에 없다.
  - **Assumption:** 아직 배포되지 않았을 수 있다. 배포가 남았다면 Task 4 전에 끝낸다.

## 배경

- **Reported (2026-10-22 평가):** D10(운영 관측·복구)은 3점이고 L4의 두 조건이 모두 미충족이다. (a) 잘못된 배포를 되돌리는 경로는 정의만 있고 실행된 적이 없다. 같은 이미지에서 데이터만 되살린 복원 시험은 L3 근거일 뿐이다. (b) 장애가 원인·후속 조치와 함께 Incident log에 적혀 있지 않다. Progress log에만 있는 행은 인정하지 않는다.
- **Verified (2026-10-22):** 롤백 경로는 `.agents/skills/bm-upgrade/references/rollback.md:5-7`에 있다(옛 `image:` 줄, 사용자의 `make restore`, restore가 `compose.yaml`과 데이터를 함께 되돌림). VM 복원 시험은 [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md)의 한 번뿐이다(`docs/plans/plan-2026-10-07-qtvzskgx-vm-rollout.md:311`, 2026-10-13, 이미지 그대로).
- **Verified (2026-10-22):** 그 뒤 `scripts/restore-notes.sh`는 `3b87fa5`(#5, SilverBullet 공간 파일과 VM `.env`), `87e86d4`(#8, ssh 모드), `47dbbc7`(#15, 이름 변경과 라이브러리 분리)에서 바뀌었다(`git log --follow`). [web-ui-vm-rollout](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)·[access-modes](plan-2026-10-15-ctv444ep-access-modes.md)·[script-cleanup](plan-2026-10-20-c2vxa7kp-script-cleanup.md)·[test-cleanup](plan-2026-10-21-hf9kadp3-test-cleanup.md) 계획의 Progress log에는 VM `make restore` 실행이 없다.
- **Verified (2026-10-22):** Incident log(`docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md:152-156`)의 열은 날짜·원인·사용한 백업·데이터 손실 구간·비고이고, 후속 조치 열이 없다. 행은 2026-10-15 하나이고 "장애 아님"이다.
- **Verified (2026-10-22):** 장애에 해당하는 사건은 Progress log에만 있다.
  - [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:285-287`: 사무실 네트워크가 Tailscale 제어 서버를 막음.
  - [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:289`, `:292`: 콜드 스타트 `unhealthy`와 수정 배포.
  - [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:309`, `:311`: 모델 캐시 심볼릭 링크 때문에 모든 백업이 복원 거부됨. 수정 뒤 재시험은 통과.
  - [script-cleanup 계획](plan-2026-10-20-c2vxa7kp-script-cleanup.md) `docs/plans/plan-2026-10-20-c2vxa7kp-script-cleanup.md:498-500`: 2026-10-21 배포 직후 첫 `make verify`가 `curl: (28)`로 시간 초과됐고, 원인은 `:499`의 Assumption이며, 2분 뒤 통과했다.
  - `.agents/skills/bm-diagnose/SKILL.md:34`는 이런 때 Incident log 행을 제안하라고 하지만 행은 없다.
- **Verified (2026-10-22):** E3. `.agents/skills/bm-diagnose/references/failure-messages.md`에 `curl: (28) Operation timed out` 행이 없다([script-cleanup 계획](plan-2026-10-20-c2vxa7kp-script-cleanup.md) Follow-ups `:472`). 시간 제한은 `scripts/verify-mcp.sh:13`의 `REQUEST_TIMEOUT_SECONDS=30`이다.
- **Verified (2026-10-22):** E1. `scripts/restore-notes.sh:118-122`는 VM의 답이 정확히 `present`일 때만 `HAD_PREVIOUS_DATA`를 켠다. 답이 `present`·`absent`가 아니면(예: 셸 시작 파일이 stdout에 한 줄을 더 찍음) "이전 데이터 없음"으로 읽는다. 그 뒤 단계가 실패하면 롤백(`:61-81`)은 이전 데이터를 제자리로 옮기지만 컨테이너를 다시 띄우지 않고(`:69-72`) "had no data before this restore"라고 보고한다. 데이터는 남지만 서비스가 내려간 채 잘못된 안내가 남는다. 이 분기는 `bb16883`(2026-10-08)부터 있었다. [script-cleanup 계획](plan-2026-10-20-c2vxa7kp-script-cleanup.md) 최종 리뷰가 M4로 찾았고(`:471`) 사용자가 미뤘다(`:496`).
- **Open question 1 (Task 3):** 사용자가 2026-10-21에 미룬 E1을 이 계획에서 고칠까?
  - A(추천): Task 3으로 고친다. 실패하면 서비스가 내려간 채 잘못된 안내가 남는 결함이고, Task 4가 고친 restore를 바로 VM에서 시험한다.
  - B: 계속 미룬다. Task 3을 빼고 Follow-ups에 남긴다.
- **Open question 2 (Task 4):** 시험에 쓸 "잘못된 배포"는 무엇으로 할까?
  - A(추천): 그때의 최신 Basic Memory 릴리스로 `bm-upgrade`를 하고 일부러 되돌린다. `rollback.md`가 다루는 바로 그 경로이고, 새 버전이 데이터를 건드린 뒤의 복원까지 시험한다. 실제 업그레이드는 나중에 `bm-upgrade`로 따로 한다.
  - B: 다음 실제 업그레이드 때까지 Task 4를 미룬다. 계획은 Task 4만 남긴 채 열어 둔다.
  - C: 이미지는 그대로 두고 설정만 바꾼 배포를 되돌린다. `image:` 롤백은 시험하지 못한다.
  - **Assumption:** 2026-10-22 기준 `compose.yaml:14`의 0.23.2보다 새 릴리스가 있는지는 확인하지 않았다. 새 릴리스가 없으면 A는 쓸 수 없고 B가 된다.

## Global Constraints

- VM을 바꾸는 `make deploy`·`make restore`는 메인 세션에서 단계마다 사용자 OK를 받은 뒤 한다. restore의 `yes`는 사용자가 자기 터미널에서 입력한다. `make backup`·`probe`·`status`·`logs`·`verify`·`tunnel`은 OK가 필요 없다(AGENTS.md).
  - **Reported (2026-10-13, [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:311`):** Claude Code의 `!`로 실행하면 `read`가 입력을 받지 못한다.
- 배포 전에 `make backup`을 하고, 출력된 절대 경로를 롤백 지점으로 적는다(`bm-upgrade` 7단계).
- 시험용 `image:` 줄은 커밋하지 않는다(`rollback.md` 5단계). 브랜치의 모든 커밋에서 `git diff origin/main -- compose.yaml`이 비어 있다.
- `backups/`와 `/srv/basic-memory.prev-*`는 지우지 않는다. 지우는 일은 사람만 한다.
- 기록에는 IP 주소, tailnet 호스트 이름, 세션 id를 쓰지 않는다. 호스트는 `agent-hub`, `agent-hub-iap`나 자리표시자로 쓴다.
- Incident log와 Progress log의 기존 행은 고치지 않는다. 열을 더할 때는 기존 행 끝에 새 칸만 붙인다(`doc-authoring`).
- 문서만 바꾸는 Task에는 bats 테스트를 쓰지 않는다. [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 결정 2가 문구·형식만 확인하는 테스트를 금지한다(`docs/decisions/adr-2026-10-13-a878ypj5-test-scope.md`). 대신 Step의 명령으로 확인한다.
- 스크립트 변경은 macOS bash 3.2 규칙과 `die` 규칙을 지킨다(AGENTS.md Invariants).
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: zw0shxee`, `Task: <N|review|none>`.

## Review Focus

1. Task 1의 새 행에는 IPv4 주소가 없다. 근거로 쓰는 [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:285`에 Tailscale 제어 서버 주소가 있으므로 옮겨 적을 때 빠뜨린다. Task 1 Step 4의 두 번째 명령으로 확인한다.
2. Task 2의 새 행은 읽기 전용 확인만 시킨다(`bm-diagnose` 규칙 `SKILL.md:12-14`). `make verify`는 사용자에게 제안만 한다.
3. Task 4의 시험 pin은 브랜치 이력에 없다. Finish 전에 `git log -p origin/main..HEAD -- compose.yaml`이 비어 있는지 본다.
4. Task 4: 백업과 복원 사이에 다른 에이전트가 쓴 노트는 복원으로 바뀌고 `.prev-*`에만 남는다. Progress log에 시험 창(백업 시각 → 복원 시각)과, 사용자가 노트 쓰기를 멈췄는지를 적는다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md` | Incident log 후속 조치 열, 장애 정의 한 줄, 과거 장애 행, 롤백 시험 행, `reviewed` | 1, 4 |
| `.agents/skills/bm-diagnose/references/failure-messages.md` | `curl: (28)` 시간 초과 행 | 2 |
| `.agents/skills/bm-diagnose/SKILL.md` | 7단계: 원인과 후속 조치를 담은 행을 제안 | 2 |
| `scripts/restore-notes.sh` | `present`·`absent`가 아닌 답에서 멈춤 | 3 |
| `tests/restore-notes.bats` | 그 실패 경로 테스트 | 3 |
| `compose.yaml` | 시험 중에만 바뀌고 커밋하지 않음 | 4 |
| `docs/plans/plan-2026-10-22-zw0shxee-recovery-drill.md` | Progress log의 시험 증거 | 4 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/zw0shxee-recovery-drill` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Incident log follow-up column and past incidents

**Files:**
- Modify: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md:152-156`

- [ ] **Step 1: 테스트 없음.** [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 결정 2. Step 4의 명령으로 확인한다.
- [ ] **Step 2: 열과 정의**
  - 머리 행 끝에 `후속 조치` 열을 더한다. 2026-10-15 행에는 끝에 `해당 없음(장애 아님)` 칸만 붙인다.
  - `## Incident log` 바로 아래에 정의 한 줄을 둔다. 장애는 실제 VM에서 서비스, 접속 경로, 복구 경로를 해친 계획에 없던 사건이고, 실패한 검증·시험도 포함한다. 원인을 확인하지 못했으면 원인 칸을 `Assumption:`으로 시작한다. 후속 조치 칸에는 커밋·PR·계획을 적고, 없으면 `없음`과 이유를 적는다.
  - **Assumption:** 이 정의는 평가의 D10 판정 기준을 옮긴 것이다. 사용자가 다르게 정하면 그에 따른다.
- [ ] **Step 3: 행 추가.** 날짜순으로 넣고, 출처 줄은 비고 칸에 적는다.
  - 2026-10-13, 콜드 스타트 `unhealthy`([vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:289`, `:292`). 백업: 사용 안 함. 손실: 없음. 후속: `71ad51b`(`start_period: 300s`, `HEALTH_TIMEOUT_SECONDS` 360초), `tests/repo-config.bats:63`. 늘어나는 콜드 스타트는 vm-rollout 계획 Follow-ups에 남아 있다.
  - 2026-10-13, 모든 백업이 복원 거부됨(`:308`, `:310`). 백업: `bm-20261013T050026Z.tgz`(거부됨). 손실: 없음(VM에 손대기 전에 거부). 후속: `5561329`(모델 캐시 제외), `tests/restore-notes.bats:48`. 같은 날 2회차 복원이 통과했다.
  - 2026-10-13, 접속 경로: 사무실 네트워크가 HTTPS `controlplane.tailscale.com`만 막음(`:285-287`). 백업: 사용 안 함. 손실: 없음. 후속: 사용자가 IT에 허용을 요청했고, [access-modes 계획](plan-2026-10-15-ctv444ep-access-modes.md)에서 VM을 `ssh` 모드로 옮겼다(`4cedf49`, PR #12).
  - 2026-10-21, 배포 직후 첫 `make verify`가 `tools/list`에서 `curl: (28)`로 끝남([script-cleanup 계획](plan-2026-10-20-c2vxa7kp-script-cleanup.md) `:498-500`). 원인 칸은 `Assumption:`(재색인)으로 시작한다. 백업: 사용 안 함. 손실: 없음. 비고: 2분 뒤 `make probe`·`make verify` 통과. 후속: Task 2의 실패 목록 행. 원인 확인은 Follow-ups로 남긴다.
- [ ] **Step 4: 확인**

Run: `make check`; `awk '/^## Incident log/,/^### 점검 기록/' docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md | grep '^|' | awk -F'|' '{ print NF - 2 }' | sort -u`; `awk '/^## Incident log/,/^### 점검 기록/' docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md | grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}'`
Expected: `make check`는 exit 0이다. 두 번째 명령은 `6` 한 줄만 출력한다(모든 행이 여섯 칸). 세 번째 명령은 아무것도 출력하지 않는다(grep exit 1).

- [ ] **Step 5: 커밋.** `docs: give the Incident log a follow-up column and the past incidents`, 트레일러 `Plan: zw0shxee`, `Task: 1`.

### Task 2: bm-diagnose curl timeout entry

**Files:**
- Modify: `.agents/skills/bm-diagnose/references/failure-messages.md:20-30` (MCP 표, `:24` 행 다음)
- Modify: `.agents/skills/bm-diagnose/SKILL.md:34`

- [ ] **Step 1: 테스트 없음.** [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 결정 2. 새 행에도 `tests/repo-skills.bats`의 번들 파일 검사와 `tests/repo-docs.bats`의 경로 검사가 그대로 적용된다.
- [ ] **Step 2: 행 추가(영어).**
  - 메시지: `curl: (28) Operation timed out after N milliseconds`가 `<step>: request to <url> failed` 앞에 찍힌다.
  - 뜻: 서버까지의 경로(터널이나 tailnet)는 열렸지만, Basic Memory가 `REQUEST_TIMEOUT_SECONDS`(30초, `scripts/verify-mcp.sh`) 안에 답하지 않았다. 2026-10-21 배포 직후에 나왔다.
  - 다음 단계(읽기 전용): 1~2분 기다린 뒤 `make status`로 두 컨테이너가 healthy인지와 메모리·스왑을 보고, `make probe`를 돌린다. probe가 통과하면 `make verify`를 사용자에게 제안한다. 다시 나면 `make logs`의 첫 오류와 메모리 수치를 보고하고("Sustained swap use" 행), Incident log 행을 제안한다.
- [ ] **Step 3: `SKILL.md:34`.** Incident log 행을 제안할 때 원인(확인하지 못했으면 Assumption)과 후속 조치를 함께 적으라고 한 구절을 더한다.
- [ ] **Step 4: 확인**

Run: `make check`; `grep -n 'curl: (28)' .agents/skills/bm-diagnose/references/failure-messages.md`
Expected: `make check`는 exit 0이다. grep은 MCP 표 안의 한 줄을 찾는다.

- [ ] **Step 5: 커밋.** `docs: add the curl timeout to the bm-diagnose failure catalog`, 트레일러 `Plan: zw0shxee`, `Task: 2`.

### Task 3: restore stops on an unexpected VM answer (E1)

Open question 1이 B이면 이 Task를 빼고 Follow-ups에 남긴다. 시작 전에 `script-authoring` 스킬을 읽는다.

**Files:**
- Modify: `scripts/restore-notes.sh:118-122`
- Test: `tests/restore-notes.bats` (`:257` 테스트 다음에 새 테스트)

**Interfaces:**
- Consumes: `remote_exists PATH`(`scripts/lib/vm.sh:133`, `present`나 `absent`를 출력하고 VM이 답하지 않으면 실패), `fake_cmd NAME BODY`(`tests/helpers.bash:112`), `make_archive`·`restore_with_answer`(`tests/restore-notes.bats:15`, `:36`)
- Produces: 없음

- [ ] **Step 1: 실패하는 테스트 작성.** `@test "restore stops before it stops the container when the VM answers neither present nor absent"`.
  - `make_archive "restored"`를 만든다.
  - 두 답을 반복문으로 시험한다([test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 결정 3). 하나는 배너 한 줄 뒤의 `present`, 하나는 빈 답이다. 각 경우는 `$STUB_LOG`를 비운 서브셸 `( ... ) || fail "<답>"`에서 돌린다(`script-authoring` 규칙).
  - 답마다 `fake_cmd ssh`로 가짜 ssh를 만든다. 원격 명령(마지막 인자)에 `then echo present; else echo absent`가 들어 있으면 그 답을 출력하고 0으로 끝나고, 아니면 `exec "$REPO_DIR/tests/stubs/ssh" "$@"`로 넘긴다.
  - `restore_with_answer yes`를 실행하고 확인한다: `assert_failure`, `refute_stub_called -F 'docker compose stop'`, `$BM_REMOTE_DATA_ROOT/knowledge/a.md`가 그대로 `original`, 데이터 루트의 부모 폴더에 `basic-memory.prev-*`·`basic-memory.restore-*`가 없음.
- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 새 테스트만 실패한다. restore가 답을 "이전 데이터 없음"으로 읽고 데이터를 바꾼 뒤 exit 0으로 끝나므로 `assert_failure`가 실패한다.

- [ ] **Step 3: 최소 구현.** `:120-122`의 `if`를 `case "$present" in`으로 바꾼다. `present`는 `HAD_PREVIOUS_DATA=1`, `absent`는 아무것도 하지 않는다. 그 밖의 답이면 `die`로 멈춘다. 메시지에는 기대한 답(`present` 또는 `absent`), 아무것도 바꾸지 않았다는 사실, 다음 할 일(비대화형 `ssh`가 다른 출력을 내지 않는지 확인한 뒤 다시 실행)을 담는다. 이 분기는 `trap rollback EXIT`(`:124`)보다 앞에 있으므로 롤백도 실행되지 않는다.
- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0, 커버리지 80% 이상

- [ ] **Step 5: 커밋.** `fix: stop a restore when the VM gives an unexpected answer`, 트레일러 `Plan: zw0shxee`, `Task: 3`.

### Task 4: Rollback drill on the VM

메인 세션에서 사용자와 함께 한다. Open question 2가 시험 이미지를 정한다. 이 실행이 [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) 이후 처음 하는 VM 복원 재시험이다.

**Files:**
- Modify (시험 중에만, 커밋하지 않음): `compose.yaml:14`
- Modify: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md:4` (`reviewed`), `:152-156` (Incident log 행)
- Modify: `docs/plans/plan-2026-10-22-zw0shxee-recovery-drill.md` (Progress log)

- [ ] **Step 1: 준비(OK 불필요).**
  - `git diff origin/main -- compose.yaml`이 비어 있는지 본다.
  - `make access-check probe status`를 돌리고, `make status`의 IMAGE가 `grep 'image:' compose.yaml`과 같은지 본다(런북 "배포·복원 전 이미지 점검").
  - 옛 `image:` 줄을 기록한다.
  - 사용자에게 시험 창 동안 노트 쓰기를 멈춰 달라고 한다.
- [ ] **Step 2: 시험 이미지.** `bm-upgrade` 2~6단계를 따른다: 릴리스 노트 요약, digest와 두 아키텍처 확인, `image:` 줄만 변경, `make check local-up local-verify`, `make local-down`. 하나라도 실패하면 멈춘다.
- [ ] **Step 3: 롤백 지점.** `make backup`을 한다(컨테이너가 잠깐 멈춘다고 알린다). 출력의 `backup saved: <main>/backups/bm-<stamp>.tgz` 절대 경로를 기록한다.
- [ ] **Step 4: 잘못된 배포(사용자 OK).** `make deploy verify status`를 한다. Expected: IMAGE가 시험 이미지이고 두 컨테이너가 healthy이다. 첫 verify가 `curl: (28)`로 끝나면 Task 2의 행대로 기다렸다가 `make probe`, 그다음 `make verify`를 다시 한다.
- [ ] **Step 5: 표시 노트.** `make tunnel`을 띄우고 MCP `write_note`로 `rollback-drill` 노트를 쓴 뒤 `read_note`로 확인한다. 백업 뒤에 생긴 변경이다.
- [ ] **Step 6: 롤백(`rollback.md`, 사용자 OK).** 옛 `image:` 줄을 되돌린다. 그 뒤 `git diff origin/main -- compose.yaml`은 비어 있다. 사용자가 자기 터미널에서 이 worktree로 가서 `make restore BACKUP=<Step 3의 절대 경로>`를 실행하고 `yes`를 입력한다. 이것은 런북 첫 단락이 말하는 `bm-upgrade` 사용자 승인 배포의 예외에 해당한다. `make restore`는 끝나면 `scripts/verify-vm.sh`를 실행한다(`Makefile:123-125`).
  Expected: restore 출력이 manifest 대조, `compose.yaml`·`.env` 업로드, 교체, 시작을 거쳐 `restored bm-<stamp>.tgz; previous data kept at /srv/basic-memory.prev-<stamp>`로 끝나고, 이어진 verify가 통과한다.
- [ ] **Step 7: 확인.**
  - `make status`의 IMAGE가 main의 `image:`와 같고 두 컨테이너가 healthy이다.
  - `read_note`로 찾으면 `rollback-drill`이 없다. 백업 이후의 변경이 사라진 것이다(스펙 §1 완료 조건 3).
  - `make probe`가 통과한다.
- [ ] **Step 8: 기록.**
  - Progress log에 단계마다 명령과 결과(시각, exit, 걸린 시간)를 `Verified`로 적는다. IP와 세션 id는 빼고, restore를 어느 체크아웃에서 실행했는지 적는다.
  - Incident log에 "장애 아님: 롤백 시험(recovery-drill 계획 Task 4)" 행을 더한다(2026-10-15 행이 선례). 사용한 백업은 Step 3의 파일, 데이터 손실 구간은 백업 시각부터 복원 시각까지(`.prev-*`에 남음)다. 후속 조치에는 `.prev-*` 삭제를 사람이 정한다고 적는다.
  - 런북 `reviewed`를 그날로 바꾼다.
  - `.prev-*`를 지울지 사용자에게 묻는다. 에이전트는 지우지 않는다.

Run: `make check`; `git diff origin/main -- compose.yaml`
Expected: `make check`는 exit 0이고, 두 번째 명령은 아무것도 출력하지 않는다.

- [ ] **Step 9: 커밋.** `docs: record the rollback drill on the VM`, 트레일러 `Plan: zw0shxee`, `Task: 4`.

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과, Task 4의 시험 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- E2: 컨테이너 정지가 SIGTERM 뒤 10초 만에 SIGKILL로 끝난다([vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) `:329-330`, Follow-ups `:258`). 장애는 아니고, 멈출 때마다 중단 시간이 늘어난다.
  - **Verified (2026-10-22):** `compose.yaml`에 `init`, `stop_signal`, `stop_grace_period`가 없다.
- 콜드 스타트가 161 → 192 → 248초로 늘었다([vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) Follow-ups `:259`).
- 2026-10-21 시간 초과의 원인은 Assumption으로 남는다. 다음 배포 때 `make logs`의 요청 시각과 색인 로그로 확인한다.
- **Verified (2026-10-22):** E1과 같은 꼴이 `scripts/sync-sb-space.sh:38`에도 있다. 표시 파일에 대한 답이 `present`가 아니면 모두 "변경 없음"으로 읽어, `.gitignore`가 바뀌었는데도 Basic Memory를 다시 만들지 않을 수 있다. 공용 도우미(`remote_exists`, `notes_file_state`)에서 답을 검사할지는 따로 정한다.
- 반복 시험(`bm-upgrade` 때마다 롤백 경로를 시험할지, 정기 시험을 둘지)은 이 계획 밖이다.
- 실제 VM에서 restore의 자동 롤백 분기를 일부러 실패시켜 보는 시험은 하지 않는다. 그 분기는 bats 테스트 `tests/restore-notes.bats:191`이 다룬다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
