---
status: active
spec: docs/specs/spec-2026-10-15-script-test-layout.md
---

# 17 Test Cleanup and Script Authoring Rules Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 없다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 실행 스크립트와 라이브러리마다 이름이 짝인 bats 파일이 하나씩 있고, 같은 동작은 한 테스트만 보고, 필요 없는 테스트는 없다. 저장소 전체 규칙은 `repo-*.bats`에 있으며, 새 스크립트는 `make new-script`와 `script-authoring` 스킬로 같은 모양으로 만들어진다.

**Architecture:**
- 순서는 셋으로 나뉜다. 내용을 바꾸는 단계를 옮기는 단계와 나눠서, 옮기다 빠진 단언을 목록 비교로 잡는다.
  - 테스트 파일을 스크립트 이름의 짝으로 옮기고 나눈다(Task 2~4). 이때 테스트 이름과 테스트마다의 단언 수는 바뀌지 않는다.
  - 공용 도우미로 반복 코드를 줄인다(Task 5).
  - 비슷한 테스트를 합치고 필요 없는 테스트를 지운다(Task 6~9). 테스트 220개를 하나씩 분류한 결과(Progress log 2026-10-21)의 묶음 표를 따른다.
- 짝 경로와 동사 표 읽기는 `scripts/lib/layout.sh` 한 곳에 두고, `scripts/create-script.sh`와 `tests/repo-scripts.bats`의 검사가 함께 쓴다(Task 10, 11).
- 동작은 바꾸지 않는다. 새 동작은 `make new-script` 하나다.

**Spec:** `docs/specs/spec-2026-10-15-script-test-layout.md` (6~9절, 10절의 계획 17 행, 11절)

**Sequence:** 계획 17. 다음을 모두 만족한 뒤 시작한다.
- 계획 16(PR #15)이 병합됐다(`47dbbc7`, 2026-10-21).
- 이 계획과 아래 Decisions, `AGENTS.md` 문구를 사용자가 승인했다.

## Global Constraints

- 스펙 1절의 완료 조건 1~7. 특히 짝이 없는 bats 파일은 `repo-*.bats`뿐이고, `make check`가 통과하며 커버리지는 80% 이상이다.
- 정리는 동작을 바꾸지 않는다(스펙 1절 범위 밖). 스크립트 파일은 Task 10의 새 파일과 `scripts/lib/layout.sh`만 바뀐다.
- 테스트는 ADR 0004(결정 1~3)와 ADR 0007을 따른다. 스텁이나 도우미 자체를 검사하는 테스트, 문구만 확인하는 테스트는 새로 쓰지 않는다. 도우미와 검사의 실패 경로는 커밋하지 않는 임시 파일로 한 번 확인한다(Task 5, 11).
- 합치기 규칙(Task 6~9):
  - 묶음의 서로 다른 입력과 단언을 모두 결과 테스트로 옮기고, 고아가 된 도우미는 지운다(계획 06, 41-42행).
  - 결과 테스트의 이름은 반복문이 무엇을 모두 검사하는지 드러낸다(ADR 0004 결정 3).
  - 메시지 단언은 어느 검사가 멈췄는지 가릴 때만 둔다(예: `"BM_ACCESS must be tailscale or ssh"`). 고칠 방법을 안내하는 문구는 단언하지 않는다.
  - 반복문의 각 경우는 하위 셸에서 돌리거나 경우마다 상태를 되돌린다. 환경 변수, PATH, 파일이 다음 경우로 새지 않게 한다.
  - 같은 함수의 동작은 그 함수가 사는 라이브러리의 짝 테스트(`lib-*.bats`)에 두고, 스크립트 테스트에서는 그 함수를 부른다는 사실만 본다(스펙 7.2절). 여러 스크립트가 같은 사전 검사를 부르는지는 lib 테스트의 반복문 하나가 스크립트를 돌며 본다.
- 약한 묶음은 합치지 않는다. 같은 생각이지만 다른 코드나 다른 규칙을 검사하는 묶음이다. 목록과 이유는 Task 6~9 끝에 있다.
- 테스트 실행은 `make test`, `make check`만 쓴다. 기록 문서(완료 계획, 스펙, ADR, 리뷰 기록)의 옛 테스트 이름은 고치지 않는다(스펙 4절).
- 이름 목록 명령(Task 2~9의 비교에 쓴다). `$WS`는 git이 무시하는 작업 폴더(예: SDD workspace)다. 테스트 이름과 그 테스트 안의 `assert_*`, `refute_*`, `fail` 줄 수를 낸다:
  ```bash
  awk '/^@test "/ { name = $0; sub(/^@test "/, "", name); sub(/" \{$/, "", name); n = 0; next }
    name != "" && /^}/ { print name "\t" n; name = ""; next }
    name != "" && /(assert|refute)_[a-z_]+|(^|[^a-z_])fail( |$)/ { n++ }' tests/*.bats | LC_ALL=C sort >"$WS/tests-<label>.tsv"
  ```
- 아래 표의 위치(`vm_ops:32` 같은 표기)는 `47dbbc7`의 옛 파일과 줄이다. Task 2~5는 테스트 이름을 바꾸지 않으므로, 이름으로 찾는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 17`, `Task: <N|review|none>`.

## Decisions (사용자 승인 필요)

- **P1. 템플릿은 종류마다 한 쌍이다.** `assets/script.sh`·`script.bats`, `remote.sh`·`remote.bats`, `lib.sh`·`lib.bats`의 여섯 개와, 템플릿 폴더에만 적용되는 `assets/.shellcheckrc`를 둔다. 스펙 8.2절은 템플릿을 두 개(`script.sh`, `test.bats`)로 정했지만, 8.3절의 `KIND=script|remote|lib`는 머리가 서로 다르다. remote는 아무것도 source하지 않고(검사 2), lib는 source 방지 줄과 `common.sh` source가 있고 `main`이 없다(검사 3). 템플릿 하나를 sed로 고치면 그 규칙이 `create-script.sh` 코드 속에 숨는다. `.shellcheckrc`는 SC1091만 끈다. 템플릿이 source하는 파일이 템플릿 폴더에는 없어서 `make lint`가 실패하기 때문이다(Progress log 2026-10-21). 비용: 템플릿 파일이 넷 늘어난다.
- **P2. 템플릿 테스트는 기존 26개 파일처럼 파일 맨 위에 `load helpers`를 둔다.** 스펙 8.2절은 `setup() { load helpers; … }`라고 썼지만, 기존 파일을 모두 바꾸지 않으면 템플릿과 이웃 파일이 달라지고, 에이전트는 이웃 파일을 따라 한다. 함수 밖에는 `load helpers`와 상수 대입 말고 아무것도 두지 않는다.
- **P3. `scripts/lib/layout.sh`를 새로 둔다.** `script_verbs`와 `pair_test`를 `create-script.sh`와 `repo-scripts.bats`가 함께 쓴다. 스펙 8.3절은 공용 함수를 `common.sh`에 두라고 했지만 그것은 템플릿 채우기 함수에 대한 말이다. 짝 규칙은 모든 스크립트가 source하는 `common.sh`에 둘 이유가 없다.
- **P4. 계획 16에서 M2를 고치며 더한 테스트 "status points to free -m on the VM when it cannot read the memory use"를 지운다.** 실패 문구만 확인하는 테스트여서 ADR 0004 결정 2에 어긋난다. 계획 16의 작성자가 더한 것이다.
- **P5. 비슷한 테스트와 필요 없는 테스트를 모두 정리한다(사용자 결정, 2026-10-21).**
  - 스펙 7.2절은 2.2절이 고른 다섯 가지만 정리 대상으로 정했지만, 사용자가 범위를 넓혔다.
  - 테스트 220개를 하나씩 분류해 묶음 97개를 찾았다.
  - 같은 동작을 보거나 입력만 다르거나 한 테스트의 단언이 다른 테스트에 모두 들어 있는 묶음은 모두 합친다. 다른 코드를 검사하는 약한 묶음은 그대로 둔다(Task 6~9의 표).
  - ADR 0004 결정 1의 보호 대상은 합친 뒤에도 대표 테스트가 반드시 남는다. 127.0.0.1 바인딩, Funnel 금지, 공개 인그레스 0, digest 고정, 비밀값 비출력, 백업·복원 데이터 안전, git 정책이 여기에 해당한다.
- **P6. `AGENTS.md`는 다음 문구로 바꾼다.**
  - 12행 → `## Invariants (enforced by the tests/repo-*.bats files; never weaken a test to make it pass)` (Task 4)
  - 15행 → ``- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh` or a `scripts/lib/` library that sources it (scripts in `scripts/remote/` run alone on the VM and source none); fail with an actionable message via `die`.`` (Task 11)
  - 18행 → ``- Write the bats test first: `tests/<name>.bats` for `scripts/<name>.sh`, `tests/remote-<name>.bats` and `tests/lib-<name>.bats` for `scripts/remote/` and `scripts/lib/` (`make new-script` creates both); fake commands live in tests/stubs/, recorded responses in tests/fixtures/<test name>/.`` (Task 11)
  - 45행 → ``- `scripts/` lifecycle scripts named `<verb>-<object>.sh`; `scripts/lib/` shared helpers by topic, each with a function index at the top; `scripts/remote/` runs on the VM.`` (Task 11)
  - 46행 → ``- `tests/` one bats file per script plus `repo-*.bats` for repo-wide rules; `tools/` test image and coverage gate.`` (Task 11)
  - 50행의 `tests/skills.bats` → `tests/repo-skills.bats` (Task 2)
  - `## Skills`의 `skill-authoring` 줄 다음 → ``- Adding or changing a script, a library, a Make target, a bats test, a stub or a fixture: `script-authoring`.`` (Task 10)
- **P7. VM 단계가 없다.** 스크립트 동작이 바뀌지 않으므로 배포와 VM 확인을 하지 않고, `make check`(lint, 테스트, 커버리지)로 검증한다.

## Review Focus

1. 새 assertion 도우미가 실패해야 할 때 통과한다. 예를 들어 `refute_stub_called`가 grep 옵션이나 따옴표를 잘못 넘기면 무엇이든 "불리지 않음"이 된다. 기대 동작은 각 도우미가 실패 입력에서 실패하는 것이다. Task 5 Step 5가 임시 파일로 확인한다.
2. `fake_cmd`가 이미 있는 스텁 링크(`$STUB_BIN/<name>` → `tests/stubs/<name>`)를 따라 써서 저장소의 스텁을 덮어쓴다. 기대 동작은 먼저 지우고 새 파일을 쓰는 것이다. Task 5 Step 5가 임시 파일과 `git status`로 확인한다.
3. 옮긴 테스트가 setup을 잃고도 다른 이유로 통과한다. 예를 들어 스텁이 PATH에 없어 "불리지 않음"이 참이 된다. 기대 동작은 테스트 이름과 단언 수가 옮기기 전과 같고, 새 파일의 setup이 옮긴 테스트가 쓰는 스텁과 환경을 모두 만드는 것이다. Task 3, 4의 목록 비교와 Step의 setup 점검이 확인한다.
4. 합친 반복문에서 앞 경우의 상태(export한 변수, PATH, 남은 파일)가 다음 경우로 새어, 뒤 경우가 다른 이유로 통과한다. 기대 동작은 경우마다 따로 실패할 수 있는 것이다. Task 6~9 Step 3이 합친 반복문마다 경우 하나씩의 입력을 정상값으로 바꿔 그 경우만 실패하는지 확인한다(커밋하지 않음).
5. 검사 1~5가 위반을 놓친다. 예를 들어 짝의 역방향(스크립트가 없어진 테스트), 코드 블록 안의 낡은 `scripts/…sh` 경로, `common.sh`를 source하지 않는 새 라이브러리가 그렇다. 기대 동작은 위반 파일과 고칠 방법을 출력하며 실패하는 것이다. Task 11 Step 2가 일부러 심은 위반으로 확인한다.
6. `make new-script`가 스크립트나 테스트 가운데 하나가 이미 있을 때 다른 하나만 만들거나 덮어쓴다. 기대 동작은 아무것도 쓰지 않고 실패하는 것이다. Task 10의 `create-script.bats` 세 번째 테스트가 고정한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `Makefile`, `.editorconfig` | `.bats`도 lint와 fmt 대상. `new-script` 타깃 | 1, 10 |
| `tests/*.bats` 14개 이름 변경 | 짝 이름(`check-git.bats` 등), `repo-skills/github/cloud-neutral`, `lib-common.bats` | 2 |
| `tests/{deploy-stack,verify-vm,show-status,show-logs,backup-notes,restore-notes,bootstrap-vm,remote-provision-vm,check-access,open-tunnel}.bats` | 여러 스크립트를 묶었던 파일에서 나눈 짝 테스트 | 3 |
| `tests/{repo-scripts,repo-make,repo-config}.bats`, `tests/repo-docs.bats` | `repo.bats`, `main_checkout.bats`를 주제별로 나눔 | 4 |
| `tests/helpers.bash` | 공용 도우미(Task 3·5·9) | 3, 5, 9 |
| `tests/fixtures/verify-mcp/{json,sse}/`, `tests/fixtures/remote-provision-vm/os-release` | 짝 이름 폴더로 옮긴 픽스처 | 5 |
| VM·웹·접속 테스트, `tests/lib-vm.bats`, `tests/lib-sb.bats`, `tests/stubs/free` | 비슷한 테스트 합치기, 필요 없는 테스트 지우기 | 6 |
| `tests/backup-notes.bats`, `tests/restore-notes.bats` | 같은 일 | 7 |
| git·리뷰·문서 도구 테스트, `tests/stubs/{claude,gh}` | 같은 일 | 8 |
| `tests/repo-*.bats` | 같은 일, 공용 문서·스킬 도우미 | 9 |
| `scripts/lib/layout.sh`, `tests/lib-layout.bats`, `scripts/create-script.sh`, `tests/create-script.bats` | `script_verbs`, `pair_test`, `make new-script` | 10 |
| `.agents/skills/script-authoring/` (SKILL.md, assets 7개), `.claude/skills/script-authoring` | 작성 스킬, 동사 표의 정본, 템플릿 | 10 |
| `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `.agents/skills/{doc,skill}-authoring/SKILL.md` | 테스트 이름과 새 스킬의 참조 | 2, 4, 10, 11 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/17-test-cleanup` 브랜치를 만든다(`git-workflow` 스킬의 Start). worktree `repo-structure`에 이미 만들었다(`47dbbc7`).
- [x] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다. 이 커밋 전에 이름 목록 명령으로 `$WS/tests-base.tsv`를 만든다(220줄).

### Task 1: Lint the bats files

**Files:**
- Modify: `Makefile:30` (`SH_FILES`에 `'*.bats'`), `.editorconfig:9` (`[*.{sh,bash}]` → `[*.{sh,bash,bats}]`)
- Modify: `tests/*.bats` (shfmt 서식, shellcheck 지적)

- [x] **Step 1: lint 대상에 `.bats`를 더한다.** `.editorconfig`에는 dialect 키를 두지 않는다. shfmt v3.12.0이 확장자로 bats를 알아본다(Progress log 2026-10-21). 스펙 7.4절의 `language_dialect`는 필요 없다.
- [x] **Step 2: 실패 확인.** Run: `make lint`. Expected: exit 2. 지적은 SC2031 102, SC2030 30, SC2016 16, SC2164 6, SC1007 4, SC2034 2, SC2086 1, SC2001 1이고, 파싱 오류는 없다.
- [x] **Step 3: `make fmt`.** Expected: `tests/repo-docs.bats`(2줄)와 `tests/repo.bats`(1줄)만 바뀐다.
- [x] **Step 4: shellcheck 지적 고치기.**
  - SC2030·SC2031은 bats가 `@test`마다 하위 셸을 쓰기 때문에 생기는 오탐이다. 이 둘이 나오는 파일(`access`, `backup_restore`, `bootstrap`, `vm_ops`)에만, shebang 바로 다음 줄에 파일 전체에 적용되는 지시문을 둔다: `# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test`. 저장소 전체 `.shellcheckrc`에는 넣지 않는다. 스크립트에서는 이 둘이 진짜 경고이기 때문이다.
  - 나머지는 코드로 고친다.
    - SC2164: `cd … || return`
    - SC1007: `VAR='' run …`
    - SC2034: `read`의 쓰지 않는 칸은 `_`로
    - SC2086: 따옴표
    - SC2001: 같은 결과의 `${var//…/…}`
  - SC2016은 줄마다 본다. 의도한 작은따옴표면 그 줄에 `# shellcheck disable=SC2016 # <왜 리터럴인지>`를 단다.
- [x] **Step 5: 통과 확인.** Run: `make check`. Expected: exit 0, 220개, not ok 0. 이름 목록이 `tests-base.tsv`와 같다.
- [x] **Step 6: 커밋** `test: lint the bats files with shellcheck and shfmt` (`Task: 1`).

### Task 2: Rename the single-subject test files

**Files:**
- Rename(`git mv`):
  - 짝 이름: `check_git` → `check-git`, `check_pr` → `check-pr`, `verify_mcp` → `verify-mcp`, `verify_sb` → `verify-sb`, `post_review` → `post-review`, `sb_space` → `sync-sb-space`, `sb_fonts` → `upload-sb-fonts`, `review` → `review-branch`, `review_record` → `post-review-record`, `review_bash_guard` → `guard-reviewer-bash`, `common` → `lib-common`
  - 저장소 전체: `skills` → `repo-skills`, `github` → `repo-github`, `cloud_neutral` → `repo-cloud-neutral`
  - 모두 `tests/<이름>.bats`다.
- Modify: `AGENTS.md:50`, `README.md:57`, `docs/ARCHITECTURE.md:53`, `.agents/skills/skill-authoring/SKILL.md:8` (`tests/skills.bats` → `tests/repo-skills.bats`)

이름만 바꾸므로 실패 단계가 없다. 안전망은 이름 목록이다.

- [x] **Step 1: `git mv` 14개와 참조 네 곳.**
- [x] **Step 2: 남은 참조 확인.** Run: `git grep -n -E "tests/(check_git|check_pr|verify_mcp|verify_sb|post_review|sb_space|sb_fonts|review|review_record|review_bash_guard|common|skills|github|cloud_neutral)\.bats" -- AGENTS.md README.md docs/README.md docs/ARCHITECTURE.md docs/runbooks .agents .claude Makefile tools .github scripts tests`. Expected: 출력 없음.
- [x] **Step 3: 통과 확인.** Run: `make check`. Expected: exit 0, 220개. 이름 목록(`tests-t2.tsv`)이 `tests-base.tsv`와 같다.
- [x] **Step 4: 커밋** `test: name the single-subject test files after what they test` (`Task: 2`).

### Task 3: Split the multi-script test files

**Files:**
- Create: `tests/deploy-stack.bats`, `verify-vm.bats`, `show-status.bats`, `show-logs.bats`, `backup-notes.bats`, `restore-notes.bats`, `bootstrap-vm.bats`, `remote-provision-vm.bats`, `check-access.bats`, `open-tunnel.bats`
- Delete: `tests/vm_ops.bats`, `backup_restore.bats`, `bootstrap.bats`, `access.bats`
- Modify: `tests/helpers.bash` (`use_ssh_mode`, `use_provision_env`)

**Interfaces:**
- Produces:
  - `use_ssh_mode`: `vm_ops.bats:16-19`를 그대로 옮긴다. `verify-vm`과 `show-status`가 쓴다.
  - `use_provision_env`: `bootstrap.bats` setup의 `setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh swapon fallocate mkswap`, `use_vm_env`, `ETC_DIR`·`RUN_DIR`·`OS_RELEASE`·`ADMIN_USER`·`SWAP_FILE`이다. `bootstrap-vm` 테스트도 `provision-vm.sh`를 스텁 위에서 실제로 실행하므로 두 파일이 쓴다.

테스트는 이름 머리로 나눈다(이름은 그대로).

| 옛 파일 | 이름 머리 → 새 파일 |
|---|---|
| `vm_ops.bats` | `deploy …` → `deploy-stack`. `verify …`, `probe …`, `ssh mode: probe …`, `ssh mode: verify …` → `verify-vm`. `status …`, `ssh mode: status …` → `show-status`. `logs …` → `show-logs` |
| `backup_restore.bats` | `backup …` → `backup-notes`. `restore …`와 두 스크립트를 함께 도는 두 테스트("backup archive and manifest skip the model cache and restore accepts that archive", "a backup made by backup-notes.sh restores with restore-notes.sh and matches its manifest") → `restore-notes` |
| `bootstrap.bats` | `bootstrap-vm …` → `bootstrap-vm`, 나머지 → `remote-provision-vm` |
| `access.bats` | `access-check …` → `check-access`, `tunnel …` → `open-tunnel`, "a VM target that never reads the mode …" → `show-logs`(스펙 6절) |

- 파일 단위 도우미는 쓰는 테스트를 따라간다.
  - `vm_ops`의 `teardown`과 setup 7-11행(공인 IP, `VERIFY_ID`, MCP 픽스처, SilverBullet 쿠키)은 `verify-vm`만 쓴다.
  - `backup_restore`의 `make_archive`, `pack_archive`, `local_manifest`, `restore_with_answer`, `add_model_cache`는 `restore-notes`로 간다. `fail_command`와 `fix_backup_stamp`는 `backup-notes`로 간다.
  - 두 파일에서 쓰이게 되는 도우미는 `helpers.bash`로 옮긴다.

- [x] **Step 1: 나누기.** 각 새 파일의 setup에는 옛 setup 가운데 옮긴 테스트가 쓰는 스텁·환경·변수를 모두 둔다. SC2030·SC2031 지시문은 `make lint`가 그 지적을 내는 새 파일에만 둔다.
- [x] **Step 2: 목록 비교.** Run: 이름 목록 명령 → `tests-t3.tsv`, `diff "$WS/tests-t2.tsv" "$WS/tests-t3.tsv"`. Expected: 출력 없음(이름과 단언 수가 같음).
- [x] **Step 3: 통과 확인.** Run: `make check`. Expected: exit 0, 220개, not ok 0, 커버리지 94% 안팎(파일별 %가 Task 2와 같음).
- [x] **Step 4: 커밋** `test: give every VM, data and access script its own test file` (`Task: 3`).

### Task 4: Split repo.bats and main_checkout.bats by topic

**Files:**
- Create: `tests/repo-scripts.bats`, `tests/repo-make.bats`, `tests/repo-config.bats`
- Modify: `tests/repo-docs.bats` (테스트 두 개와 도우미 `markdown_files`, `markdown_links`를 받음; 34행의 "in repo.bats" 주석), `tests/backup-notes.bats` (backup 테스트 세 개)
- Delete: `tests/repo.bats`, `tests/main_checkout.bats`
- Modify: `AGENTS.md:12` (P6), `docs/ARCHITECTURE.md:77` (`tests/repo.bats` → `tests/repo-config.bats`), `.agents/skills/doc-authoring/SKILL.md:59` (상대 링크 검사도 `tests/repo-docs.bats`가 함)

| 새 파일 | 옮기는 테스트(47dbbc7의 이름) |
|---|---|
| `repo-scripts.bats` | every executable shell file enables strict mode; scripts avoid bash 4+ features; no script enables Tailscale Funnel |
| `repo-make.bats` | every Make target has a ## description and is declared .PHONY; no Make target is defined twice; `main_checkout`의 `make …` 세 개(setup, `make_host`, `make_in` 포함) |
| `repo-config.bats` | `compose …` 여섯 개; deploy and restore wait longer than the healthcheck start_period; SilverBullet is pinned …; .env is never tracked by git; .env variants are git-ignored …; CLAUDE.md only imports AGENTS.md; Gemini CLI reads AGENTS.md …; AGENTS.md fits the smallest rule file limit …(상수 `AGENTS_MD_MAX_BYTES` 포함); AGENTS.md defines the Code Review Rules …; the Claude reviewer agent …(두 개, `reviewer_hook_command` 포함); the reviewer hook command blocks (exit 2) … |
| `repo-docs.bats` | relative links in markdown files resolve; every gcloud command in runbooks and skills names the bm-personal configuration |
| `backup-notes.bats` | `main_checkout`의 `backup …` 세 개. setup이 내보내는 `BACKUP_DIR`를 테스트 안에서 `unset`하고 `make_worktree_fixture`를 부른다(옛 `use_backup_env`) |

- 위치를 정한 근거:
  - repo-config: 에이전트가 읽는 설정이고 compose 값을 읽는다(스펙 6절의 repo-config 목록, ADR 0007 결정 1).
  - repo-scripts: Funnel 금지는 스크립트 전체를 grep한다.
  - repo-docs: gcloud 플래그는 문서 안의 명령을 본다.
- 지우는 테스트: "git-workflow cleanup checks the worktree's backups before git worktree remove". 스킬 문장을 grep하는 테스트라서다(스펙 6절, 7.3절, ADR 0004 결정 2).
- 고치는 주석: `main_checkout.bats:12-13`, `:40`의 "same reason as tests/repo.bats:65-66"과 "same kcov workaround as make_host"는 이제 없는 줄을 가리킨다. 주석이 설명하던 이유를 그 자리에 직접 쓴다.

- [x] **Step 1: 나누기와 참조 고치기.**
- [x] **Step 2: 목록 비교.** Run: 이름 목록 명령 → `tests-t4.tsv`, `diff "$WS/tests-t3.tsv" "$WS/tests-t4.tsv"`. Expected: "git-workflow cleanup checks …" 한 줄만 빠진다.
- [x] **Step 3: 남은 참조 확인.** Run: `git grep -n -E "tests/(repo|main_checkout)\.bats" -- AGENTS.md README.md docs/README.md docs/ARCHITECTURE.md docs/runbooks .agents .claude Makefile tools .github scripts tests`. Expected: 출력 없음.
- [x] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 219개, not ok 0.
- [x] **Step 5: 커밋** `test: split repo.bats and main_checkout.bats by topic` (`Task: 4`).

### Task 5: Share the repeated test setup and checks

**Files:**
- Modify: `tests/helpers.bash`, 아래 도우미를 쓰는 테스트 파일들
- Move(`git mv`): `tests/fixtures/mcp-json` → `tests/fixtures/verify-mcp/json`, `tests/fixtures/mcp-sse` → `tests/fixtures/verify-mcp/sse`, `tests/fixtures/os-release` → `tests/fixtures/remote-provision-vm/os-release`

**Interfaces:**
- Produces (모두 `helpers.bash`):
  - `init_git_repo`: `$BATS_TEST_TMPDIR/work`에 main 브랜치의 git 저장소를 만들고 들어가 `agent@example.com`/`agent`로 빈 커밋 "chore: init"을 남긴다. `WORK`를 설정한다(`check-git.bats:5-10`과 `review-branch.bats:6-11`이 같았다).
  - `agent_commit TOOL SUBJECT [GIT_COMMIT_ARG...]`: `--allow-empty -m SUBJECT`에 `Assisted-by: TOOL model-x`, `Plan: 02`, `Task: 1` 트레일러를 단다. 옛 `agent_commit SUBJECT …`는 `agent_commit claude-code SUBJECT …`가 되고, 옛 `author_commit TOOL`은 `agent_commit TOOL "feat: change by TOOL"`이 된다.
  - `use_mcp_fixtures sse|json`: `tests/fixtures/verify-mcp/<종류>`를 `$BATS_TEST_TMPDIR/mcp-<종류>`로 복사하고 그 경로를 `CURL_FIXTURES`로 export한다. 테스트가 고치는 픽스처는 복사본이다.
  - `fake_cmd NAME BODY`: `$STUB_BIN/NAME`을 먼저 `rm -f`하고, `#!/usr/bin/env bash`와 BODY로 새 실행 파일을 만든다. `setup_stubs` 뒤에만 쓴다. 지우지 않고 `>`로 쓰면 스텁 링크를 따라 저장소 스텁을 덮어쓴다.
  - `assert_stub_called GREP_ARG...`와 `refute_stub_called GREP_ARG...`: `grep GREP_ARG... "$STUB_LOG"`가 찾으면 성공하고, 못 찾으면 기대한 줄을 출력하며 실패한다(refute는 반대이고, 찾은 줄을 출력한다). 옵션은 그대로 넘긴다(`refute_stub_called -F 'ssh '`).
  - `assert_log_order TEXT...`: TEXT마다 `$STUB_LOG`에서 처음 나오는 줄 번호(`grep -nF -m1`)가 순서대로 커지지 않거나 없으면, 그 로그를 출력하며 실패한다.
  - `assert_same_file EXPECTED ACTUAL`: 두 파일이 다르면 `diff`를 출력하며 실패한다.

- [x] **Step 1: 도우미를 쓰기 전에 대상 위치를 다시 만든다.** 조사(2026-10-21, 47dbbc7)에서 찾은 곳은 다음과 같다. Task 1~4로 줄 번호가 바뀌었으므로 같은 grep으로 다시 찾는다.
  - 임시 git 저장소 두 곳
  - 그 자리의 가짜 명령 다섯 곳: `fail_command`, `datebin`(같은 파일 `fix_backup_stamp`의 복사본이므로 `fix_backup_stamp` 호출로 바꾼다), 부분 쓰기 `cp`, `fakebin`의 `mktemp`, `fix_backup_stamp` 본문
  - "스텁이 불리지 않음" 40곳: `run grep … "$STUB_LOG"` 뒤 `assert_failure`, `grep -c` 뒤 `assert_output 0`
  - `run diff` 15곳
  - 로그 순서 4곳
- [x] **Step 2: 도우미를 더하고 위치마다 바꾼다.** 픽스처를 옮기고, `verify-mcp`·`verify-vm`은 `use_mcp_fixtures`, `use_provision_env`는 새 `os-release` 경로를 쓰게 한다. `$STUB_LOG.requests`처럼 다른 로그를 보는 검사는 그대로 둔다.
- [x] **Step 3: 목록 비교.** Run: 이름 목록 명령 → `tests-t5.tsv`, `diff "$WS/tests-t4.tsv" "$WS/tests-t5.tsv"`. Expected: 이름은 같고, 단언 수는 로그 순서를 바꾼 테스트에서만 다르다.
- [x] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 219개, not ok 0. 파일별 커버리지를 `$WS/coverage-t5.txt`로 남긴다(Task 6~9의 기준).
- [x] **Step 5: 도우미 실패 경로 확인(커밋하지 않음).** `tests/zz-helper-probe.bats`를 임시로 만든다. 아래 경우마다 테스트를 하나씩 둔다.
  - `assert_stub_called`에 없는 줄
  - `refute_stub_called`에 있는 줄(옵션 `-F` 포함)
  - `assert_log_order`의 뒤바뀐 순서와 없는 TEXT
  - `assert_same_file`에 다른 파일
  - `fake_cmd ssh 'exit 0'`을 `setup_stubs ssh` 뒤에 부른 뒤 `tests/stubs/ssh`가 바뀌지 않았는지 보는 테스트(이것은 통과해야 함)

  Run: `make test`. Expected: 처음 다섯 개만 not ok이고 도우미의 메시지가 보인다. 그다음 `git status --short tests/stubs`에 출력이 없다. 확인한 뒤 probe 파일을 지운다.
- [x] **Step 6: 커밋** `test: share the repeated test setup and checks through helpers.bash` (`Task: 5`).

### Task 6~9의 공통 Step

Task 6~9는 아래 Step을 각 Task의 표에 대해 같은 순서로 밟는다.

- [x] **Step 1: 합치기.** 표의 묶음마다 결과 테스트를 쓰고 원래 테스트를 지운다(Global Constraints의 합치기 규칙).
- [x] **Step 2: 지우기.** 표의 "지움" 행을 지운다. 줄이는 단언은 그 단언만 지운다.
- [x] **Step 3: 반복문 경우 확인(커밋하지 않음, Review Focus 4).** 합친 반복문마다 경우 하나를 골라, 그 경우의 입력을 정상값으로 바꾼 채 `make test`를 돌린다. Expected: 그 결과 테스트만 not ok이고, 메시지에 바꾼 경우가 나온다. 확인한 뒤 되돌린다.
- [x] **Step 4: 목록 비교.** Run: 이름 목록 명령 → `tests-t<N>.tsv`, 앞 Task의 목록과 `diff`. Expected: 표에 적힌 이름만 사라지거나 새로 생긴다. 차이를 Progress log에 묶음 번호와 함께 적는다.
- [x] **Step 5: 통과 확인.** Run: `make check`. Expected: exit 0, not ok 0, 커버리지 80% 이상. `coverage-t5.txt`보다 떨어진 파일은 줄 이유를 Progress log에 적는다.
- [x] **Step 6: 커밋.** 합치기(Step 1)와 지우기(Step 2)를 나눠 커밋한다. 메시지는 각 Task에 있다.

### Task 6: Merge and prune the VM, web and access tests

**Files:**
- Modify: `tests/{deploy-stack,verify-vm,show-status,show-logs,check-access,open-tunnel,bootstrap-vm,remote-provision-vm,sync-sb-space,upload-sb-fonts,verify-sb,verify-mcp,lib-vm,lib-sb,repo-make}.bats`, `tests/stubs/free`

**Interfaces:**
- Produces: lib 테스트의 결과 이름(아래 표). `lib-vm`과 `lib-sb`의 소비자 반복문은 스크립트를 실행하므로, 그 파일의 setup에 필요한 스텁(`ssh`, `curl`, `nc`, `docker`, `sudo`, `tailscale`)과 `use_vm_env`를 둔다.

| 묶음 | 지금(47dbbc7) | 결과 테스트 → 파일 |
|---|---|---|
| A1 `vm_env` | `vm_ops:32`의 VM `.env` 다섯 줄, `backup_restore:209-212`·`:440-443` | `lib-vm` "vm_env prints the loopback ports, the absolute data paths and SB_USER". deploy 테스트는 VM `.env`가 `vm_env` 출력과 같고(`assert_same_file`) 권한이 600인지만 본다 |
| A2 `require_vm` | `lib-vm:19`, `vm_ops:107`(BM_VM_HOST) | `lib-vm` "require_vm stops on an unknown BM_ACCESS in any case, a missing command or a missing VM setting, before any ssh"(`SSH`·`Ssh`, 없는 명령, `BM_VM_HOST`·`BM_VM_USER` 비움, 그리고 `ssh`는 통과) |
| A3 `require_vm` 소비자 | `vm_ops:259`(verify-vm), `access:66`(show-logs), `vm_ops:107`(deploy) | `lib-vm` "deploy, verify and logs stop on an unknown BM_ACCESS before they run ssh, curl or nc"(세 스크립트 반복) |
| A4 `require_free_port` | `access:87`의 `BM_TUNNEL_MCP_PORT=80`·13000 사용 중, `vm_ops:212` | `lib-vm` "require_free_port refuses a privileged port and a port in use, so both tunnels stop before ssh"(open-tunnel 두 경우, verify-vm `--read-only` 28737). `open-tunnel`에는 "tunnel refuses the tailscale mode before it runs ssh"만 남는다 |
| A5 `require_sb_user` | `verify_sb:58`(입력 8개), `:72`(env 파일 두 쌍과 마지막 줄 CRLF), `main_checkout:46`(`#` 잘림) | `lib-sb` "require_sb_user rejects an SB_USER that make or docker compose would change or that differs from its raw line in SB_ENV_FILE, without printing it, and accepts the last line without its CR". `repo-make`의 `main_checkout:46` 테스트는 지운다(make가 경로를 넘기는지는 `main_checkout:65`가 본다) |
| A6 `require_sb_user` 소비자 | `vm_ops:92`(deploy, ssh 0회), `verify_sb:58`(curl 0회) | `lib-sb` "deploy and verify-sb stop before they contact the VM or SilverBullet on an SB_USER that require_sb_user rejects" |
| A7 deploy 공간 파일 | `vm_ops:32`의 두 `diff`, `vm_ops:58`의 두 번째 deploy | 공간 파일 내용은 `sync-sb-space`가 본다. deploy 테스트는 관리 페이지가 생겼는지만 본다. `vm_ops:58`의 두 번째 실행(바뀌지 않으면 재생성 없음)은 `lib-sb:36`의 세 번째 호출과 같으므로 지운다 |
| A8 pull 실패 | `vm_ops:74` | "deploy writes nothing into the notes folder when the image pull fails"로 줄인다(`.gitignore`와 marker가 없음). 재실행 부분은 `vm_ops:58`과 같다. P2 뒤로 옛 단언은 언제나 참이었다(계획 16 판정) |
| A9 Serve와 Funnel(verify) | `vm_ops:165`, `:172` | "verify fails unless Serve sends 443 to Basic Memory and 8443 to SilverBullet with Funnel off on both"의 반복문에 Funnel(443)을 더한다 |
| A10 공인 IP 형식 | `vm_ops:158`, `:277` | "verify stops before any probe without a public IPv4"(비움, 값 없음 + 기존 10개) |
| A11 공인 포트 판정 | `vm_ops:270`, `:291`, `:298` | "verify fails when the public IP accepts a connection or nc rejects its options, and treats refused, timed out and ICMP-rejected probes as closed"(nc 결과 다섯 경우) |
| A12 verify 터널 정리 | `vm_ops:195`, `:222` | "ssh mode: probe checks through a verify tunnel on 127.0.0.1 and closes it, also when a check fails"(기본, `CURL_STUB_EXIT=7`). 성공 경우의 나머지 단언은 그대로 |
| A13 `--read-only` | `verify_sb:50` ⊂ `vm_ops:181` | `verify_sb:50` 지움 |
| A14 status 스왑 | `vm_ops:312`, `:327` | "status shows containers, memory and swap use, and warns only when no swap is active"(기본, 사용 200, 전체 0) |
| A15 access-check 추천 | `access:15`, `:29`, `:39` | "access-check recommends the mode that works on this network, or asks for BM_ACCESS_CHECK_URL when Tailscale is blocked and the tunnel was not checked"(세 경우와 기대 추천) |
| A16 인증 키 경로 | `bootstrap:131`, `:151`, `:159` | `bootstrap-vm` "bootstrap-vm passes the key on stdin only, from TS_AUTHKEY or the prompt, and removes its remote script also after a failed run"(세 경우) |
| A17 키 파일 | `bootstrap:43`, `:58` | `remote-provision-vm` "joins the tailnet with the key in a temp file that it removes, also when tailscale up fails"(`TS_STUB_UP_EXIT` 0, 1) |
| A18 Serve와 Funnel(provision) | `bootstrap:97`, `:109` | "fails when Serve is not active, misses the 8443 mapping or has Funnel on"(세 경우, `done` 없음) |
| A19 ssh 모드 bootstrap | `bootstrap:118`, `:181` | `bootstrap-vm` "bootstrap-vm in ssh mode never asks for a key or touches Tailscale, passes the mode to the VM, still sets up docker and the data dirs and points to make tunnel" |
| A20 스왑 | `bootstrap:196`, `:224` / `:211`, `:237` | "creates, formats and enables a swap file once and keeps other fstab entries, even when run twice" / "writes no fstab line when swap is already active or swapon fails" |
| A21 verify-mcp 성공 | `verify_mcp:14`, `:22`, `:28`, `:42`, `:49` | "passes a full round trip against SSE and JSON responses, sends the session id and the Host header on every later request, masks the session id and writes, reads and deletes the same note"(SSE, JSON, SSE + `--host-header`) |
| A22 verify-mcp 실패 | `verify_mcp:66`, `:75`, `:82`, `:111` | "fails on a missing tool, a non-200 status, a JSON-RPC error or no connection"(경우마다 단계 이름) |
| A23 note 정리 | `verify_mcp:56`, `:89`, `:101` | "deletes the leftover note during cleanup when write_note fails or reports an error, or the read-back does not match"(세 경우, `delete_note` 1회) |
| A24 container 사용자 | `sb_fonts:15`의 `sudo -u #1000` ⊂ `sb_space:59` | `sb_fonts:15`에서 그 단언만 지운다 |
| A25 present/absent | `lib-sb:27` ⊂ `sb_space:13` | `lib-sb:27` 지움 |
| A26 `mask` | `common:9`, `bootstrap:131`의 `tske****`, `verify_mcp:28`의 `test****` | 형식은 `lib-common`이 본다. 스크립트 테스트는 비밀값과 세션 id 전체가 출력에 없다는 `refute_output --partial`만 남긴다 |
| 지움 | `vm_ops:100` "deploy reports an unhealthy container" | 문구만 확인한다. 이름과 달리 재생성 단계의 실패를 지나간다. 마지막 시작의 실패는 `set -e`로도 드러난다 |
| 지움 | `vm_ops:336` (P4), `verify_mcp:118`(usage 문구) | ADR 0004 결정 2 |
| 정리 | `bootstrap`의 `setup_stubs docker` 열 번 | `remote-provision-vm`의 setup으로 옮긴다. docker 설치를 보는 "installs tailscale with the official script …"는 처음에 `rm "$STUB_BIN/docker"`로 링크를 지운다(옛 `bootstrap:21-22`가 tailscale에 쓰던 방식). docker 설치를 보는 다른 테스트(ssh 모드)는 A19로 `bootstrap-vm`에 옮기고, 그 파일은 docker 스텁을 두지 않는다 |
| 정리 | `stubs/free`의 `FREE_STUB_AVAILABLE_MB` | 지우고 available 3000을 고정값으로 둔다. "memory used: 23%"가 그 값에 기댄다 |

- 합치지 않는 약한 묶음과 그 이유:
  - 서로 다른 코드를 검사한다: Serve가 loopback을 가리킴(설정·검증·출력), loopback 바인딩 성공·실패 한 쌍, 터널이 바로 끝날 때(open-tunnel의 종료 코드와 verify의 메시지), VM Tailscale 상태(verify 실패와 status 경고), uid 1000 데이터 폴더(tailscale·ssh 모드), `access_hint`의 ssh 문구, ssh 옵션 모양, ssh 모드 verify 실패들
  - 이미 다른 묶음에 들어갔다: 비밀값 비출력 패턴, 사전 검사 뒤 아무것도 닿지 않음
  - 두 터널의 `ssh -L` 줄: 스크립트마다 옵션이 다른 정확한 줄이라 그대로 둔다
- 커밋: `test: merge the VM, web and access tests that check one behavior` / `test: drop the VM, web and access tests ADR 0004 rules out` (`Task: 6`).

### Task 7: Merge and prune the backup and restore tests

**Files:**
- Modify: `tests/backup-notes.bats`, `tests/restore-notes.bats`

| 묶음 | 지금(47dbbc7) | 결과 테스트 |
|---|---|---|
| B1 중지 뒤 실패 | `backup_restore:94`, `:105`, `:126`, `:177` | "backup restarts the container, keeps no file of its run and spares earlier backups when the stop, the listing, the stream or the checksum fails". 경우마다 날짜를 고정하고 이전 백업 세 파일을 둔다. 메시지, 이전 파일만 남고 그대로임, `compose start`를 본다 |
| B2 중지 전 거부 | `:145`, `:165` | "backup refuses a name that another backup or another run holds, without stopping the container or touching those files" |
| B3 ssh 전 거부 | `:254`, `:265`, `:276`, `:286`, `:300`, `:318` | "restore refuses before any ssh when the answer is not yes, SB_USER is invalid, a backup file is missing, the checksum is wrong or the archive holds a symlink, a ../ or an absolute path". 아홉 경우 모두 실패, 가리는 문구, ssh 0회, `a.md` 그대로를 본다 |
| B4 중지 뒤 롤백 | `:239`, `:336`, `:349`, `:359`, `:378`, `:411`, `:448` | "restore rolls the previous data, compose.yaml and .env back when the extract, the manifest, the upload, the swap, the pages or the start fails". 파이프라인 순서의 여섯 경우다. 모든 경우에 이전 상태, "rolled back", 임시 파일 없음을 본다. 시작 실패에만 `.failed-*`와 `--force-recreate`를 보고, 시작 전 실패에만 일반 `up -d --wait` 없음을 본다 |
| B5 복원 성공 | `:190`, `:215`, `:432` | "restore replaces the data, writes the space files while stopped and the VM .env, on an existing and on a recreated VM". 두 경우 모두 `vm_env`와 같은 `.env`와 600을 본다. 기존 VM에만 `.prev-*`, 재생성된 VM에만 `.prev-*` 없음을 본다 |
| B6 왕복 | `:76`, `:467` | "a backup made by backup-notes.sh skips the model cache and restores with restore-notes.sh to match its manifest"(`add_model_cache`를 왕복 앞에 둠) |
| B7 main checkout | `main_checkout:81`, `:94` | "backup saves into the main checkout's backups/, from a linked worktree and from GIT_DIR" |
| 줄임 | `backup_restore:49`의 매니페스트 형식 단언 | 형식은 `lib-vm`의 `manifest_cmd`가 본다. 세 파일이 생기는지만 남긴다 |

- 합치지 않는 약한 묶음: 이전 데이터가 없는 VM의 실패와 성공(`:397`, `:432`, 기대가 반대), 링크된 worktree에서 main checkout으로 가는 상태(make, backup, 리뷰 출력의 다른 코드), SB_USER를 누가 언제 받는지(Makefile 내보내기와 함수), `report_problems`와 `review_report_prefix`의 lib 테스트와 스크립트 경로.
- `main_checkout:103`(main checkout을 찾지 못함)은 다른 fixture가 필요해서 B2에 넣지 않는다.
- 커밋: `test: merge the backup and restore tests that check one behavior` / `test: drop the backup assertions the library tests already make` (`Task: 7`).

### Task 8: Merge and prune the git, review and doc tool tests

**Files:**
- Modify: `tests/{check-git,check-pr,review-branch,post-review,post-review-record,guard-reviewer-bash,lib-docs,create-doc}.bats`, `tests/stubs/claude`, `tests/stubs/gh`

| 묶음 | 지금(47dbbc7) | 결과 테스트 |
|---|---|---|
| C1 check-git 성공 | `check_git:22` ⊂ `:100`, `:119`, 그리고 `:30` | "passes plan and work branches whose commits carry every trailer, with a merge from main and as an explicit branch from a detached HEAD"(세 경우). `:22`는 지운다 |
| C2 브랜치 규칙 | `:38`, `:44`, `:51`, `:128` | "fails on main, a detached HEAD and a branch outside plan/ and work/, also as an explicit branch" |
| C3 없는 ref | `:112`, `:137` | "fails instead of passing when the base or the explicit branch does not exist" |
| C4 트레일러 거부 | `check_git:58`, `:68`, `:79` / `check_pr:39`, `:55`, `:69` | 파일마다 하나: "lists every missing, malformed and forbidden trailer with its commit" / "fails on missing, misplaced, malformed, repeated and forbidden trailers and session links in the body" |
| C5 PR 제목 | `check_pr:30`, `:80` | "rejects an empty title and titles that are not '<type>: <description>'" |
| C6 리뷰 성공 | `review:28`, `:51`, `:63` | "codex and claude review another vendor's branch in a detached worktree and write both reports; claude runs as the guarded branch-reviewer in plan mode without user or system git config"(리뷰어 두 경우) |
| C7 같은 벤더 | `review:71`, `:80` | "refuses a same-vendor reviewer unless the human allowed it, and tells only that reviewer" |
| C8 리뷰 실패 | `review:111`, `:152` | "leaves no worktree and no report of the round when the change review or the plan review fails" |
| C9 리뷰 거부 | `review:127`, `:137`, `:165`, `:174` | "refuses a stale review worktree, a leftover review-base branch, a relative REVIEW_OUT_DIR and an unknown reviewer, and leaves what exists alone". `:174`의 usage 문구 단언은 "리뷰어 CLI를 부르지 않음"으로 바꾼다 |
| C10 게시하지 않음 | `post_review:29`, `:38` / `review_record:34`, `:42` | 파일마다 하나: "posts nothing when a file of the round is missing or too long" / "writes nothing when the PR has several records or gh reports no login" |
| C11 기록 만들기와 고치기 | `review_record:11`, `:25` | "creates the Review record when the PR has none and updates the one it has" |
| C12 guard 차단 | `review_bash_guard:44`, `:64`, `:71`, `:78`, `:99` / `:124`, `:132` | "blocks shell operators, file-writing and helper options with their abbreviations, anything but plain single-spaced tokens and every other command" / "fails closed on bad hook input and without jq" |
| C13 레지스트리 오류 | `lib-docs:34`, `:50` | "doc_types fails on a reordered header, a missing separator, a short row and an empty cell" |
| C14 create-doc 거부 | `create-doc:85`, `:95` | `:95`의 반복문에 "금지된 타입"을 더한다 |
| 정리 | `stubs/claude`의 `CLAUDE_STUB_EXIT`, `stubs/gh`의 `GH_STUB_EXIT` | 지운다(어떤 테스트도 쓰지 않음) |

- 합치지 않는 묶음: check-git과 check-pr의 트레일러 검사는 파서가 다른 두 코드다. 각 파일 안에서만 합친다(C4). 이 밖에 리뷰 2회차의 성공과 남은 브랜치(같은 setup만 공유), `lib-git`의 두 테스트, `lib-docs:23`과 create-doc 성공이 있다. `lib-*.bats`는 함수의 정본 위치다(스펙 7.2절).
- 커밋: `test: merge the git, review and doc tool tests that check one behavior` / `test: drop the duplicate check-git test and the unused stub options` (`Task: 8`).

### Task 9: Merge and prune the repo-wide tests

**Files:**
- Modify: `tests/{repo-scripts,repo-make,repo-config,repo-docs,repo-skills,repo-cloud-neutral}.bats`, `tests/helpers.bash`

**Interfaces:**
- Produces (`helpers.bash`, 같은 코드가 둘 이상의 파일에 있었다):
  - `front_value FILE KEY`: `repo-docs`의 `front_value`, `repo-skills`의 `field_of`와 그 인라인 사본
  - `outside_code`와 `markdown_files`: `repo-docs`의 `outside_code`, `markdown_links`의 같은 awk, 같은 `git ls-files` 줄
  - `refute_matches DIR ERE [GREP_FLAG...]`: grep exit 1이면 성공, 찾으면 그 줄을 출력하며 실패, grep 오류(2 이상)는 실패. bash 3.2 금지 문법, Funnel, `AGENT_ID`, 참조 파일, 클라우드 이름 검사가 쓴다. `repo-skills`의 `|| true`가 grep 오류를 삼키던 것도 없어진다.

| 묶음 | 지금(47dbbc7) | 결과 테스트 → 파일 |
|---|---|---|
| D1 Make 타깃 | `repo:35`, `:47` | `repo-make` "every Make target is defined once, has a ## description and is declared .PHONY" |
| D2 digest 고정 | `repo:53`, `:118`의 SilverBullet 이미지 | `repo-config` "every compose image is pinned by digest"(모든 `image:` 줄). SilverBullet의 `-slim`은 D4에 남긴다 |
| D3 basic-memory 서비스 | `repo:67`, `:74`(BM), `:92`, `:101`, `:110`(BM), `:118`(BM 네트워크) | "basic-memory serves streamable-http on /mcp, probes port 8000 without --version, has a start_period of at least 240 s that HEALTH_TIMEOUT_SECONDS exceeds, restarts unless-stopped and uses only its own network"(`service_block`으로 범위를 그 서비스로 좁힘) |
| D4 SilverBullet 서비스 | `repo:118` 나머지, `:110`(SB), `:74`(SB의 --version 없음) | "SilverBullet is a -slim image, needs a login, has no shell or runtime API, restarts unless-stopped, probes without --version and shares no network or data beyond the notes" |
| D5 `.env` | `repo:138`, `:165` | "the .env files are never tracked and are git-ignored, but .env.example is not ignored" |
| D6 에이전트 설정 | `repo:147`, `:152` | "Claude Code and Gemini CLI load AGENTS.md" |
| D7 리뷰어 에이전트 | `repo:181`, `:189`, `:213` | "the Claude reviewer agent cannot edit files and runs every Bash call through the guard hook, which blocks (exit 2) even when the guard is missing". `git status` 없음 단언은 남긴다. guard가 막는 명령을 에이전트 지시문이 시키지 않게 한다(`dc423de`) |
| D8 Code Review Rules | `repo:174` | 제목 줄 단언만 남긴다. `scripts/review-branch.sh:129`, `.claude/agents/branch-reviewer.md:15`, `branch-review` 스킬이 이름으로 가리키기 때문이다. `P0.*P1.*block the merge` 문장 단언은 지운다(ADR 0007 결정 2) |
| D9 Markdown 경로 | `repo:240`, `repo-docs:98` | `repo-docs` "every relative link and every docs path in tracked Markdown, scripts, skills and AGENTS.md resolves". 수집기 하나가 `파일·종류·대상`을 내고, 링크는 파일 폴더 기준 `-e`로, docs 경로는 저장소 기준 `-f`로 본다. 두 범위(코드 블록 포함 여부)는 그대로 둔다 |
| D10 문서 파일 | `repo-docs:64`, `:157`, `:173` | "every file under docs/ is a single file or a typed document with a valid name, front matter and no template blank". 문제를 모두 모아 한 번에 낸다(ADR 0007 결정 3) |
| D11 날짜 형식 | `repo-docs:10`의 `DATE_PATTERN` | `scripts/lib/docs.sh`의 `DOC_DATE_PATTERN`을 쓴다(setup이 이미 source함) |
| D12 스킬 frontmatter | `skills:22`, `:36`, `:49`, `:68` | `repo-skills` "every SKILL.md frontmatter uses only standard keys on one line, the directory name in the name format, a plain description with 'Use when' and length limits". 한도는 표 하나(name 64, description 1024, compatibility 500)로 두고, description 비어 있음 단언은 남긴다 |
| D13 스킬 폴더 | `skills:85`, `:99` / `:105`, `:116` | "skill folders hold only SKILL.md and the allowed folders, with no nested SKILL.md" / "every bundled file is named in SKILL.md and reference files point to no other file of their skill" |
| D14 스킬 등록 | `skills:122`, `:137` | "every skill is linked both ways and listed in AGENTS.md and README.md". 스킬 목록이 비면 실패하는 단언을 더한다. 지금은 `skills:155`만 그 경우에 실패한다 |
| D15 클라우드 이름 | `cloud_neutral:17`, `:27`, `:33` | `repo-cloud-neutral` "the scan flags a provider name, and scripts and skills name none, comments included". 첫 경우는 임시 파일로 스캔이 이름을 잡는지 보는 확인이다. 스펙 7.3절이 남기라 한 검사를 반복문의 첫 경우로 옮긴다 |
| D16 gcloud 범위 | `repo:258`의 `.agents/skills/*/SKILL.md` | 그 범위를 뺀다. 스킬에 gcloud가 한 줄이라도 있으면 D15가 먼저 실패하므로, 이 범위는 혼자서는 실패할 수 없다 |
| 지움 | `skills:155` "operational skills bm-upgrade, bm-recover and bm-diagnose exist" | 스펙 7.3절, ADR 0004 결정 2(변경 감지) |

- 합치지 않는 약한 묶음과 그 이유:
  - 규칙의 정본이나 대상 파일이 다르다: 레지스트리 행을 도는 두 검사(셀 값과 번호), 크기 한도(AGENTS.md 바이트와 SKILL.md 줄), 포트 127.0.0.1(파일 전체를 봐서 새 서비스도 잡음), AGENTS.md 제목 검사 두 개, 워크플로 두 검사
  - 합치면 동작이 바뀐다: strict mode와 bash 3.2 검사(파일 집합이 달라, 합치면 bash 3.2 검사가 스텁까지 넓어짐)
  - 대상이 달라 도우미로 얻는 것이 적다: 빈 목록 방어 줄
- 커밋: `test: merge the repo-wide tests that check one rule` / `test: drop the repo-wide checks ADR 0004 and 0007 rule out` (`Task: 9`).

### Task 10: Add the script-authoring skill and make new-script

**Files:**
- Create: `scripts/lib/layout.sh`, `tests/lib-layout.bats`, `scripts/create-script.sh`, `tests/create-script.bats`
- Create: `.agents/skills/script-authoring/SKILL.md`, `assets/{script,remote,lib}.sh`, `assets/{script,remote,lib}.bats`, `assets/.shellcheckrc`, 링크 `.claude/skills/script-authoring` → `../../.agents/skills/script-authoring`
- Modify: `Makefile` (`new-script` 타깃과 `.PHONY`), `AGENTS.md` `## Skills`(P6), `README.md:57` (스킬 목록에 `script-authoring`(스크립트·테스트 작성 규칙)), `docs/ARCHITECTURE.md:43` (라이브러리 목록에 layout), `tests/repo-scripts.bats` (strict mode 검사에서 lib 템플릿 `assets/lib.sh` 제외)

**Interfaces:**
- Produces:
  - `scripts/lib/layout.sh`(`common.sh`를 source, source 방지 줄 `_BM_LIB_LAYOUT`, 첫머리 함수 색인)
    - `readonly SCRIPT_AUTHORING_SKILL=".agents/skills/script-authoring/SKILL.md"`, `readonly SCRIPT_TEMPLATES_DIR=".agents/skills/script-authoring/assets"`. 저장소 기준 경로다.
    - `script_verbs SKILL_FILE`: `## Verbs` 아래 표의 첫 칸(백틱 제거)을 한 줄에 하나씩 낸다. 제목이나 표가 없거나 첫 칸이 빈 행이 있으면 고칠 곳을 말하며 die한다.
    - `pair_test PATH`: `scripts/<n>.sh` → `tests/<n>.bats`, `scripts/remote/<n>.sh` → `tests/remote-<n>.bats`, `scripts/lib/<n>.sh` → `tests/lib-<n>.bats`. 다른 경로는 die한다.
  - `scripts/create-script.sh NAME [KIND]`: `KIND`는 `script`(기본), `remote`, `lib`이다. Usage는 `make new-script NAME=<name> [KIND=script|remote|lib]`이다.
    - script와 remote의 이름은 `^[a-z0-9]+(-[a-z0-9]+)+$`이고 첫 낱말이 동사 표에 있어야 한다. lib 이름은 `^[a-z0-9]+(-[a-z0-9]+)*$`이다.
    - 스크립트와 짝 테스트 가운데 하나라도 있으면 아무것도 쓰지 않고 실패한다.
    - 템플릿 `assets/<KIND>.sh`, `assets/<KIND>.bats`의 `{{name}}`을 NAME으로 바꾼다. lib는 `_BM_LIB_NAME`을 `_BM_LIB_<NAME을 대문자로, - → _>`로 바꾼다(`tr`, bash 3.2). script와 remote에는 실행 권한을 준다.
    - 두 경로를 출력하고, 끝에 "add a Make target with a ## description and .PHONY if people run it"을 출력한다.
  - 템플릿:
    - `script.sh`: shebang, `set -euo pipefail`, 머리 주석 `{{…}}` 두 줄(목적, usage), `lib/common.sh` source, `main` 안의 `die "not implemented: write tests/{{name}}.bats first"`, `main "$@"`
    - `remote.sh`: source 없이 자기 `log`/`die`
    - `lib.sh`: source 방지 줄, `common.sh` source, 함수 색인 주석, `main` 없음
    - `.bats` 셋: `load helpers`(P2), 성공 경로 하나와 실패 경로 하나의 자리. 작성자가 채울 칸은 `{{…}}`다.
  - `SKILL.md`(영어, `skill-authoring` 규칙) 내용:
    - Rules: 테스트 먼저, remote는 source 금지, 도우미를 쓰기 전에 라이브러리 색인 읽기
    - Name and place: 스펙 3·4·6절
    - `## Verbs` 표: 스펙 4절의 15행이고, 이후 정본은 이 표다
    - Libraries: 파일마다 한 줄
    - Tests: 짝 이름, `tests/stubs/<command>`, `tests/fixtures/<test name>/`, `helpers.bash`의 도우미, ADR 0004 결정 2, 같은 함수의 동작은 lib 테스트에 한 번(Global Constraints의 합치기 규칙)
    - Make targets: `##` 설명과 `.PHONY`, `tests/repo-make.bats`가 검사
    - Steps: `make new-script` → 테스트 RED → 구현 → `make check`
    - Gotchas: 계획 16의 교훈. kcov에서 `bash -c` 최상위의 `BASH_SOURCE`, trap 안의 인자 없는 `return`, `x="$(fn)" || exit 1`
    - bash 3.2 규칙은 `AGENTS.md` Invariants를 가리킨다.
  - description: "Creates and changes this repo's bash scripts, libraries, Make targets and bats tests with make new-script and the templates in assets. Use when adding, renaming or editing a script under scripts/, a Make target, a bats test, a stub or a fixture, or when make check reports a missing pair test or an unknown verb. Not for documents (use doc-authoring) or skills (use skill-authoring)."

- [x] **Step 1: 실패하는 테스트 작성.**
  - `lib-layout.bats`
    - "script_verbs reads the first column of the table under ## Verbs and stops when the table is missing": 임시 SKILL 파일에 두 행 표를 두고, 제목이 없는 파일도 만든다.
    - "pair_test maps scripts, remote scripts and libraries to their test and refuses other paths": 반복문 하나.
  - `create-script.bats`. `create-doc.bats`의 setup처럼 임시 git 저장소에 skill과 assets를 복사한다.
    1. "creates a script, a remote script and a library with their pair test from the templates": KIND 셋의 경로, 실행 권한(lib은 없음), `{{name}}`과 `_BM_LIB_NAME`이 남지 않음, 각 파일의 `bash -n` 통과를 본다.
    2. "refuses a name whose first word is not a verb of the table or that has no object, and writes nothing"
    3. "refuses when the script or its test already exists and leaves both untouched": Review Focus 6.
- [x] **Step 2: 실패 확인.** Run: `make test`. Expected: 위 다섯 테스트만 실패한다(`scripts/lib/layout.sh`, `scripts/create-script.sh` 없음).
- [x] **Step 3: 구현.** `layout.sh`, `create-script.sh`, 템플릿, skill, 링크, Makefile 타깃, `AGENTS.md`·`README.md`·ARCHITECTURE를 만들고 고친다.
- [x] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, not ok 0. `repo-skills` 테스트(색인 두 곳, 링크, frontmatter, 묶음 파일 이름)가 통과한다.
- [x] **Step 5: 생성 결과 lint 확인(커밋하지 않음).** Run: `make new-script NAME=show-probe`, `make new-script NAME=check-probe KIND=remote`, `make new-script NAME=probe KIND=lib`, 그다음 `make lint`. Expected: 세 명령이 exit 0이고, 생성 파일이 실제 위치에서 shellcheck와 shfmt를 통과한다. 이어서 `make test`. Expected: 생성된 테스트의 성공 경로 자리만 not ok다(템플릿의 `die`). 생성 파일 여섯 개를 지우고 `git status --short`로 남은 것이 없는지 본다.
- [x] **Step 6: 스킬 시험(`skill-authoring`의 Test the skill).** 사용자 말투의 프롬프트 셋과 비껴가는 프롬프트 둘을 쓴다.
  - 쓸 것: "백업 목록을 보여 주는 스크립트를 추가해 주세요", "make target 하나 더 만들어 주세요", "이 bats 테스트에 스텁을 더해 주세요"
  - 비껴갈 것: "런북을 새로 써 주세요"(doc-authoring), "스킬 설명을 고쳐 주세요"(skill-authoring)

  새 에이전트 세션에서, 바꾸지 말고 계획만 말하게 해서 main checkout(기준)과 이 worktree를 비교한다. 결과를 Progress log에 적는다.
- [x] **Step 7: 커밋** `feat: add the script-authoring skill, its templates and make new-script` (`Task: 10`).

### Task 11: Check script pairs, names and paths

**Files:**
- Modify: `tests/repo-scripts.bats` (검사 1~5), `AGENTS.md:15`, `:18`, `:45-46` (P6)

**Interfaces:**
- Consumes: `script_verbs`, `pair_test`, `SCRIPT_AUTHORING_SKILL` (Task 10), `refute_matches` (Task 9)

검사(스펙 9절)는 저장소를 반복문으로 돈다. 실패 메시지는 파일, 어긋난 값, 허용 값, 고칠 곳(`make new-script NAME=…` 또는 짝 이름)을 출력한다(ADR 0007 결정 3).

1. "every script and library has its pair test, and every test that is not repo-*.bats pairs an existing script": `scripts/*.sh`, `scripts/remote/*.sh`, `scripts/lib/*.sh`마다 `pair_test` 파일이 있다. 그 집합과 `tests/*.bats` 가운데 `repo-*.bats`가 아닌 파일이 같다.
2. "scripts in scripts/remote source no library": `scripts/remote/*.sh`에 `lib/`를 source하는 줄이 없다.
3. "every topic library sources common.sh": `common.sh` 말고 `scripts/lib/*.sh`마다 `common.sh`를 source하는 줄이 있다.
4. "every executable script is named <verb>-<object>.sh with a verb from the script-authoring table": `scripts/*.sh`, `scripts/remote/*.sh`.
5. "every scripts/…sh path in the maintained docs, skills, Makefile, .github and .claude/agents names an existing file": `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/runbooks/*.md`, `.agents/skills/` 아래 모든 파일, `Makefile`, `.github/` 아래, `.claude/agents/` 아래. 코드 블록도 포함하고, 정규식은 `scripts/[A-Za-z0-9_./-]+\.sh`다. `<`나 `{`가 든 예시 경로는 이 정규식에 걸리지 않는다.

- [x] **Step 1: 검사 다섯 개 작성.**
- [x] **Step 2: 실패 확인(심은 위반, 커밋하지 않음).**
  - 심는 위반:
    - `scripts/frob-probe.sh`(동사 아님, 짝 없음, 실행 권한)
    - `tests/ghost-probe.bats`(스크립트 없음)
    - `scripts/remote/check-probe.sh`(`lib/common.sh` source)와 그 짝 `tests/remote-check-probe.bats`
    - `scripts/lib/probe.sh`(`common.sh` source 없음)와 짝 `tests/lib-probe.bats`
    - `docs/ARCHITECTURE.md` 끝에 `scripts/nope-probe.sh` 한 줄
  - Run: `make test`. Expected: 검사 1~5가 모두 not ok이고, 메시지가 심은 파일을 하나씩 이름으로 말한다. 심은 것을 지우거나 되돌리고 `git status --short`로 확인한다.
- [x] **Step 3: `AGENTS.md` 15, 18, 45, 46행을 P6 문구로 바꾼다.**
- [x] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, not ok 0, 커버리지 80% 이상.
- [x] **Step 5: 커밋** `test: check script pairs, names and documented script paths` (`Task: 11`).

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과와, `tests-base.tsv`에서 `tests-t9.tsv`까지의 이름 수(220 → …)를 `Verified`로 적는다. `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 계획 16 최종 리뷰 M4(`scripts/restore-notes.sh`가 `present`가 아닌 답을 "이전 데이터 없음"으로 읽음)와 `bm-diagnose` 오류 카탈로그의 curl 시간 초과 행은 동작이나 운영 문서를 바꾸므로 이 계획 밖이다(계획 16 Follow-ups).
- `repo-docs.bats`의 `ALLOWED_KEYS`, `ARCHITECTURE_ROW`는 `docs/README.md`의 메타데이터 표를 되풀이한다. slug 정규식도 `scripts/create-doc.sh`와 겹친다. 정본에서 읽으려면 레지스트리 파서를 넓히거나 스크립트 상수를 라이브러리로 옮겨야 해서, 이 계획에서는 그대로 둔다.
- kcov가 세는 테스트가 지나가지 않는 분기가 있다.
  - 조사에서 찾은 것: `upload-sb-fonts.sh --local`(`make sb-fonts LOCAL=1`), 마지막 시작이 건강하지 않을 때의 `scripts/deploy-stack.sh:42-43`.
  - Task 6 뒤에 생긴 것: `scripts/deploy-stack.sh:17-18`(재생성 실패, `vm_ops:100`을 지운 뒤), `scripts/show-status.sh:43-44`(메모리 읽기 실패, P4), `scripts/verify-mcp.sh:36`(`--host-header` 뒤의 옵션, usage 테스트를 지운 뒤), `scripts/remote/provision-vm.sh:184`(ssh 모드). 마지막 것은 `bootstrap-vm.bats`가 `/tmp` 복사본으로만 실행해 kcov가 세지 않는다(A19).
  - 새 테스트를 더하는 일이라 이 계획의 정리 범위가 아니다.
- `restore-notes.sh`가 `require_sb_user`의 형식 검사(`scripts/lib/sb.sh:38-39`)에서 멈추는지 보는 테스트가 없다. `lib-sb`의 소비자 반복문에 `restore-notes.sh`를 더하면 된다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-21 | Verified | 기준(`main` 47dbbc7, 계획 16 병합 뒤): bats 파일 26개, 테스트 220개, 3,321행. `setup_stubs`는 14개 파일, `use_vm_env`는 9개 파일이 쓴다. 짝이 없게 되는 스크립트는 없다(`create-doc.bats`, `lib-docs/git/sb/vm.bats`는 이미 짝 이름). 쓰이지 않는 스텁 옵션은 `CLAUDE_STUB_EXIT`, `GH_STUB_EXIT`, `FREE_STUB_AVAILABLE_MB` 셋이다. 살아 있는 파일 가운데 테스트 파일 이름을 적은 곳: `AGENTS.md:12`, `:50`, `README.md:57`, `docs/ARCHITECTURE.md:53`, `:77`, `.agents/skills/doc-authoring/SKILL.md:59`, `.agents/skills/skill-authoring/SKILL.md:8`. |
| 2026-10-21 | Command | `make -k lint SH_FILES="<tests/*.bats>"`(파일은 바꾸지 않음) |
| 2026-10-21 | Verified | 위 명령: shellcheck v0.11.0이 `.bats` 26개를 파싱 오류 없이 읽고 지적 162건을 냈다(SC2031 102, SC2030 30, SC2016 16, SC2164 6, SC1007 4, SC2034 2, SC2086 1, SC2001 1). SC2030·SC2031은 `access`, `backup_restore`, `bootstrap`, `vm_ops`의 `@test` 안 `export`에서만 나왔다. |
| 2026-10-21 | Verified | `.editorconfig`에 `[*.bats]`(스크립트와 같은 서식)를 잠시 더하고 `make fmt SH_FILES="<tests/*.bats>"`: exit 0, 바뀐 곳은 `tests/repo-docs.bats` 2줄, `tests/repo.bats` 1줄뿐이다. shfmt v3.12.0이 dialect 키 없이 bats를 처리한다. 두 파일과 `.editorconfig`는 되돌렸다. |
| 2026-10-21 | Verified | 템플릿 폴더 모양의 임시 스크립트(`lib/common.sh`가 없는 곳에서 source)를 `make lint`: SC1091(info) "Not following: lib/common.sh"로 exit 1. 임시 파일은 지웠다(P1의 근거). |
| 2026-10-21 | Verified | 테스트 220개를 세 묶음(VM·웹·접속 83개, 데이터·git·문서 도구 89개, 저장소 전체 48개)으로 나눠 하나씩 분류했다(읽기 전용 서브에이전트 셋). 테스트마다 대상, 조건, 단언, 그 동작을 만드는 lib 함수, ADR 0004 결정 1의 분류를 적었다. 비슷한 묶음은 97개(VM 41, 데이터·git 28, 저장소 28)이고, 강한·중간 묶음을 Task 6~9의 표로 옮겼다. |
| 2026-10-21 | Verified | 분류 중 찾은 기존 테스트의 결함(원래 있던 것): `vm_ops.bats:100` "deploy reports an unhealthy container"는 새 notes 폴더에서 `recreate_basic_memory`의 `up -d … --force-recreate`에서 먼저 실패한다. 그래서 이름이 말하는 마지막 시작(`scripts/deploy-stack.sh:43`)의 분기를 지나가지 않는다. `vm_ops.bats:74`는 pull(`deploy-stack.sh:36`)이 공간 파일(`:39`)보다 먼저라서, 첫 실행의 단언이 언제나 참이다. |
| 2026-10-21 | Verified | `scripts/review-branch.sh:129`, `.claude/agents/branch-reviewer.md:15`, `.agents/skills/branch-review/SKILL.md:16`이 `AGENTS.md`의 "Code Review Rules"를 이름으로 가리킨다(D8의 근거). `repo.bats`의 `git status` 단언은 guard hook을 도입한 `dc423de`가 더했다(D7). |
| 2026-10-21 | Verified | Task 1: `Makefile`의 `SH_FILES`와 `.editorconfig`에 `.bats`를 더한 뒤 `make lint`: exit 2, 지적 162건(SC2031 102, SC2030 30, SC2016 16, SC2164 6, SC1007 4, SC2034 2, SC2086 1, SC2001 1), 파싱 오류 없음. `make fmt`가 바꾼 파일은 `tests/repo-docs.bats`(2줄)와 `tests/repo.bats`(1줄)뿐이다. 수정 뒤 `make lint` exit 0, `make check` exit 0, ok 220개, not ok 0, 총 줄 커버리지 94.50%(최소 80%). 이름 목록(`tests-t1.tsv`)은 `tests-base.tsv`와 같다. SC2086(`vm_ops.bats`)은 한 경우에 `VAR=값` 단어가 둘이라 따옴표 대신 disable 주석으로 처리했다. |
| 2026-10-21 | Verified | Task 2: 이름 변경 14개를 `git mv`로 했다(유사도 100%): `check_git`→`check-git`, `check_pr`→`check-pr`, `verify_mcp`→`verify-mcp`, `verify_sb`→`verify-sb`, `post_review`→`post-review`, `sb_space`→`sync-sb-space`, `sb_fonts`→`upload-sb-fonts`, `review`→`review-branch`, `review_record`→`post-review-record`, `review_bash_guard`→`guard-reviewer-bash`, `common`→`lib-common`, `skills`→`repo-skills`, `github`→`repo-github`, `cloud_neutral`→`repo-cloud-neutral`. 참조 네 곳(`AGENTS.md:50`, `README.md:57`, `docs/ARCHITECTURE.md:53`, `.agents/skills/skill-authoring/SKILL.md:8`)의 `tests/skills.bats`를 `tests/repo-skills.bats`로 바꿨다. 이 밖에 고친 참조는 없다. Step 2 grep(기록 문서 제외)은 처음에 이 네 곳만 찾았고, 고친 뒤 출력이 없다. 이름 목록(`tests-t2.tsv`, 220줄)은 `tests-t1.tsv` 및 `tests-base.tsv`와 diff가 없다. `make check`: exit 0, ok 220, not ok 0, 총 줄 커버리지 94.50%(최소 80%). |
| 2026-10-21 | Verified | Task 3: 여러 스크립트를 묶었던 `vm_ops`, `backup_restore`, `bootstrap`, `access`(.bats)를 짝 파일 열 개로 나눴다(`deploy-stack` 6, `verify-vm` 16, `show-status` 4, `show-logs` 2, `backup-notes` 7, `restore-notes` 19, `bootstrap-vm` 5, `remote-provision-vm` 12, `check-access` 4, `open-tunnel` 2). `use_ssh_mode`와 `use_provision_env`는 `tests/helpers.bash`로 옮겼다. 이름 목록(`tests-t3.tsv`, 220줄)은 `tests-t2.tsv`와 diff가 없다(이름과 단언 수 같음). `make check`: exit 0, ok 220, not ok 0, 총 줄 커버리지 94.50%, 파일별 커버리지는 Task 2(`t2-check3.log`)와 차이가 없다. |
| 2026-10-21 | Verified | Task 4: `repo.bats`와 `main_checkout.bats`를 `repo-scripts`(3), `repo-make`(5), `repo-config`(17)로 나누고, `repo-docs`(+2)와 `backup-notes`(+3)로 옮겼다. 이름 목록(`tests-t4.tsv`, 219줄)은 `tests-t3.tsv`에서 "git-workflow cleanup checks the worktree's backups before git worktree remove" 한 줄만 빠졌고 나머지는 이름과 단언 수가 같다. Step 3 grep은 출력이 없다. `make check`: exit 0, ok 219, not ok 0, 총 줄 커버리지 94.50%, 파일별 커버리지는 Task 2(`t2-check3.log`)와 차이가 없다. 옮긴 backup 테스트 셋은 `unset BACKUP_DIR`와 `make_worktree_fixture`를 부르고, 나머지 스텁과 환경(ssh docker sudo, `use_vm_env`, `a.md`)은 `backup-notes.bats`의 setup이 만든다. |
| 2026-10-21 | Verified | Task 5 위치 다시 세기(`89df5f4`, grep): "스텁이 불리지 않음/불림" `run grep … "$STUB_LOG"` 98곳 중 `refute_stub_called` 45곳(assert_failure 32곳 + 개수 0 13곳; backup-notes 3, bootstrap-vm 4, check-access 1, deploy-stack 2, lib-vm 2, open-tunnel 1, post-review-record 3, post-review 2, remote-provision-vm 6, repo-make 1, restore-notes 6, review-branch 1, show-logs 1, sync-sb-space 1, upload-sb-fonts 1, verify-sb 4, verify-vm 6)와 `assert_stub_called` 39곳(backup-notes 4, bootstrap-vm 2, check-access 1, deploy-stack 2, lib-vm 1, open-tunnel 1, post-review-record 3, remote-provision-vm 11, restore-notes 3, review-branch 4, show-logs 1, upload-sb-fonts 1, verify-sb 1, verify-vm 4)을 바꿨다. 남긴 곳 14곳: 개수가 0이 아닌 `grep -c`(deploy-stack 39·48·63, lib-sb 50, post-review 18, repo-make 70, review-branch 57·59·67, verify-mcp 18·45, verify-vm 35·52), `grep -E '^docker compose (stop\|start)'` 뒤 `assert_line --index 0`(backup-notes 43). 다른 로그(`$STUB_LOG.requests`, `.body`)를 보는 곳과 `total="$(grep -c …)"` 변수 대입(sync-sb-space 75·76)도 그대로다. `run diff` 15곳(deploy-stack 3, restore-notes 4, sync-sb-space 8)은 모두 `assert_same_file`로 바꿨다. 임시 git 저장소는 check-git·review-branch 2곳을 `init_git_repo`로 바꾸고, create-doc은 커밋 전에 파일을 복사하므로 남겼다. 가짜 명령 5곳(`fail_command`, `fix_backup_stamp`, `datebin` 복사본, 부분 쓰기 `cp`, `mktemp`)은 `fake_cmd`로 바꿨다. 로그 순서 4곳 중 remote-provision-vm 1곳만 `assert_log_order`로 바꿨다. deploy-stack 2곳(정규식 앵커와 마지막 줄 비교)은 고정 문자열 첫 줄 비교로 바꾸면 ssh 줄에 먼저 걸려 실패해 awk를 되돌렸고, restore-notes 111(여러 조건)은 그대로다. |
| 2026-10-21 | Verified | Task 5 이름 목록: `diff tests-t4.tsv tests-t5.tsv` 219줄, 이름은 모두 같고 한 줄만 다르다: "installs tailscale with the official script and sets up swap before it installs docker from the official apt repo" 단언 수 7→8(`((swap_line < apt_line))`가 단언으로 세어지지 않다가 `assert_log_order` 한 줄이 된 것). 픽스처는 `verify-mcp/{json,sse}`, `remote-provision-vm/os-release`로 `git mv`했다. `make check`: exit 0, ok 219, not ok 0, 총 줄 커버리지 94.50%. 파일별 커버리지(`coverage-t5.txt`)는 Task 2(`t2-check3.log`)와 같다(show-status 출력의 시각 줄만 다름). |
| 2026-10-21 | Verified | Task 5 도우미 실패 경로(`tests/zz-helper-probe.bats`, 커밋하지 않음, 지움): 없는 줄 `assert_stub_called`, 있는 줄 `refute_stub_called -F 'ssh '`, 뒤바뀐 `assert_log_order`, 없는 TEXT `assert_log_order`, 다른 파일 `assert_same_file`, grep 오류(`-E '('`, exit 2) `assert_stub_called`/`refute_stub_called` 일곱 개가 모두 not ok이고 도우미 메시지가 나왔다. `setup_stubs ssh` 뒤 `fake_cmd ssh 'exit 0'`은 ok였고 `git status --short tests/stubs` 출력이 없다. 좋은 입력 통과 확인도 ok. |
| 2026-10-21 | Verified | Task 5 리뷰 지적 SDD-T5-F1: `assert_stub_called`, `refute_stub_called`, `assert_log_order`, `assert_same_file`의 `fail` 뒤에 `return 1`을 더했다. 이전에는 errexit가 꺼진 곳(`if`, 하위 셸, `run`)에서 `assert_log_order`가 0을 돌려주거나 "grep failed" 메시지가 하나 더 나왔다. 임시 probe(커밋하지 않음, 지움)로 errexit를 끈 호출 여섯 경우가 모두 0이 아닌 값을 돌려주고 자기 메시지만 내며 좋은 입력은 0임을 확인했다. `make check`: exit 0, ok 219, not ok 0, 총 줄 커버리지 94.50%. |
| 2026-10-21 | Verified | Task 6 합치기(커밋 `6227b49`), 묶음 → 지운 이름 수 → 결과 테스트(파일): A1 0 → "vm_env prints the loopback ports, the absolute data paths and SB_USER"(`lib-vm`); deploy 테스트는 VM `.env`를 `vm_env` 출력과 `assert_same_file`로 비교하고 600만 본다(restore 쪽은 Task 7 B5). A2 1 → "require_vm stops on an unknown BM_ACCESS in any case, …"(`lib-vm`). A3 2 → "deploy, verify and logs stop on an unknown BM_ACCESS before they run ssh, curl or nc"(`lib-vm`); "deploy requires the VM settings from .env"는 A2(`BM_VM_HOST` 비움)와 A3(deploy 경우)가 나눠 가졌다. A4 1 + 이름 변경 1 → "require_free_port refuses a privileged port and a port in use, so both tunnels stop before ssh"(`lib-vm`), `open-tunnel`에는 "tunnel refuses the tailscale mode before it runs ssh". A5 3(`main_checkout:46` 포함) → "require_sb_user rejects an SB_USER …"(`lib-sb`). A6 1 → "deploy and verify-sb stop before they contact the VM or SilverBullet …"(`lib-sb`). A7 0(deploy 두 테스트를 줄임). A8 이름 변경 1 → "deploy writes nothing into the notes folder when the image pull fails". A9 1 → 기존 반복문에 Funnel(443)을 더함. A10 2, A11 3, A12 2(`verify-vm`). A13 1(`verify-sb`). A14 2(`show-status`). A15 3(`check-access`). A16 3, A19 2(`bootstrap-vm`). A17 2, A18 2, A20 2 + 2(`remote-provision-vm`). A21 5, A22 4, A23 3(`verify-mcp`). A24 0(`upload-sb-fonts` 단언 하나). A25 1(`lib-sb`). A26 0(형식 단언 `tske****`, `test****`를 A16, A21에서 뺐다). 정리: `remote-provision-vm` setup에 docker 스텁을 두고 "installs tailscale …"가 `rm "$STUB_BIN/docker"`로 지운다. `stubs/free`의 available은 3000 고정이다. |
| 2026-10-21 | Verified | Task 6 지우기: "deploy reports an unhealthy container", "status points to free -m on the VM when it cannot read the memory use"(P4), "rejects --host-header followed by another option". |
| 2026-10-21 | Verified | Task 6 반복문 경우 확인(커밋하지 않음, 되돌림): 합친 반복문 20개(테스트 19개, A5는 반복문 둘)에서 경우 하나씩의 입력을 바꿔 `make test`. 1차(19곳): not ok는 바꾼 테스트 19개뿐이고 ok 171, 메시지마다 바꾼 경우가 나왔다(예: "require_vm did not stop as expected for: BM_VM_HOST=agent-hub\|\|missing env BM_VM_HOST"). 2차(A5의 env 파일 쌍): not ok는 그 테스트 하나. 성공만 보는 반복문(A20 앞쪽, A21)은 그 경우의 입력을 나쁜 값으로 바꿨다. |
| 2026-10-21 | Verified | Task 6 이름 목록(`tests-t6.tsv`, 187줄): `tests-t5.tsv`(219줄)에서 이름 54개가 빠지고 22개가 생겼다(합치기 커밋 뒤 190, 지우기 커밋에서 셋 더 빠짐). 새 이름 22개는 표의 결과 이름과 같다. 이름은 같고 단언 수만 바뀐 테스트는 넷이다: "deploy uploads compose.yaml, …" 14→9(A1, A7), "deploy recreates Basic Memory …" 6→4(A7), "converts Regular and Bold to WOFF2 …" 4→3(A24), "verify fails unless Serve sends 443 …" 1→2(A9). |
| 2026-10-21 | Verified | Task 6 `make check`: exit 0, ok 187, not ok 0, 총 줄 커버리지 94.42%(Task 5 94.50%). `coverage-t5.txt`보다 떨어진 파일은 `scripts/remote/provision-vm.sh` 하나다(96.19% → 95.24%, 합치기 커밋). 커버리지에서 빠진 줄은 184행 `log "access mode ssh: skipping Tailscale"`이다. A19로 ssh 모드 테스트가 `bootstrap-vm.bats`로 옮겨 갔는데, 그 테스트는 이 스크립트를 `/tmp/bm-bootstrap.XXXXXX` 복사본으로 돌리고 kcov(`--include-path=/repo/scripts`)는 복사본을 세지 않는다. 동작은 그 테스트가 여전히 본다(그 줄의 출력, `tailscale` 호출 없음). 지운 세 테스트는 파일별 비율을 바꾸지 않았다. kcov 보고서(`cobertura.xml`)에서 `deploy-stack.sh`와 `show-status.sh`의 빠진 줄은 0이다. 다만 그 테스트들이 지나가던 분기(`deploy-stack.sh:17-18` 재생성 실패, `show-status.sh:43-44` 메모리 읽기 실패, `verify-mcp.sh:36` 옵션 뒤 옵션)는 이제 어떤 테스트도 지나가지 않는다. |
| 2026-10-21 | Verified | Task 6 리뷰 지적 SDD-T6-F1, SDD-T6-F2. Step 4의 예외로, 이름이 하지 않는 검사를 말하던 다섯 테스트의 이름을 바꿨다(ADR 0004 결정 3, 단언 수는 그대로). "deploy uploads compose.yaml, an owner-only VM .env with SB_USER and the space files, …" → "… and the SilverBullet library page, …". "deploy recreates Basic Memory before starting SilverBullet only when the notes .gitignore changed, …" → "… when the notes .gitignore changed, …". "converts Regular and Bold to WOFF2 and writes them into the VM notes folder as the container user" → "… into the VM notes folder". "creates, formats and enables a swap file once and keeps other fstab entries, even when run twice" → "creates, formats and enables a swap file and keeps other fstab entries with one swap line, even when run twice". "passes a full round trip …, masks the session id and …" → "…, never prints the full session id and …". `repo-make`에는 "make local-up stops before any compose call on an SB_USER that require_sb_user rejects, without printing it"를 남겼다(`#` 경우 하나, 실패, `Tr4mp` 비출력, docker 호출 없음). "deploy writes nothing into the notes folder when the image pull fails"는 이제 notes 폴더 자체가 없음을 본다(`deploy-stack.sh`는 pull 전에 그 폴더에 닿지 않는다). 확인(커밋하지 않음, 되돌림): 실행 전에 notes 폴더를 만들거나 `Makefile:59`의 `require_sb_user` 줄을 지운 채 `make test`를 돌리면 not ok는 각각 그 테스트 하나다(ok 186). 이름 목록 `tests-t6b.tsv`(188줄)는 `tests-t6.tsv`와 비교해 이름 다섯이 바뀌고 하나가 더해진 것뿐이다. `make check`: exit 0, ok 188, not ok 0, 총 줄 커버리지 94.42%. |
| 2026-10-21 | Verified | Task 7 합치기(커밋 `c1081c2`), 묶음 → 지운 이름 → 결과 테스트(파일). B1 4("backup leaves no partial archive and still restarts the container when streaming fails", "backup publishes no file of its run when the checksum cannot be written, …", "backup still restarts the container when the stop cannot be confirmed", "backup fails and writes nothing when listing the data files fails") → "backup restarts the container, keeps no file of its run and spares earlier backups when the stop, the listing, the stream or the checksum fails"(`backup-notes`): 네 경우 모두 날짜를 고정하고 이전 백업 세 파일을 둔 뒤 실패, 그 단계의 문구, `docker compose start`, 백업 폴더에 이전 세 파일만 있고 내용이 그대로임을 본다. B2 2 → "backup refuses a name that another backup or another run holds, …"(`backup-notes`): 두 경우 모두 실패, 문구(`already exists`, `another backup`), `compose stop` 없음, 이름을 가진 파일만 남고 내용이 그대로임(첫 경우에서는 이 실행이 자기 `.partial`을 지웠다는 뜻)을 본다. B3 6 → "restore refuses before any ssh when …"(`restore-notes`): 아홉 경우 모두 실패, 멈춘 검사의 문구, ssh 0회, `a.md` 그대로를 보고, `../`와 절대 경로 경우는 tar 목록에 그 항목이 있는지도 본다. B4 7 → "restore rolls the previous data, compose.yaml and .env back when …"(`restore-notes`): 여섯 경우 모두 그 단계의 문구, "restore failed; rolling back", "rolled back: the previous data is live again", 이전 `a.md`·`compose.yaml`·`.env`, data root 옆에 `.prev-*`·`.restore-*` 없음, app 폴더에 `.env`와 `compose.yaml`만 있음을 본다. 시작 실패만 `.failed-*`의 복원 데이터와 `--force-recreate` 호출을, 나머지 다섯은 일반 `up -d --wait` 없음을 본다. B5 3 → "restore replaces the data, writes the space files while stopped and the VM .env, …"(`restore-notes`): 두 경우 모두 복원 데이터와 소유자 1000, tar 옵션, 시작 호출, 저장소의 `compose.yaml`, `vm_env`와 같은 `.env`와 600, app 폴더에 두 파일만, 공간 파일과 남은 `index.md`, 표식 없음, 첫 시작 전의 쓰기, `.restore-*` 없음을 본다. 기존 VM만 중지 뒤의 쓰기와 `.prev-*`의 `a.md`를, 재생성된 VM만 `.prev-*` 없음을 본다. B6 2 → "a backup made by backup-notes.sh skips the model cache and restores with restore-notes.sh to match its manifest"(`restore-notes`). B7 2 → "backup saves into the main checkout's backups/, from a linked worktree and from GIT_DIR"(`backup-notes`): 두 경우 모두 `.tgz.manifest`와 `.tgz.sha256`을 본다. 약한 묶음 "restore on a VM without previous data …"와 "backup fails with an actionable message when the main checkout cannot be found"는 그대로 두었다. |
| 2026-10-21 | Verified | Task 7 합치기에서 표에 적히지 않은 선택. (1) B4 시작 경우의 입력은 `:378`의 `DOCKER_STUB_FAIL_MATCH="up -d --wait"`(롤백의 시작은 성공)다. 표가 모든 경우에 "rolled back"을 보라고 해서다. 이 커밋에서는 `:359`의 입력(`up -d`, 롤백의 시작도 실패)이 빠져 `scripts/restore-notes.sh:78`이 실행되지 않았고, 다음 커밋에서 일곱째 경우로 되돌렸다(아래 판정 행). `:378`의 "바뀌지 않은 compose" 픽스처도 빠졌다. 스크립트는 compose를 비교하지 않고 언제나 `--force-recreate`를 넘기므로 같은 경로이고, 그 테스트의 `compose.yaml` 단언은 롤백 여부와 상관없이 참이었다. (2) B5 기존 VM에는 이전 `compose.yaml`을 둔다. `:190`에는 없어서 중지가 일어나지 않았다. 이제 중지 뒤의 쓰기와 성공 뒤 `compose.yaml.prev-*` 없음을 실제로 본다. (3) "임시 파일 없음"은 `ls -A` 목록과 `refute_line --regexp`로 본다. 옛 `ls -d <glob> <glob>` + `assert_failure`는 두 glob 가운데 하나만 있어도 통과했다. (4) B3의 SB_USER 경우는 `missing env SB_USER`를 본다. 옛 테스트는 문구를 보지 않았고, 표는 아홉 경우 모두 가리는 문구를 보라고 한다. (5) 경우마다 기대가 다른 반복문에는 기대를 적은 필드를 두었다(B4 `started`, B5 `stopped`·`kept`). |
| 2026-10-21 | Verified | Task 7 지우기: "backup stores a checksummed archive of the data root and restarts the container"에서 매니페스트 형식 단언 하나(`a.md`의 sha256 줄)를 지웠다(단언 수 8 → 7). 형식은 `lib-vm`의 "manifest_cmd lists every file's sha256 sorted by path"가 보고, 백업 매니페스트가 data root의 것인지는 B6이 복원 뒤 `local_manifest`와 같은지로 본다. 세 파일, `.partial` 없음, `.sha256` 내용은 그대로 본다. |
| 2026-10-21 | Verified | Task 7 반복문 경우 확인(커밋하지 않음, 되돌림): 합친 반복문 여섯 개에서 경우 하나씩의 입력을 바꿔 한 번에 `make test`를 돌렸다(ok 163, not ok 6). not ok는 바꾼 테스트 여섯 개뿐이고, 메시지마다 바꾼 경우가 나왔다. B1 stream 경우의 fail match를 비움 → "backup after a failed stream". B2 다른 실행이 다른 시각의 이름을 가짐 → "backup went on although bm-20261009T000000Z.tgz.partial held its name". B7 `GIT_DIR`이 없는 저장소를 가리킴 → "backup from GIT_DIR". B3 올바른 checksum → "restore did not refuse before ssh with: wrong checksum". B4 맞는 매니페스트 → "restore after a failed manifest". B5는 성공만 보는 반복문이라 나쁜 입력으로 바꿨다(재생성된 VM에 데이터를 둠) → "restore on the recreated VM". |
| 2026-10-21 | Verified | Task 7 이름 목록(`tests-t7.tsv`, 169줄): `tests-t6b.tsv`(188줄)에서 이름 26개가 빠지고 7개가 생겼다(B1 4, B2 2, B3 6, B4 7, B5 3, B6 2, B7 2 → 결과 7). 새 이름 일곱은 표의 결과 이름과 같다. 이름은 같고 단언 수만 바뀐 테스트는 "backup stores a checksummed archive …" 8 → 7(지우기)뿐이다. `make check`(두 커밋 모두): exit 0, ok 169, not ok 0, 총 줄 커버리지 94.34%(Task 6 94.42%). `coverage-t5.txt`보다 떨어진 파일은 `scripts/restore-notes.sh`(97.70% → 96.55%, 합치기 커밋, 78행)와 Task 6의 `scripts/remote/provision-vm.sh`다. `scripts/backup-notes.sh` 95.00%, `scripts/lib/vm.sh` 93.22%, `scripts/lib/sb.sh` 93.18%는 그대로다. |
| 2026-10-21 | Verified | Task 7 판정(리뷰 전): 합치기 규칙 "묶음의 서로 다른 입력을 모두 결과 테스트로 옮긴다"가 표의 "모든 경우에 rolled back을 본다"보다 앞선다. 그래서 B4에 일곱째 경우 "start and rollback start"(`DOCKER_STUB_FAIL_MATCH="up -d"`, 롤백의 시작도 실패)를 더했다. `:359`가 본 것(실패, 시작 실패 문구, "restore failed; rolling back", 이전 `a.md`·`compose.yaml`·`.env`, `.failed-*`의 복원 데이터)과 다른 경우의 공통 검사(임시 파일 없음, `--force-recreate` 호출)를 본다. 이때 스크립트는 "rolled back: the previous data is live again"을 내지 않는다(`scripts/restore-notes.sh:75-79`). 그래서 새 필드 `back`이 `down`이면 그 문구가 없음을 본다(`:397`과 같은 refute). 이 검사가 없으면 아래 확인에서 이 경우가 실패할 수 없다. 이름은 그대로다(시작 실패의 한 경우). Follow-ups의 `restore-notes.sh:78` 줄은 지웠다. 확인(커밋하지 않음, 되돌림): 이 경우에 `:378`의 입력(`up -d --wait`)을 주자 not ok는 B4 테스트 하나였고(ok 168), 메시지는 "restore after a failed start and rollback start"였다. 이름 목록 `tests-t7b.tsv`(169줄)는 `tests-t7.tsv`와 비교해 B4의 단언 수만 10 → 11로 다르다. `make check`: exit 0, ok 169, not ok 0, 총 줄 커버리지 94.42%, `scripts/restore-notes.sh` 97.70%(78행이 다시 실행됨). `coverage-t5.txt`보다 떨어진 파일은 Task 6의 `scripts/remote/provision-vm.sh`뿐이다. |
| 2026-10-21 | Verified | Task 7 리뷰 지적 SDD-T7-F1. Step 4의 예외로 B3 결과 테스트의 이름을 바꿨다(ADR 0004 결정 3, 단언 수는 그대로). "restore refuses before any ssh when the answer is not yes, SB_USER is invalid, …" → "… SB_USER is missing, …". 그 반복문의 SB_USER 경우는 SB_USER를 비운 것 하나뿐이고 `require_sb_user` 안의 `require_env`에서 멈춘다. 형식 검사(`scripts/lib/sb.sh:38-39`)는 `restore-notes.sh`로 실행되지 않는다(`lib-sb`의 소비자 반복문은 `deploy-stack.sh`와 `verify-sb.sh`만 돈다). 옛 `:265`부터 있던 빈틈이라 Follow-ups에 적었다. 이름 목록 `tests-t7c.tsv`(169줄)는 `tests-t7b.tsv`와 비교해 이 이름 하나만 바뀌었다. `make check`: exit 0, ok 169, not ok 0, 총 줄 커버리지 94.42%. |
| 2026-10-21 | Verified | Task 8 합치기(커밋 `9097bb7`), 묶음 → 지운 이름 → 결과 테스트(파일). C1 3("accepts work branches with Plan none and Task review", "ignores merge commits brought into the branch", "checks an explicit branch from a detached HEAD") → "passes plan and work branches whose commits carry every trailer, …"(`check-git`): 세 경우 모두 성공과 "OK: git policy (1 commits since main)"을 본다(옛 work 브랜치 테스트는 성공만 봤다). C2 4("fails on main because agents never commit to main", "fails in detached HEAD", "fails on a branch name outside plan/ and work/", "applies the branch-name rule to an explicit branch") → "fails on main, a detached HEAD and a branch outside plan/ and work/, also as an explicit branch"(`check-git`): 네 경우 모두 실패와 그 브랜치 문제의 문구를 본다. C3 2("fails clearly when the base branch does not exist", "fails clearly when the explicit branch does not exist") → "fails instead of passing when the base or the explicit branch does not exist"(`check-git`). C4 3("lists every missing trailer with the commit", "rejects malformed trailer values", "rejects Co-authored-by and Signed-off-by") → "lists every missing, malformed and forbidden trailer with its commit"(`check-git`): 문제마다 커밋 제목 뒤의 문구를 본다(옛 테스트는 첫 문구에서만 제목을 봤다). C4 3("fails when the trailers are missing or not in the last paragraph", "rejects malformed trailer values, including a second Plan line", "rejects Co-authored-by, Signed-off-by and Claude Code session links in the body because the squash commit would carry them") → "fails on missing, misplaced, malformed, repeated and forbidden trailers and session links in the body"(`check-pr`): 일곱 경우 모두 exit 1과 문제마다의 문구를 본다. C5 2("rejects titles that are not '<type>: <description>'", "fails instead of passing when CI does not pass the title") → "rejects an empty title and titles that are not '<type>: <description>'"(`check-pr`). C6 3("codex reviews a claude-authored branch in a detached worktree and writes both reports", "both claude reviews run as the guarded branch-reviewer agent in plan mode", "claude reviews run without user or system git config, so no external diff or textconv helper loads") → "codex and claude review another vendor's branch in a detached worktree and write both reports; …"(`review-branch`): 두 리뷰어 모두 성공, 두 보고서의 내용, 리뷰 worktree 안의 호출 2회, worktree 정리, 출력 폴더의 세 파일, meta의 base·head를 본다. codex만 두 명령 줄을, claude만 호출 2회, branch-reviewer plan 모드 2회, git 설정 없음 2회를 본다. C7 2("refuses a reviewer from the same vendor as the author", "tells the reviewer only when the human allowed a same-vendor review") → "refuses a same-vendor reviewer unless the human allowed it, and tells only that reviewer"(`review-branch`, 거부·허락받은 같은 벤더·다른 벤더의 세 경우). C8 2("removes the worktree and this round's earlier reports even when the reviewer fails", "a failed plan review leaves no half pair of reports") → "leaves no worktree and no report of the round when the change review or the plan review fails"(`review-branch`): 두 경우 모두 실패한 리뷰의 문구, worktree 하나, diff·plan 보고서 없음을 본다(옛 plan 리뷰 테스트는 worktree를 보지 않았다). C9 4("refuses to reuse a stale review worktree and leaves it alone", "refuses a leftover review-base branch and never deletes it", "rejects a relative REVIEW_OUT_DIR", "rejects an unknown reviewer") → "refuses a stale review worktree, a leftover review-base branch, a relative REVIEW_OUT_DIR and an unknown reviewer, and leaves what exists alone"(`review-branch`): 네 경우 모두 실패, 리뷰어 CLI(codex·claude 스텁) 호출 없음, worktree 하나를 보고, 앞 세 경우는 문구와 남은 폴더·남은 브랜치·`out` 없음을 본다. 알 수 없는 리뷰어의 usage 문구 단언은 표대로 "리뷰어 CLI를 부르지 않음"으로 바꿨다. C10 2("posts nothing when a file of the round is missing", "posts nothing when either report is too long for one GitHub comment") → "posts nothing when a file of the round is missing or too long"(`post-review`), 2("refuses to guess when the PR has several Review records", "stops instead of creating a second record when gh reports no login") → "writes nothing when the PR has several records or gh reports no login"(`post-review-record`). C11 2("creates the Review record when the PR has none, with the marker as its first line", "updates the existing Review record instead of adding a second one") → "creates the Review record when the PR has none and updates the one it has"(`post-review-record`): 두 경우 모두 machine 계정 필터, 쓰는 호출, 다른 메서드 없음, 본문 첫 줄의 표식과 findings 줄을 본다(옛 고치기 테스트는 본문을 보지 않았다). C12 5("blocks shell operators in an allowed git command", "blocks git options that write files, including abbreviations", "blocks git options that run external diff or textconv helpers, including abbreviations", "blocks anything but single-space-separated plain tokens", "blocks every other git subcommand and every non-git command") → "blocks shell operators, file-writing and helper options with their abbreviations, anything but plain single-spaced tokens and every other command"(`guard-reviewer-bash`, 명령 52개 각각 exit 2와 guard 문구), 2("fails closed on empty, invalid or incomplete hook input", "fails closed when jq is missing") → "fails closed on bad hook input and without jq"(여섯 경우 모두 exit 2, jq 경우만 "missing command 'jq'"). C13 2("doc_types fails when the header row's columns are reordered or the separator row is missing", "doc_types fails and names the row when a row lost a cell or has an empty one") → "doc_types fails on a reordered header, a missing separator, a short row and an empty cell"(`lib-docs`). C14 2("refuses a type whose 새 문서 cell is 금지 even when its template exists", "refuses an unknown type, a slug that is not lowercase-hyphen and an existing file, and writes nothing") → "refuses an unknown type, a retired type whose template still exists, a slug that is not lowercase-hyphen and an existing file, and writes nothing"(`create-doc`). 합치지 않는 묶음(리뷰 2회차 성공, `lib-git`의 두 테스트, `lib-docs`의 읽기 테스트와 create-doc 성공)은 그대로 두었다. |
| 2026-10-21 | Verified | Task 8 합치기에서 표에 적히지 않은 선택. (1) Step 4의 예외: C14는 표에 결과 이름이 없어 `:95`의 이름에 은퇴한 타입을 넣었다(ADR 0004 결정 3). 그 이름의 "template still exists"를 실제로 보도록, 레지스트리 사본이 가리키는 research 템플릿이 있는지 확인하는 줄을 더했다. 옛 `:85`는 이 전제를 보지 않았다. 확인(커밋하지 않음, 되돌림): 그 줄의 타입을 없는 이름으로 바꾸자 not ok는 그 테스트 하나였고(ok 140), 메시지는 "the copy has no research template"였다. (2) C14의 은퇴한 타입 경우만 "no longer created"를 본다. awk가 깨뜨린 레지스트리에서도 실패하기 때문이다. 나머지 네 경우는 옛 테스트처럼 실패만 본다. 바꾼 레지스트리 사본은 커밋해 두어, `git status` 단언이 옛 것 그대로 create-doc이 쓴 파일만 본다. (3) C13의 문구 단언을 멈춘 검사의 문구로 좁혔다. 옛 "header", "row 1" → "the header row must name the columns", "the separator row", "row 1 has 9 cells", "row 1 has an empty cell". 새 문구는 옛 문구를 포함한다. (4) C5의 빈 제목은 `PR_TITLE=""`로 준다. 옛 테스트는 PR_TITLE을 두지 않았지만 스크립트는 `${PR_TITLE:-}`로 읽어 같은 줄(`scripts/check-pr.sh:45`)에서 멈춘다. `check-pr`의 C4·C5는 모든 경우에 exit 1을 본다. (5) git을 쓰는 반복문(C1~C4, C6~C9)은 경우마다 하위 셸에서 새 저장소를 만든다. `check-git`은 `init_git_repo`를, `review-branch`는 새 파일 도우미 `review_repo`(출력·worktree 폴더와 스텁 기록도 지움)를 쓴다. 그래서 테스트는 먼저 setup의 저장소에서 나간다. `post-review`는 새 파일 도우미 `write_reports`로 경우마다 보고서 세 파일을 다시 쓴다. C12는 경우마다 자기 hook 입력을 준다. (6) 경우마다 기대가 다른 반복문에는 기대를 적은 필드를 두었다(C7 `outcome`, C9 문구, C11 쓰는 호출과 쓰지 않을 메서드). |
| 2026-10-21 | Verified | Task 8 지우기. "passes on a plan branch whose commits carry every trailer"(`check-git`)를 지웠다. 그 단언(plan 브랜치, 기본 인자, 성공, "OK: git policy (1 commits since main)")은 C1의 "plan branch with a merge from main" 경우가 모두 본다. `tests/stubs/claude`의 `CLAUDE_STUB_EXIT`와 `tests/stubs/gh`의 `GH_STUB_EXIT`를 머리 주석과 함께 지웠다. 지우기 전 `git grep -n -E 'CLAUDE_STUB_EXIT\|GH_STUB_EXIT'`는 두 스텁과 기록 문서(완료 계획 02·09, 스펙, 이 계획)만 찾았다. 기록 문서는 고치지 않는다. |
| 2026-10-21 | Verified | Task 8 반복문 경우 확인(커밋하지 않음, 되돌림): 합친 반복문 17개에서 경우 하나씩의 입력을 바꿔 한 번에 `make test`를 돌렸다(ok 124, not ok 17). not ok는 바꾼 테스트 17개뿐이고, 메시지마다 바꾼 경우가 나왔다. 성공만 보는 반복문(C1, C6, C11)은 나쁜 값으로 바꿨다. C1 work 브랜치에 `Task: first` → "check-git did not pass the work branch with Plan none and Task review". C2 `feature/x` 대신 `work/x` → "check-git did not refuse to run on: feature/x". C3 base `main` → "check-git did not fail on a missing base". C4(`check-git`) 올바른 트레일러 → "check-git did not list the malformed trailers". C4(`check-pr`) 두 번째 Plan 줄 없음 → "check-pr did not list every problem of the body: a second Plan line". C5 "feat: add rules" → "check-pr did not reject the title 'feat: add rules'". C6 claude 경우의 작성자 claude-code → "claude review of a branch by claude-code". C7 거부 경우의 리뷰어 codex → "codex review with REVIEW_ALLOW_SAME_VENDOR='' was not refused". C8 plan 경우에 실패시키는 변수 없음 → "the failed codex plan review left a worktree or a report". C9 남은 worktree 폴더 없음 → "review-branch did not refuse the stale review worktree or did not leave it alone". C10(`post-review`) 100바이트 보고서 → "post-review did not stop before gh with a plan report that is too long". C10(`post-review-record`) login 있음 → "post-review-record wrote although gh reported no login". C11 기록이 없는 경우에 id 99 → "post-review-record when the PR has none Review record". C12 `--ext` 대신 `--text` → "expected exit 2 (blocked) for: git diff --text main...HEAD". C12 "not json" 대신 올바른 hook 입력 → "the guard did not fail closed with exit 2 on: not JSON". C13 짧은 줄에 칸을 채움 → "doc_types did not fail on a short row". C14 research 대신 spec → "create-doc.sh did not refuse: spec late-note". |
| 2026-10-21 | Verified | Task 8 이름 목록: `tests-t8-merge.tsv`(141줄, 커밋 `9097bb7`)는 `tests-t7c.tsv`(169줄)에서 이름 45개가 빠지고 17개가 생겼다(C1 3, C2 4, C3 2, C4 3·3, C5 2, C6 3, C7 2, C8 2, C9 4, C10 2·2, C11 2, C12 5·2, C13 2, C14 2 → 결과 17). 새 이름 16개는 표의 결과 이름과 같고, C14의 이름은 위 선택 (1)이다. `tests-t8.tsv`(140줄)는 `tests-t8-merge.tsv`에서 "passes on a plan branch whose commits carry every trailer" 하나만 빠졌다. `make check`(두 커밋 모두): exit 0, not ok 0, ok 141(합치기)과 140(지우기), 총 줄 커버리지 94.42%(Task 7과 같다). 이 Task가 다룬 아홉 파일(`scripts/check-git.sh` 100%, `check-pr.sh` 96.88%, `review-branch.sh` 95.10%, `post-review.sh` 92.31%, `post-review-record.sh` 92.00%, `guard-reviewer-bash.sh` 100%, `create-doc.sh` 100%, `lib/git.sh` 100%, `lib/docs.sh` 56.67%)은 `coverage-t5.txt`와 같고, kcov의 실행되지 않은 줄 목록도 Task 7 끝(`c5e2a1d`)과 같다. 이 Task로 kcov가 세는 테스트를 잃은 분기는 없다. |
| 2026-10-21 | Verified | Task 8 판정(리뷰 전), 표와 다른 점: C9의 알 수 없는 리뷰어 경우는 멈춘 검사의 문구를 그대로 본다. 위 합치기 행의 C9 설명은 이 판정으로 바뀐다. 표대로 usage 문구 단언을 "리뷰어 CLI를 부르지 않음"으로만 바꾸면, 허용 목록 검사(`scripts/review-branch.sh:169`의 `reviewer_tool`, 그 `*) usage`는 `:59`)가 없어져도 이 경우는 `:170`의 `require_cmd git "$REVIEWER"`가 없는 gemini 명령에서 멈춰 그대로 통과한다. 합치기 규칙은 어느 검사가 멈췄는지 가릴 때 문구 단언을 허락하고, 스펙 7.3절은 리뷰어 허용 목록 테스트를 보호 대상으로 남긴다. 그래서 이 경우는 usage 문구에서 허용 리뷰어를 적은 부분 `REVIEWER=codex\|claude`를 보고, 리뷰어 CLI 호출 없음(`refute_stub_called -E '^(codex\|claude) '`)도 그대로 본다. 확인(커밋하지 않음, 되돌림): `:169`를 지운 채 `make test`를 돌리자 not ok는 이 테스트 하나였다(ok 139). 메시지는 "review-branch did not refuse the unknown reviewer or did not leave it alone", 출력은 "missing command 'gemini'"였다. 스크립트는 되돌렸다(`git diff --stat scripts/` 빈 출력). 이름 목록 `tests-t8b.tsv`(140줄)는 `tests-t8.tsv`와 비교해 이 테스트의 단언 줄 수만 7 → 6으로 다르다(문구 단언을 앞 줄의 검사에 이었다). `make check`: exit 0, ok 140, not ok 0, 총 줄 커버리지 94.42%. |
| 2026-10-21 | Verified | Task 8 리뷰 지적 SDD-T8-F1, SDD-T8-F2, SDD-T8-F3(고치기 1회차). F1: C7 "… tells only that reviewer"는 다른 벤더 리뷰어가 동의를 받은 경우를 돌리지 않았다. 넷째 경우 `codex\|1\|untold`(다른 벤더 리뷰어에 `REVIEW_ALLOW_SAME_VENDOR=1`, 프롬프트에 동의 문구 없음)를 더하고 `codex\|\|untold`는 남겼다. F2: `( … ) \|\| fail` 안에서는 errexit가 꺼져, 준비 명령이 실패해도 경우가 다른 이유로 통과할 수 있었다(예: C1 병합 경우에서 `git merge`가 실패해도 "1 commits"가 나온다). 준비 줄을 `&& … \|\| exit 1`로 이었다. `check-git`: C1 세 경우, C2의 detached HEAD·feature/x·명시 feature/x, C3의 `git switch -c work/x`, C4의 브랜치 만들기와 세 커밋. `review-branch`: `review_repo`의 앞 줄(지우기, 스텁 기록 비우기, `init_git_repo`, 브랜치), C8의 이전 보고서 쓰기와 `export`. `post-review`: `write_reports`의 네 줄과 C10의 준비. `post-review-record`: C11의 스텁 기록 비우기와 본문 지우기, C10의 스텁 기록 비우기와 `export`. `lib-docs`: C13의 레지스트리 쓰기. `check-pr`, `guard-reviewer-bash`, `create-doc`의 반복문은 하위 셸 안에 변수 대입과 `unset` 말고 준비 명령이 없다. F3: C5에 옛 입력인 PR_TITLE 없음(`<unset>`, 하위 셸에서 `unset PR_TITLE`)을 다시 넣고 빈 제목도 남겼다. 둘 다 "PR_TITLE is empty"를 본다. 스크립트는 둘을 같은 빈 제목으로 다루므로 이름은 그대로다. 확인(커밋하지 않음, 되돌림): `scripts/review-branch.sh`의 동의 분기(74-77행)를 73행 위로 옮기고 `<unset>` 경우에 올바른 제목을 준 채 `make test`를 돌리자 not ok는 두 테스트뿐이었다(ok 138). 메시지는 "codex review with REVIEW_ALLOW_SAME_VENDOR='1' was not untold"와 "check-pr did not reject the title '<unset>'"였다. 스크립트는 되돌렸다(`git diff --stat scripts/` 빈 출력). 이름 목록 `tests-t8c.tsv`(140줄)는 `tests-t8b.tsv`와 같다. 새 경우는 반복문 항목이고 이은 줄은 준비 줄이라 단언 줄 수가 바뀌지 않는다. `make check`: exit 0, ok 140, not ok 0, 총 줄 커버리지 94.42%. |
| 2026-10-21 | Verified | Task 9 공용 도우미(`tests/helpers.bash`): `front_value FILE KEY`(`repo-docs`의 `front_value`, `repo-skills`의 `field_of`와 그 인라인 사본), `outside_code`와 `markdown_files`(`repo-docs`의 같은 awk와 같은 `git ls-files` 줄), `refute_matches DIR ERE [GREP_FLAG...]`(bash 3.2 금지 문법, Funnel, `AGENT_ID`, 참조 파일, 클라우드 이름 검사가 쓴다). 실패 경로 확인(`tests/zz-helper-probe.bats`, 커밋하지 않음, 지움): 찾은 줄, 하위 폴더에서 찾은 줄, grep 오류(`'('`, exit 2), 없는 DIR, `( … ) \|\| fail` 안에서 찾은 줄, 이 다섯 경우가 모두 not ok였다. 메시지는 도우미의 것(찾은 줄, 또는 "grep failed with exit 2")이다. errexit를 끈 하위 셸과 `if`에서는 찾은 줄과 grep 오류가 1을 돌려주며 자기 메시지 하나만 냈다. 찾지 못한 경우는 0과 빈 출력이었다. `front_value`(없는 키는 빈 값), `outside_code`, `markdown_files`의 좋은 입력도 ok였다. |
| 2026-10-21 | Verified | Task 9 합치기(커밋 `6bb03e9`), 묶음 → 지운 이름 → 결과 테스트(파일). D1 2("every Make target has a ## description and is declared .PHONY", "no Make target is defined twice") → 표의 이름(`repo-make`), 문제를 모아 한 번에 낸다. D2 1("compose pins the Basic Memory image by digest")과 `:118`의 SilverBullet digest → "every compose image is pinned by digest"(`repo-config`). `services:`의 서비스마다 `image:` 줄이 있고 모두 `<이름>:<버전>@sha256:<64자>`인지 본다. D3·D4 6("compose overrides the image's default SSE command …", "compose healthcheck probes port 8000 …", "compose healthcheck start_period covers …", "deploy and restore wait longer …", "compose restarts both services after reboots", "SilverBullet is pinned, …") → 표의 두 이름(`repo-config`). D3은 모든 검사를 `service_block basic-memory`로 좁혔다(옛 transport·path·healthcheck 검사는 파일 전체를 봤다). D4는 `:118`의 나머지와 `:110`·`:74`의 SilverBullet 몫이다. D5 2, D6 2, D7 3 → 표의 이름(`repo-config`). D7은 `git status` 없음 단언을 남겼다. D9 2("relative links in markdown files resolve", "every docs path named in scripts, skills, AGENTS.md or outside code in tracked Markdown exists") → 표의 이름(`repo-docs`). 수집기 `path_refs`가 `파일·종류·대상` 줄을 낸다. link는 파일 폴더 기준 `-e`로, docs는 저장소 기준 `-f`로 보고, 두 범위는 그대로다. D10 3 → 표의 이름. `doc_problems`가 문제를 모아 한 번에 내고, ARCHITECTURE는 옛 테스트처럼 front matter만 본다. D11: 파일의 `DATE_PATTERN` 대신 `scripts/lib/docs.sh`의 `DOC_DATE_PATTERN`(setup이 이미 source함)을 front matter와 이름 검사에 쓴다. D12 4 → 표의 이름(`repo-skills`). 한도는 표 하나(`MAX_FIELD_CHARS`: name 64, description 1024, compatibility 500)이고 description 비어 있음 단언은 남겼다. D13 4 → 표의 두 이름. D14 2 → 표의 이름. D15 3 → 표의 이름(`repo-cloud-neutral`). 스캔 자체의 확인이 첫 경우이고, 그다음 `scripts`와 `.agents/skills`를 돈다. 고아가 된 도우미 `field_of`, `markdown_links`, `compose_start_period_seconds`, `cloud_name_matches`와 상수 `DATE_PATTERN`, `MAX_NAME_CHARS`, `MAX_DESCRIPTION_CHARS`, `MAX_COMPATIBILITY_CHARS`는 지웠다. bash 3.2, Funnel, `AGENT_ID` 검사는 이름을 그대로 두고 `refute_matches`를 쓴다. |
| 2026-10-21 | Verified | Task 9 합치기에서 표에 적히지 않은 선택. (1) D15: 허용된 런북 경로가 `scripts/`와 스킬에 있어 `refute_matches`를 그대로 쓸 수 없다. `cloud_scan`은 DIR의 사본에서 그 경로를 sed로 지운 뒤 `refute_matches <사본> "$CLOUD_NAMES" -i -w`를 부른다. 판정은 옛 `cloud_name_matches`(경로를 지우고 다시 grep)와 같다. 출력은 사본 경로(`scan/scripts/…`)로 파일을 가리킨다. (2) D5: 이름이 ".env files"라서 추적 검사를 `.env`에서 `.env`와 `.env.*`(`.env.example` 제외)로 넓혔다. 무시 경우에 `.env`를 더하고, `check-ignore`에 `--no-index`를 더했다. `.env.example`은 추적 파일이어서 `--no-index` 없이는 `!.env.example`이 없어져도 exit 1이므로, 옛 단언은 실패할 수 없었다(아래 반복문 확인 1차에서 `--no-index`를 넣은 단언이 실패함). 경우마다 기대 exit(무시 0, 무시 안 함 1)를 본다. (3) D2: 옛 Basic Memory 정규식의 이미지 이름은 파일 전체에서 그 줄을 고르는 데만 쓰였다. 이제 서비스 블록으로 줄을 고르고, 이름은 보지 않는다. SilverBullet의 이미지 이름과 `-slim`은 D4가 본다. (4) D4: SilverBullet에 healthcheck test 줄이 있어야 한다(이름의 "probes"). 옛 `:74`는 파일 전체의 test 줄을 봤다. (5) 빈 목록에서 실패하는 줄: D2(서비스), D9(link와 docs 경로 각각 하나 이상), D10(docs/ 아래 파일), D12·D13·D14(스킬 목록), D13의 둘째 테스트(묶인 파일과 references 폴더 각각 하나 이상). (6) D13의 참조 검사는 `2>/dev/null \|\| true`가 grep 오류를 삼키던 것을 `refute_matches`로 바꿨다. (7) D5와 D6은 반복문 확인 1차에서 bats-assert의 일반 메시지만 냈다. 그래서 경우를 이름으로 대는 `fail` 문구로 바꿨다(2차·3차에서 확인). |
| 2026-10-21 | Verified | Task 9 지우기. "operational skills bm-upgrade, bm-recover and bm-diagnose exist"(`repo-skills`)를 지웠다(스펙 7.3절, ADR 0004 결정 2). 스킬 목록이 비면 이제 D12·D13·D14의 방어 줄이 실패한다. D8: "AGENTS.md defines the Code Review Rules that Codex reads"에서 `P0.*P1.*block the merge` 문장 단언을 지우고 제목 줄 단언만 남겼다(ADR 0007 결정 2, 단언 수 2 → 1). D16: gcloud 검사에서 `.agents/skills/*/SKILL.md` 범위를 뺐다. 스킬에 gcloud가 한 줄이라도 있으면 D15가 먼저 실패하므로, 이 범위는 혼자서는 실패할 수 없다. Step 4의 예외로, 이름이 하지 않는 검사를 말하지 않도록 이름을 바꿨다(ADR 0004 결정 3, 단언 수 3 그대로). "every gcloud command in runbooks and skills names the bm-personal configuration" → "every gcloud command in runbooks, README.md and docs/ARCHITECTURE.md names the bm-personal configuration". 확인(커밋하지 않음, 지움): `repo-skills.bats`의 사본 두 개가 `REPO_DIR`을 가짜 저장소로 바꿔 돌았다. 스킬이 없는 저장소에서는 D12, D13 둘, D14가 "found no skills under .agents/skills"로 not ok였다. 묶인 파일이 없는 올바른 스킬 하나만 있는 저장소에서는 D13의 둘째 테스트만 "checked 0 bundled files and 0 references folders"로 not ok였다. 약한 묶음인 "every SKILL.md is at most 500 lines"는 빈 목록에서도 통과한다(원래 있던 것, 이 Task의 표 밖). |
| 2026-10-21 | Verified | Task 9 반복문 경우 확인(커밋하지 않음, 되돌림). 1차: 합친 테스트 14개에서 경우 하나씩, 그리고 불변식 셋(보안 불변식인 포트 127.0.0.1과 Funnel, AGENTS.md 불변식인 bash 3.2)의 입력을 한 번에 바꿨다(digest 불변식은 D2의 경우, 리뷰어 에이전트는 D7의 경우). `make test`: ok 102, not ok 18, not ok는 바꾼 18개뿐이다. 메시지는 바꾼 경우를 가리켰다. D1 `new-doc` 두 번 정의 → "new-doc: defined more than once". D2 Basic Memory digest 지움 → "basic-memory: image: …:0.23.2". D3 Basic Memory가 silverbullet 네트워크도 씀 → "basic-memory must use only its own network". D4 SilverBullet healthcheck가 `--version` → "the silverbullet healthcheck must not use --version". D7 `tools:`에 Write → refute_line `^tools: .*(Write\|Edit)`. D9 README의 깨진 링크와 없는 docs 경로 → 두 줄. D10 ARCHITECTURE `status: draft`와 이름·front matter·빈칸이 틀린 새 계획 파일 → 네 줄. D12 compatibility 600자 → "bm-recover(compatibility has 600 characters, max 500)". D13 스킬 폴더의 `notes.txt` → 그 파일. D13 참조 파일의 `references/` → 그 줄. D14 README에서 `bm-recover`가 빠짐 → "bm-recover: add it to the skill list in README.md". D15 `scripts/`의 새 파일에 gcloud → `scan/scripts/zz-flip.txt:1`. 포트 `0.0.0.0` → ports 테스트. Funnel, bash 3.2, `AGENT_ID` → `refute_matches`가 찾은 줄. D5(`!.env.example` 지움)와 D6(Gemini `GEMINI.md`)은 일반 메시지만 냈다. 문구를 고친 뒤 2차: D5 → "git check-ignore .env.example exited 0, expected 1", D6(`CLAUDE.md`에 줄 추가) → "Claude Code: CLAUDE.md must hold only @AGENTS.md"(ok 118, not ok 2). 3차(`.env` 불변식): 인덱스에 빈 `.env` 항목을 넣고(파일은 만들지 않음) Gemini를 `GEMINI.md`로 → D5 "these hold secrets and must never be tracked by git: .env", D6 "Gemini CLI: .gemini/settings.json must name AGENTS.md in context.fileName"(ok 118, not ok 2). 매번 파일을 복사본으로 되돌렸고, `.env`는 `git update-index --force-remove`로 뺐다. 그 뒤 `git diff`는 바꾸기 전과 같았고, `git ls-files`의 `.env*`는 `.env.example`뿐이다. |
| 2026-10-21 | Verified | Task 9 이름 목록: `tests-t9-merge.tsv`(120줄, 커밋 `6bb03e9`의 `git archive`)는 `tests-t8c.tsv`(140줄)에서 이름 34개가 빠지고 14개가 생겼다(D1 2, D2 1, D3·D4 6, D5 2, D6 2, D7 3, D9 2, D10 3, D12 4, D13 4, D14 2, D15 3 → 결과 14). 새 이름 14개는 표의 결과 이름과 같다(`grep -F`로 확인). 이름이 같은 테스트의 단언 수는 바뀌지 않았다. 합친 테스트의 단언 줄 수가 옛 테스트들의 합보다 적은 것은 문제를 `bad`에 모아 `fail` 한 번으로 내기 때문이다. `tests-t9.tsv`(119줄)는 `tests-t9-merge.tsv`에서 "operational skills …" 하나가 빠졌다. D16의 이름이 바뀌고 D8의 단언 수가 2 → 1이 된 것 말고는 같다. `make check`(두 커밋 모두): exit 0, not ok 0, ok 120(합치기)과 119(지우기), 총 줄 커버리지 94.42%. 파일별 커버리지는 Task 8(`coverage-t8c.txt`)과 같다. `coverage-t5.txt`보다 떨어진 파일은 Task 6에서 적은 `scripts/remote/provision-vm.sh` 하나다. 저장소 전체 테스트는 스크립트를 실행하지 않는다. |
| 2026-10-21 | Verified | Task 9 리뷰 지적 SDD-T9-F1~F4와 문구 하나(고치기 1회차). F1: D2가 이미지 줄을 서비스 블록으로 고르면서 Basic Memory가 어느 이미지를 쓰는지 보는 검사가 사라졌다(`d782269`의 `tests/repo-config.bats:8-11`은 `ghcr.io/basicmachines-co/basic-memory:<버전>@sha256:…`을 요구했다). D3에 basic-memory 블록의 `image:` 줄이 `ghcr.io/basicmachines-co/basic-memory:`로 시작하는지 보는 줄을 더했다. Step 4의 예외로 D3의 이름을 바꿨다(D4의 "is a -slim image"처럼): "basic-memory serves streamable-http on /mcp, …" → "basic-memory runs the basicmachines-co image, serves streamable-http on /mcp, …"(단언 수 12 → 13). F2: `compose_services`는 `^  [a-z0-9-]+:$`만 서비스로 읽어, 주석이 붙거나 밑줄이 있는 서비스 키의 이미지를 D2가 보지 않았다. 이제 D2는 compose.yaml의 모든 `image:` 줄을 `PINNED_IMAGE`로 보고(없으면 실패), 서비스마다 이미지 줄이 있는지도 그대로 본다(단언 수 2 → 3). F3: D13 첫째 테스트의 중첩 SKILL.md `find`와 `cloud_scan`의 `find`가 here-string 안에 있어, find가 실패해도 빈 목록으로 지나갔다. 결과를 변수로 받고 find가 실패하면 그 사실을 적은 `fail`로 멈춘다. `cloud_scan`은 복사본에 파일이 없을 때도 실패한다(D13 첫째 테스트 단언 수 2 → 3). F4: D13 둘째 테스트에 더했던 references 폴더 수 방어 줄은 지웠다. 스킬에 references가 없는 것도 올바른 상태라서 변경 감지가 된다(ADR 0004 결정 2). 묶인 파일 수 방어 줄만 남는다. 앞의 Task 9 행들에 적은 references 방어 줄과 그 확인 결과는 이 행으로 바뀐다. 문구: "Task 9 반복문 경우 확인" 행의 "보안 불변식 셋"을 "불변식 셋(보안 불변식인 포트 127.0.0.1과 Funnel, AGENTS.md 불변식인 bash 3.2)"으로 고쳤다. 확인(커밋하지 않음, 되돌림): compose.yaml의 Basic Memory 이미지 소유자를 `ghcr.io/someone/`으로 바꾸고, silverbullet 뒤에 `  extra_svc:  # comment`와 `    image: busybox:latest`를 더했다. 같은 실행에 `repo-skills.bats`, `repo-cloud-neutral.bats`의 사본 둘(가짜 `find`가 `-mindepth 2 -iname`, `-type f` 호출에서만 실패)도 돌렸다. `make test`: ok 122, not ok 4. D3 "basic-memory must run the ghcr.io/basicmachines-co/basic-memory image", D2 "compose.yaml:63:    image: busybox:latest", 사본의 D13 첫째 테스트 "find could not search .agents/skills/bm-diagnose for nested SKILL.md files", 사본의 D15 "find could not list the files copied from …/sample"이다. compose.yaml은 복사본으로 되돌렸고 사본 둘은 지웠다(`git diff`는 바꾸기 전과 같다). 이름 목록 `tests-t9b.tsv`(119줄)는 `tests-t9.tsv`와 비교해 D3의 이름과 단언 수, D2와 D13 첫째 테스트의 단언 수만 다르다. `make check`: exit 0, ok 119, not ok 0, 총 줄 커버리지 94.42%. |
| 2026-10-21 | Verified | Task 10 RED(Step 2): `tests/lib-layout.bats`(2개)와 `tests/create-script.bats`(3개)를 먼저 쓰고 `make test`를 돌렸다. exit 2, 124개 가운데 ok 119, not ok 5이고 not ok는 새 테스트 다섯 개뿐이다. `lib-layout`의 둘("script_verbs reads …", "pair_test maps …")은 setup의 `. "$REPO_DIR/scripts/lib/layout.sh"`에서 "No such file or directory"로 멈췄다. `create-script`의 셋은 setup이 아직 없는 스킬을 복사하다 "cp: cannot stat '/repo/.agents/skills/script-authoring'"로 멈췄다. Step 2의 예상 이유(`scripts/create-script.sh` 없음)보다 한 줄 앞이지만, 같은 Task가 만드는 파일이 없어서 멈춘 것은 같다. |
| 2026-10-21 | Verified | Task 10 구현에서 브리프가 정하지 않은 선택. (1) `tests/repo-scripts.bats`의 "every executable shell file enables strict mode"는 추적하는 `*.sh`를 모두 보므로, `set -euo pipefail`이 없는 라이브러리 템플릿 `assets/lib.sh`에서 실패했다(구현 뒤 첫 `make test`의 not ok 4개 가운데 하나다. 나머지 셋은 `scripts/create-script.sh`에 실행 권한을 빠뜨린 탓이었고 `chmod +x`로 고쳤다). 라이브러리는 strict mode로 도는 스크립트가 source하므로 그 줄을 두지 않는다. 그 검사의 제외 목록(`*.bash \| scripts/lib/*`)에 이 템플릿 경로 하나만 더했다. 테스트 이름과 단언 수는 그대로다. (2) shellcheck v0.11.0이 remote 템플릿의 쓰이지 않는 `log`를 SC2329(info)로 막아 `make lint`가 exit 2였다. `main`의 첫 줄을 첫 단계 자리 `log "…"`로 두어 템플릿이 자기 `log`와 `die`를 모두 쓴다. (3) `assets/.shellcheckrc`는 저장소 `.shellcheckrc`의 두 줄(`external-sources=true`, `source-path=SCRIPTDIR`)을 그대로 두고 `disable=SC1091`만 더했다. (4) `.bats`의 `bash -n`: bash는 `@test` 줄을 읽지 못하므로, 테스트가 sed로 그 줄을 함수 머리로 바꾼 뒤 `bash -n`에 넘긴다(bats가 하는 변환과 같다). (5) 경로 두 줄은 stdout, "add a Make target with a ## description and .PHONY if people run it"은 KIND와 상관없이 마지막 줄로 stderr에 낸다. (6) lib 템플릿에는 함수가 없어, 생성된 lib 테스트의 성공 자리는 "command not found"(127, bats 경고 BW01)로 실패한다. 스킬 Steps 2에 적었다. |
| 2026-10-21 | Verified | Task 10 새 테스트가 제 이유로 실패하는지 확인(커밋하지 않음, 되돌림): 다섯 곳을 한 번에 바꿔 `make test`를 돌렸다. ok 119, not ok 5이고 바꾼 곳마다 그 테스트 하나만 실패했다. `create-script.sh`가 짝 테스트의 존재를 보지 않음 → "create-script.sh did not refuse remote check-probe"(Review Focus 6). 동사 검사를 건너뜀 → "create-script.sh did not refuse script frob-probe with: not a verb". lib 가드를 바꾸지 않음 → `scripts/lib/probe-kit.sh`에 남은 `_BM_LIB_NAME` 두 줄. `pair_test`의 스크립트 정규식을 `(.+)`로 → "pair_test scripts/other/show-status.sh: expected a refusal". `script_verbs`가 제목 없는 파일을 통과 → "script_verbs did not stop on: # Skill…". 원래 파일로 되돌린 뒤 `git diff`는 비었다. |
| 2026-10-21 | Verified | Task 10 Step 5(커밋하지 않음): `make new-script NAME=show-probe`, `make new-script NAME=check-probe KIND=remote`, `make new-script NAME=probe KIND=lib`가 모두 exit 0이고 각각 경로 두 줄을 냈다(`scripts/show-probe.sh`·`tests/show-probe.bats`, `scripts/remote/check-probe.sh`·`tests/remote-check-probe.bats`, `scripts/lib/probe.sh`·`tests/lib-probe.bats`). 두 스크립트는 실행 권한이 있고 라이브러리는 없다. `make lint`: exit 0이고 여섯 파일이 shellcheck와 shfmt 목록에 들었다. `make test`: 130개, ok 127, not ok 3. not ok는 생성된 테스트의 성공 경로 자리 셋뿐이다(스크립트 둘은 `ERROR: not implemented: write tests/show-probe.bats first`와 `[check-probe] ERROR: not implemented: write tests/remote-check-probe.bats first`, lib은 "command not found"). 실패 경로 자리 셋은 ok다. 여섯 파일을 지운 뒤 `git status --short --untracked-files=all`에 생성 파일이 남지 않았다. |
| 2026-10-21 | Verified | Task 10 GREEN(Step 4): `make check` exit 0, 124개, not ok 0, 총 줄 커버리지 93.52%(Task 9의 94.42%에서 내려감). `scripts/create-script.sh` 97.44%이고 지나지 않는 줄은 `:43`(모르는 KIND)이다. `scripts/lib/layout.sh` 55.88%: 지나지 않은 15줄은 모두 `script_verbs`의 여러 줄 awk 프로그램 안의 줄이다. kcov는 따옴표 안의 줄도 bash 줄로 세며, 같은 모양의 `scripts/lib/docs.sh`도 56.67%다. bash 줄은 모두 지난다(`:9-18`, `:24-25`, `:44-46`, `:53-61`). `repo-skills` 테스트(색인 두 곳, 링크, frontmatter, 묶음 파일 이름)는 모두 ok다. 이름 목록 `tests-t10.tsv`(124줄)는 `tests-t9b.tsv`(119줄)에 새 테스트 다섯 개만 더해졌다(단언 수: "creates a script, …" 9, "pair_test maps …" 3, "refuses a name …" 3, "refuses when the script …" 3, "script_verbs reads …" 4). Step 6(새 세션에서 스킬 시험)은 커밋 뒤 컨트롤러가 한다. |
| 2026-10-21 | Verified | Task 10 Step 6(스킬 시험, 컨트롤러가 실행): sonnet 에이전트를 새 세션마다 띄워 아무것도 바꾸지 말고 계획만 말하게 했다. 기준은 worktree가 없는 `47dbbc7`의 `git archive`다. 처음 기준 실행 두 번은 worktree를 읽었으므로 버렸다. worktree: "백업 목록을 보여 주는 스크립트를 추가해 주세요" → `script-authoring`과 `git-workflow`, `make new-script NAME=show-backups KIND=script`(동사 show), 테스트 먼저, `##` 설명과 `.PHONY`. "make target 하나 더 만들어 주세요" → `script-authoring`과 `git-workflow`, 스크립트가 필요하면 `make new-script`, `##`과 `.PHONY`는 `tests/repo-make.bats`가 검사한다. "이 bats 테스트에 스텁을 더해 주세요" → `script-authoring`과 `git-workflow`, `tests/stubs/<command>`, `setup_stubs`, `assert_stub_called`·`refute_stub_called`, RED 뒤 GREEN. 비껴갈 것: "런북을 새로 써 주세요" → `doc-authoring`과 `git-workflow`, "스킬 설명을 고쳐 주세요" → `skill-authoring`과 `git-workflow`. 다섯 모두 빠진 정보를 먼저 묻고 VM 단계를 계획하지 않았다. 기준: 세 스크립트 프롬프트는 `git-workflow`만 쓰고 스크립트를 손으로 만들었다(하나는 표에 없는 동사의 `list-backups.sh`). `make new-script`도 스텁 도우미도 쓰지 않았다. 비껴갈 둘은 worktree와 같은 스킬을 골랐다. 결론: 세 프롬프트에서 `script-authoring`이 뽑혔고 비껴갈 프롬프트 둘은 바뀌지 않았다. 스킬의 설명과 본문은 고치지 않았다. |
| 2026-10-21 | Verified | Task 10 리뷰 지적 SDD-T10-F1, SDD-T10-F2(고치기 1회차). F1: 스킬의 "Keep `scripts/` and `tests/` flat" 문장이 글자 그대로는 `tests/stubs/`와 `tests/fixtures/`도 막았다. 허용 폴더를 `scripts/remote/`, `scripts/lib/`, `tests/stubs/`, `tests/fixtures/` 넷으로 적었다. F2: lib 이름 규칙(`LIB_NAME_PATTERN`)을 고정하는 경우가 없었다(`probe-kit`만 있었다). "creates a script, …"에 한 낱말 lib 경우(`probe` → `scripts/lib/probe.sh`, `tests/lib-probe.bats`, 가드 `_BM_LIB_PROBE`)를 더하고, 가드 확인을 경우마다 반복문 안으로 옮겼다. 경우마다 `( … ) \|\| fail "<경우>"`로 돌리고 준비 줄을 `&& … \|\| exit 1`로 이었다. 확인(커밋하지 않음, 되돌림): `LIB_NAME_PATTERN`이 하이픈을 요구하게 바꾸자 `make test`는 ok 123, not ok 1이었고, not ok는 이 테스트 하나, 메시지는 "create-script.sh did not create lib probe as scripts/lib/probe.sh and tests/lib-probe.bats"였다. 이름 목록 `tests-t10b.tsv`(124줄)는 `tests-t10.tsv`와 이 테스트의 단언 줄 수(9 → 8)만 다르다. 세 단언을 한 줄로 이어서 줄 수가 줄었고, 검사는 하나도 빠지지 않았다. |
| 2026-10-21 | Verified | Task 11 검사 다섯 개(Step 1, `tests/repo-scripts.bats`). setup이 `scripts/lib/layout.sh`를 source하고, 검사 1~4가 그 `pair_test`, `script_verbs`, `SCRIPT_AUTHORING_SKILL`, `SCRIPT_TEMPLATES_DIR`을 쓴다. 반복문은 문제를 모두 모아 한 번에 실패하고, 줄마다 파일과 고칠 곳을 낸다(ADR 0007 결정 3). (1) 짝: `scripts/*.sh`, `scripts/remote/*.sh`, `scripts/lib/*.sh`마다 `pair_test`로 짝 이름을 만들고 파일이 없으면 "<스크립트>: no <짝>; write it from <템플릿>.bats"를 적는다. 그 짝 이름 집합에 없는 `tests/*.bats`(`repo-*.bats` 제외)는 "pairs no script"로 적는다. 짝 규칙은 여럿이 하나로 가므로(`scripts/remote-x.sh`와 `scripts/remote/x.sh` → `tests/remote-x.bats`) 거꾸로 풀지 않고 앞 방향 집합과 비교한다. 스크립트나 짝 테스트가 0개면 실패한다. (2) remote: `refute_matches scripts/remote '^[[:space:]]*(\.\|source)[[:space:]].*lib/'`, 실패하면 템플릿 `remote.sh`를 가리킨다. (3) 라이브러리: `common.sh` 말고 `scripts/lib/*.sh`마다 같은 source 줄 정규식으로 `common.sh`를 찾고, 라이브러리가 0개면 실패한다. (4) 이름: `script_verbs`가 비거나 실패하면 실패한다. `scripts/*.sh`, `scripts/remote/*.sh`의 이름이 `^[a-z0-9]+(-[a-z0-9]+)+$`(`scripts/create-script.sh`의 `SCRIPT_NAME_PATTERN`과 같은 규칙)에 맞고 첫 낱말이 동사 표에 있는지 본다. 메시지는 허용 동사 15개를 나열한다. (5) 문서 경로: `git grep --untracked -I -n -o -E 'scripts/[A-Za-z0-9_./-]+\.sh'`를 `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/runbooks/*.md`, `.agents/skills`, `Makefile`, `.github`, `.claude/agents`에 돌려(코드 블록 포함, 새 파일 포함) 없는 파일을 `파일:줄: 경로`로 적는다. 일치가 없거나 git grep이 실패하면 실패한다. 이름 목록 `tests-t11.tsv`(129줄)는 `tests-t10b.tsv`(124줄)에 새 이름 다섯 개만 더해졌다(단언 수 3, 2, 2, 3, 2). |
| 2026-10-21 | Verified | Task 11 Step 2(심은 위반, 커밋하지 않음, 되돌림): `scripts/frob-probe.sh`(실행 권한, strict mode), `tests/ghost-probe.bats`, `scripts/remote/check-probe.sh`(`. "${BASH_SOURCE[0]%/*}/../lib/common.sh"`)와 `tests/remote-check-probe.bats`, `scripts/lib/probe.sh`(source 가드만)와 `tests/lib-probe.bats`, `docs/ARCHITECTURE.md` 끝에 `scripts/nope-probe.sh` 한 줄과 bash 펜스 코드 블록 안의 `scripts/nope-fenced.sh` 한 줄을 심었다. `make test`: exit 2, 132개, ok 127, not ok 5이고 not ok는 검사 다섯 개뿐이다. (1) "scripts/frob-probe.sh: no tests/frob-probe.bats; write it from .agents/skills/script-authoring/assets/script.bats"와 "tests/ghost-probe.bats: pairs no script; …"(Review Focus 5의 역방향). (2) `/repo/scripts/remote/check-probe.sh:4:`와 그 source 줄. (3) "scripts/lib/probe.sh"(Review Focus 5의 새 라이브러리). (4) "scripts/frob-probe.sh: 'frob' is not a verb of the table". (5) "docs/ARCHITECTURE.md:97: scripts/nope-probe.sh"와 "docs/ARCHITECTURE.md:100: scripts/nope-fenced.sh"(Review Focus 5의 코드 블록). 심은 파일을 지우고 `docs/ARCHITECTURE.md`를 원본 사본으로 되돌린 뒤 `git diff --quiet -- docs/ARCHITECTURE.md`가 통과했고, `git status --short`에는 ` M tests/repo-scripts.bats`만 남았다. 심기 전 `make test`는 129개 모두 ok였다. |
| 2026-10-21 | Verified | Task 11 낡은 경로: 검사 5의 범위에서 `git grep -n -o`가 파일 9개의 일치 53개(서로 다른 경로 28개)를 냈고 모두 있는 파일이다. 고친 경로는 없다. `AGENTS.md` 15, 18, 45, 46행을 P6 문구로 바꿨다(계획 Decisions의 문구를 그대로 옮겼다). 크기는 9,409 → 9,841바이트(한도 24,000)다. |
| 2026-10-21 | Verified | Task 11 Step 4: `make check` exit 0, 129개, not ok 0, 총 줄 커버리지 93.52%(Task 10과 같다). `make lint` exit 0. `AGENTS.md` 크기 검사("AGENTS.md fits the smallest rule file limit of the four agents")는 ok다. |
| 2026-10-21 | Verified | Task 11 리뷰 지적 SDD-T11-F1~F3(고치기 1회차). F1: 이름 규칙 `SCRIPT_NAME_PATTERN`, `LIB_NAME_PATTERN`을 `scripts/create-script.sh`와 `tests/repo-scripts.bats`에서 지우고 `scripts/lib/layout.sh`의 상수 자리로 옮겼다(정본 한 곳, ADR 0007 결정 3, P3). 두 파일 모두 layout.sh를 source해 같은 상수를 쓴다. F2: 검사 2가 줄 첫머리의 `lib/` source 줄만 보았다. 이제 줄 첫머리나 `;`, `&`, `\|`, `(`, `$(` 뒤에서 `.sh` 경로를 source하는 명령을 모두 막는다(`SOURCES_SH`). `scripts/remote/provision-vm.sh:70`의 `$(. "$OS_RELEASE" && …)`는 `.sh`가 없어 걸리지 않고, 그 파일에서 걸리는 줄은 없다. `scripts/*.sh` 21개는 모두 이 정규식에 걸린다(라이브러리를 source하므로). F3: 검사 3이 `common.sh`를 말하는 주석에도 통과했다. 이제 `#` 앞의 source 경로가 `common.sh`로 끝나야 한다(`SOURCES_COMMON`). 지금의 라이브러리 다섯 개는 모두 걸린다. 확인(커밋하지 않음, 지움): `scripts/remote/check-probe.sh`(`LIB_DIR="${BASH_SOURCE[0]%/*}/../lib"`, `. "$LIB_DIR/common.sh"`, `mode="$(. "$LIB_DIR/vm.sh" && …)"`)와 짝 테스트, `scripts/lib/probe.sh`(`. "${BASH_SOURCE[0]%/*}/vm.sh"  # vm.sh sources common.sh`만 있음)와 짝 테스트를 심었다. `make test`: 131개, ok 129, not ok 2. 검사 2는 `check-probe.sh:5`와 `:6`을, 검사 3은 `scripts/lib/probe.sh`를 냈다. 검사 1과 4는 ok였다. 지운 뒤 `git status --short`에 심은 파일이 없다. 이름 목록 `tests-t11b.tsv`(129줄)는 `tests-t11.tsv`와 같다. |
| 2026-10-21 | Verified | 최종 리뷰 지적 SDD-final-F1~F5 고침. F1: `tests/repo-make.bats`의 local-up 테스트에 유효한 SB_USER 성공 절반(성공, 비밀번호 부분 미출력, `docker compose -f compose.yaml up -d --wait` 정확히 1회)을 되살리고 이름을 바꿨다. 뒤집기(Makefile 62행을 비움, 되돌림): 이 테스트만 실패했다(`assert_output 1`). F2: `SOURCES_SH`가 `{`와 `then`, `do`, `else` 뒤의 source도 잡는다. 심은 `scripts/remote/check-probe.sh`(`if [ -f x ]; then . ...; fi`, `{ . ../lib/vm.sh; }`)에서 검사 2만 실패하고 두 줄을 모두 짚었다(되돌림). F3: 합친 반복문의 준비 명령(`: >"$STUB_LOG"`, `rm`, `mkdir`, `echo`, `install`, `make_archive` 등)에 `|| exit 1`을 붙였다(restore-notes, backup-notes, bootstrap-vm, remote-provision-vm, check-access, lib-sb, lib-vm, verify-vm, verify-mcp). F4: `tests/repo-scripts.bats`가 `$SCRIPT_TEMPLATES_DIR/lib.sh`를 쓴다. F5: `tests/create-script.bats` 첫 테스트에 빈 KIND 사례를 더했다. `make check` exit 0, 129개, not ok 0, 총 줄 커버리지 93.52%. 이름 목록 차이는 F1의 이름과 단언 수(3에서 6)뿐이다. |
