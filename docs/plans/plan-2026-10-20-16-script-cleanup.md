---
status: active
spec: docs/specs/spec-2026-10-15-script-test-layout.md
---

# 16 Script Cleanup Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 모든 Task가 같은 스크립트와 라이브러리를 고치므로 한 worktree에서 한 명만 쓴다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM을 바꾸는 Step은 Task 7의 `make deploy` 하나이고, 메인 세션에서 사용자 OK를 받은 뒤 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** `scripts/lib/`를 관심사별 라이브러리(common, vm, sb, git, docs)로 나누고, 스펙 5절 표의 중복 8가지를 한 곳으로 모으고, 실행 스크립트 13개를 `<동사>-<대상>.sh`로 바꾸되, 스크립트의 동작은 바꾸지 않는다.

**Architecture:**
- 라이브러리마다 맨 위에 이중 source 방지 줄과 함수 색인을 둔다. 관심사 라이브러리는 `common.sh`를 source하고, 스크립트는 직접 부르는 함수가 있는 라이브러리만 source한다. 방지 줄이 있으므로 같은 라이브러리를 여러 번 source해도 된다.
- 함수는 먼저 옛 이름의 스크립트에서 옮기고 합친다(Task 1~5). 이름 변경은 마지막 Task 6에서 한다. 이름 변경 커밋에서는 경로 참조만 고쳐서 `git log --follow`가 옛 이력을 따라가게 한다.
- 지금 있는 테스트가 안전망이다. 이 계획은 기존 테스트 파일에서 스크립트·라이브러리 경로만 고친다. 예외는 "Decisions"의 P3, P7에 적은 기대값 두 개다. 옮긴 함수의 테스트는 새 짝 파일 `tests/lib-vm.bats`, `tests/lib-sb.bats`, `tests/lib-git.bats`로 옮긴다. 테스트 파일의 이름 변경과 분할은 계획 17이 한다.
- Task마다 끝에 `make check`를 돌리고, 테스트 이름 목록을 Task 전과 비교해 Progress log에 적는다(스펙 11절).

**Spec:** `docs/specs/spec-2026-10-15-script-test-layout.md` (특히 §3, §4, §5, §2.1의 규칙 위반, §10, §11)

**Sequence:** 계획 16. 다음을 모두 만족한 뒤 시작한다.
- 문서 체계 계획 14(PR #13, `eda0d92`)가 병합됐다(충족). 계획 15(PR #14, `e648d5a`)도 병합됐다.
- 열린 PR #10(`work/docker-log-rotation`)도 `compose.yaml`, `docs/ARCHITECTURE.md`, `tests/repo.bats`를 고친다. 나중에 병합되는 쪽이 `git merge origin/main`으로 충돌을 푼다. 리베이스하지 않는다.
- 계획 17은 이 계획의 PR이 병합된 `main`에서 쓴다(스펙 10절).

## Decisions

스펙이 정하지 않은 곳에서 이 계획이 고른 것이다. 계획을 승인하면 이 결정들도 승인하는 것이다.

- **P1. sb 공간 적용은 함수가 맡고, 쓰기 스크립트는 그대로 둔다.** `sync-sb-space.sh`(지금 `sb-space.sh`)는 지금처럼 파일을 쓰고 `changed`나 `unchanged`만 출력한다. "바뀌었는가 → 다시 만들기 → 표지 삭제 → 다시 쓰기 → 변화 없음 확인"이라는 순서는 `lib/sb.sh`의 `sb_space_apply`가 맡고, Makefile·deploy·restore가 이 함수를 부른다. Makefile은 라이브러리를 source하고 이 함수를 한 줄로 부른다. 이유: `tests/sb_space.bats`가 고치지 않은 채로 안전망 역할을 계속한다.
- **P2. deploy는 이미지 pull을 공간 파일보다 먼저 한다.** 지금 순서는 공간 파일 쓰기 → pull → (바뀌었으면) 다시 만들기다. P1의 함수는 쓰기와 다시 만들기를 한 번에 하므로, pull을 앞으로 옮긴다. 다시 만들 때 새 이미지를 쓰고, pull이 실패하면 VM의 공간 파일은 그대로 남는다. 순서를 설명한 `docs/ARCHITECTURE.md`(주요 흐름의 배포)도 고친다.
- **P3. `BM_ACCESS` 확인은 `require_vm`이 한 번 한다.** 지금은 `remote()`가 부를 때마다 확인한다(`common.sh:136-138`). 스펙 중복 7번에 따라 `remote()`의 확인을 빼고, VM을 쓰는 모든 스크립트가 처음에 `require_vm`을 부른다. `tests/common.bats`의 "remote checks BM_ACCESS …" 테스트는 `require_vm`을 검사하는 테스트로 바뀐다. 스크립트 단위의 불변식("모드를 읽지 않는 VM 타깃도 멈춘다")은 `tests/access.bats`의 logs 테스트가 계속 지킨다.
- **P4. 노트 폴더의 존재 확인은 sb.sh의 `notes_file_state`가 한다.** `sb-space.sh:37,47`은 `--local`도 다루므로 VM 전용인 `remote_exists`를 쓸 수 없다. 대신 두 함수가 같은 sh 조각 `exists_cmd`(vm.sh)를 쓰고, 둘 다 `present`나 `absent`를 출력한다.
- **P5. `AGENTS.md`는 이 계획에서 고치지 않는다.** 스펙 10절에 따라 Invariants·Skills·Map은 계획 17이 고친다. 그 사이에도 Invariants의 "source `scripts/lib/common.sh`"는 틀린 말이 아니다. 모든 라이브러리가 `common.sh`를 source하기 때문이다.
- **P6. VM에서는 브랜치에서 확인한다.** 이 계획은 VM의 상태를 바꾸지 않으므로 결과 PR을 따로 두지 않는다. Task 7에서 OK가 필요 없는 확인(`make access-check probe status logs backup verify`)은 바로 하고, `make deploy`만 사용자 OK를 받아 이 브랜치에서 한 번 실행한다. P2의 새 순서와 P1의 함수를 실제로 증명하는 것은 deploy뿐이기 때문이다. 관리 페이지(`silverbullet/agent-hub.md`)의 스크립트 이름 한 줄도 그때 VM에 반영된다.
- **P7. 두 터널은 `tunnel_args` 하나로 ssh 인자를 만든다.** 함수는 ssh를 실행하지 않고 인자 배열만 만든다. ssh는 호출하는 쪽이 실행한다. 그래야 verify의 `ssh … &`에서 `$!`가 ssh 자신이 되어, 끝날 때 터널을 죽일 수 있다. 함수 안에서 실행하면 `$!`는 하위 셸의 pid가 되고 ssh는 남는다. `ExitOnForwardFailure`는 함수가 넣고, 다른 옵션은 인자로 받아 그 뒤에 둔다. 그래서 `tests/vm_ops.bats:204`의 verify 터널 기대 줄에서 옵션 순서만 바뀐다(`-o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=10`). `make tunnel`의 줄과 `running:` 로그는 그대로다.

## Global Constraints

- 동작을 바꾸지 않는다(스펙 1절, 범위 밖). 예외는 P2의 순서와 오류 문구의 다듬기(같은 원인, 같은 다음 행동)다.
- Make 타깃 이름은 그대로 둔다. CI가 부르는 `check-git.sh`, `check-pr.sh`도 이름을 바꾸지 않는다(스펙 4절).
- 라이브러리 이름은 `<주제>.sh`다. 맨 위에 `[ -n "${_BM_LIB_<NAME>:-}" ] && return 0`과 `readonly _BM_LIB_<NAME>=1`을 두고, 그 위의 머리 주석에 함수 색인(이름과 한 줄 설명)을 둔다. 함수 이름에 접두어 규칙은 없다(E6).
- `scripts/remote/*.sh`는 `scripts/lib/`를 source하지 않는다. 복사해 둔 log, die, 상수, 접속 방식 확인은 그대로 둔다(E5). 임시 폴더와 `trap` 도우미, 스텁 공통 머리도 만들지 않는다(E5).
- macOS bash 3.2 규칙(`AGENTS.md` Invariants): 연관 배열, `mapfile`, 빈 배열 펼치기를 쓰지 않는다. 실패할 수 있는 `x="$(fn)"` 뒤에는 `|| exit 1`을 붙인다. `readonly X="$(…)"`처럼 실패를 가리는 꼴로 쓰지 않는다.
- 기록 문서(완료 계획, 스펙, ADR, 리뷰, 조사)에 남은 옛 스크립트 이름은 그대로 둔다(스펙 4절).
- 테스트는 `make test`/`make check`로만 돌린다. 테스트를 약하게 만들어 통과시키지 않는다. 테스트 이름 목록 비교: `grep -h '^@test' tests/*.bats | sort`.
- 줄 번호는 `e648d5a` 기준이다. 앞 Task를 거치면 줄이 밀리므로, Task마다 `grep -n`으로 위치를 다시 찾는다.
- `git add` 전에 `git status`를 본다. 커밋 트레일러: `Assisted-by: claude-code claude-opus-5-5`, `Plan: 16`, `Task: <N|review|none>`.
- PR: 브랜치 `plan/16-script-cleanup`, 제목 `refactor: split the script libraries, merge duplicates and rename scripts`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 16`이다.

## Review Focus

1. **라이브러리를 두 번, 또는 다른 순서로 source함.** `readonly`를 다시 할당하면 스크립트가 바로 죽는다. Makefile은 `sb.sh`를, deploy와 restore는 `vm.sh`와 `sb.sh`를 source한다. → Task 1의 `lib-sb.bats` 첫 테스트가 세 라이브러리를 거꾸로, 두 번씩 source한다.
2. **`BM_ACCESS`를 확인하지 않는 VM 스크립트가 생김(P3).** `remote()`가 더는 확인하지 않는다. → Task 3의 `require_vm` 테스트, 그대로 둔 `access.bats` logs 테스트. Task 3 Step 4가 `remote`·`in_notes_dir`·`vm_tailscale_logged_in`을 부르는 스크립트마다 `require_vm`(또는 그것을 부르는 `notes_dir_arg`)이 있는지 grep으로 확인한다.
3. **VM이 답하지 않았는데 `absent`로 읽힘.** restore가 "VM에 이전 데이터가 없다"고 판단하면 롤백하지 않는다. → Task 3의 `lib-vm.bats` 테스트: ssh가 실패하면 `remote_exists`는 0이 아닌 값으로 끝나고, `absent`를 출력하지 않는다.
4. **다시 만들기가 실패한 뒤 재실행(P2).** 순서가 바뀌므로, 표지가 남은 채로 실패한 다음 실행도 다시 만들어야 한다. → Task 4의 `lib-sb.bats` 테스트.
5. **터널 옵션이 빠지거나, 바인딩이 넓어지거나, 터널이 남음(P7).** verify 터널이 BatchMode를 잃으면 `make verify`가 프롬프트에서 멈춘다. 두 터널은 `forward_spec`로 `127.0.0.1`에만 바인딩해야 한다. verify가 끝나면 ssh 자신이 죽어야 한다. → Task 5. `vm_ops.bats`와 `access.bats`가 ssh 줄 전체를 `grep -Fx`로 비교하고, `vm_ops.bats`의 "leaves no tunnel behind"와 "closes its tunnel even when a check fails"가 스텁 ssh의 pid가 살아 있지 않은지 본다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `scripts/lib/common.sh` | 핵심 도우미, `REPO_DIR`, 공용 상수(포트 기본값, `PARTIAL_SUFFIX`), `utc_stamp`, `main_checkout_root` | 1, 3 |
| `scripts/lib/vm.sh` (새 파일) | VM 상수, 접속 방식, `require_vm`, ssh·compose 실행, 존재 확인, 터널 인자, `vm_env`, manifest, 해시 | 1, 3, 5 |
| `scripts/lib/sb.sh` (새 파일) | SilverBullet 상수, `require_sb_user` 계열, 노트 폴더 쓰기, `notes_file_state`, `sb_space_apply` | 1, 3, 4 |
| `scripts/lib/git.sh` (새 파일) | 트레일러 패턴, 문제 모으기와 보고, 리뷰 출력 경로 | 2 |
| `scripts/lib/docs.sh` | `common.sh` source와 방지 줄만 더한다 | 1 |
| `scripts/*.sh`, `scripts/remote/bootstrap.sh` | source 줄, 중복 제거, 이름 변경, usage 줄 | 1~6 |
| `Makefile` | local-up 한 줄, 포트 기본값 주석, 새 스크립트 경로, deploy 설명 | 1, 3, 4, 6 |
| `tests/lib-vm.bats`, `tests/lib-sb.bats`, `tests/lib-git.bats` (새 파일) | 새 라이브러리의 짝 테스트 | 1~4 |
| `tests/common.bats` | VM 테스트를 `lib-vm.bats`로 보내고 `mask`만 남김(이름 변경은 계획 17) | 1 |
| 그 밖의 `tests/*.bats` | 스크립트·라이브러리 경로, P7 기대 줄 | 1, 5, 6 |
| `.claude/agents/branch-reviewer.md`, `docs/ARCHITECTURE.md`, 스킬 3개, `compose.yaml`, `silverbullet/agent-hub.md` | 새 스크립트 이름, 라이브러리 구성, deploy 순서 | 1, 4, 6 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`에서 `plan/16-script-cleanup` 브랜치를 만든다(`git-workflow` 스킬의 Start). worktree `repo-structure`를 다시 쓴다(`.review-out/`에 계획 13~15의 리뷰 기록이 있으니 지우지 않는다).
- [x] 첫 커밋에서 이 파일의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다(`Task: none`).
- [x] 참조 목록(스펙 11절)을 Progress log에 적는다. 명령은 Task 6 Step 2와 같다.

### Task 1: common, vm, sb 라이브러리로 나누기

**Files:**
- Create: `scripts/lib/vm.sh`, `scripts/lib/sb.sh`, `tests/lib-vm.bats`, `tests/lib-sb.bats`
- Modify: `scripts/lib/common.sh`, `scripts/lib/docs.sh`, 스크립트 전부의 source 줄, `deploy.sh:8-9`·`restore.sh:11-12`·`sb-space.sh:16-17`(스크립트마다 구하던 `REPO_DIR` 삭제), `Makefile:19,56,60`, `tests/common.bats`, `tests/backup_restore.bats:32`, `tests/repo.bats:104`, `docs/ARCHITECTURE.md:43`

**Interfaces:**
- Produces: 아래 표의 함수와 상수가 표의 파일에 산다. 시그니처와 동작은 지금과 같다. 새로 생기는 것은 `common.sh`의 `readonly REPO_DIR`(이 라이브러리가 들어 있는 저장소의 루트)와 방지 변수 `_BM_LIB_COMMON`, `_BM_LIB_VM`, `_BM_LIB_SB`, `_BM_LIB_DOCS`다.

| 파일 | 상수 | 함수 |
|---|---|---|
| `common.sh` | `COMMON_LIB_DIR`, `REPO_DIR` | `log`, `step`, `die`, `require_cmd`, `require_env`, `mask`, `main_checkout_root` |
| `vm.sh` | `BM_REMOTE_APP_DIR`, `BM_REMOTE_DATA_ROOT`, `BM_CONTAINER_UID`, `BM_MODEL_CACHE_REL_PATH`, `SSH_CONNECT_TIMEOUT_SECONDS`, `HEALTH_TIMEOUT_SECONDS`, `MIN_LOCAL_PORT`, `MAX_LOCAL_PORT` | `access_mode`, `access_hint`, `require_free_port`, `forward_spec`, `remote`, `remote_compose`, `vm_tailscale_logged_in`, `vm_env`, `manifest_cmd`, `sha256_of` |
| `sb.sh` | `SB_USER_PATTERN`, `SB_LOCAL_NOTES_DIR`(`$REPO_DIR/.local-data/knowledge/basic-memory`, 테스트만 덮어씀), `SB_REMOTE_NOTES_DIR`, `SB_FONTS_REL_DIR`, `SB_GITIGNORE_PENDING` | `require_sb_user`, `require_sb_user_matches_env_file`, `notes_dir_arg`, `in_notes_dir`, `write_notes_file` |

- Produces (source 관계): `vm.sh`는 `common.sh`를, `sb.sh`는 `common.sh`와 `vm.sh`를, `docs.sh`는 `common.sh`를 source한다. 경로는 `"${BASH_SOURCE[0]%/*}/<file>"`이고 그 위에 `# shellcheck source=<file>`를 둔다(`.shellcheckrc`가 `source-path=SCRIPTDIR`).
- Produces (스크립트가 source하는 것): `vm.sh` — backup, status, logs, verify-vm, access-check, tunnel, bootstrap-vm. `vm.sh`와 `sb.sh` — deploy, restore. `sb.sh` — sb-space, sb-fonts, verify-sb. `common.sh` — verify-mcp, review-record, review-bash-guard, 그리고 Task 2 전까지의 check-git, check-pr, review, post-review. `docs.sh` — create-doc.

- [x] **Step 1: 실패하는 테스트 작성**

`tests/lib-vm.bats`: `setup`은 `setup_stubs ssh docker sudo`, `use_vm_env`, `. "$REPO_DIR/scripts/lib/vm.sh"`다. `tests/common.bats`의 테스트 세 개를 이름과 본문 그대로 옮긴다. "remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST", "remote checks BM_ACCESS before it runs ssh, so no VM target reaches the VM with a typo there", "manifest_cmd lists every file's sha256 sorted by path"이다. `tests/common.bats`에는 `mask` 테스트만 남기고, setup은 `common.sh`만 source한다.

`tests/lib-sb.bats`:

```bash
setup() {
  setup_stubs ssh sudo
  use_vm_env
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/notes"
  # shellcheck source=../scripts/lib/sb.sh
  . "$REPO_DIR/scripts/lib/sb.sh"
}

@test "the libraries load in any order and more than once, and common.sh alone holds no VM or SilverBullet settings" {
  run env REPO_DIR=/nowhere bash -c 'set -euo pipefail
    . "$0/scripts/lib/common.sh"
    [[ -z "${BM_CONTAINER_UID+x}${SB_GITIGNORE_PENDING+x}" ]] || { echo "common.sh loaded VM settings"; exit 1; }
    . "$0/scripts/lib/sb.sh"; . "$0/scripts/lib/vm.sh"; . "$0/scripts/lib/common.sh"; . "$0/scripts/lib/sb.sh"
    printf "%s|%s\n" "$REPO_DIR" "$SB_REMOTE_NOTES_DIR"' "$REPO_DIR"
  assert_success
  assert_output "$REPO_DIR|$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
}
```

`env REPO_DIR=/nowhere`는 `common.sh`가 물려받은 값이 아니라 자기 위치에서 `REPO_DIR`를 구하는지 확인한다. 검사에 쓰는 두 상수는 환경 값으로 덮어쓸 수 없는 것을 골랐다. `use_vm_env`가 `BM_REMOTE_*`를 export하기 때문이다.

- [x] **Step 2: 실패 확인**

Run: `make test`
Expected: `lib-vm.bats`와 `lib-sb.bats`의 모든 테스트가 실패한다(`scripts/lib/vm.sh`, `scripts/lib/sb.sh`가 없다). 다른 파일은 통과한다.

- [x] **Step 3: 나누기**

- 위 표대로 정의를 옮긴다. 본문은 바꾸지 않는다. 머리 주석은 `docs.sh:1-8`의 꼴을 따른다(용도 한 줄, bash 3.2 한 줄, `#   name ARGS -> 한 줄` 색인).
- `common.sh`: `REPO_DIR="$(dirname "$(dirname "$COMMON_LIB_DIR")")" || exit 1`과 `readonly REPO_DIR`. 환경의 `REPO_DIR`는 읽지 않는다(테스트가 `REPO_DIR`를 export한다). `SB_LOCAL_NOTES_DIR`는 이 값으로 구하므로, source할 때 하위 셸이 하나 줄어든다(스펙 2.1의 `common.sh:22`).
- `docs.sh:3`의 "Source scripts/lib/common.sh first"를 "Sources common.sh"로 바꾼다. `create-doc.sh`는 `docs.sh`만 source한다.
- 스크립트의 source 줄은 위 Produces대로 바꾼다. 세 스크립트의 `REPO_DIR` 줄을 지운다. 이 세 스크립트에서는 `SCRIPT_DIR`만 남는다.
- `Makefile:60` → `. scripts/lib/sb.sh && require_sb_user`. `Makefile:19,56` 주석의 경로 → `scripts/lib/sb.sh`.
- `tests/backup_restore.bats:32`의 `local_manifest` → `scripts/lib/vm.sh`. `tests/repo.bats:104`가 `HEALTH_TIMEOUT_SECONDS`를 읽는 파일 → `scripts/lib/vm.sh`.
- `docs/ARCHITECTURE.md:43`(`Makefile` + `scripts/` 행) 끝에 "공용 함수는 `scripts/lib/`(common, vm, sb, git, docs)에 있고, 파일마다 첫머리에 함수 색인이 있음"을 더한다. git은 Task 2에서 생긴다.

- [x] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0, 커버리지 80% 이상. 테스트 이름 목록은 Task 전과 같고, `lib-sb.bats`의 새 테스트 하나만 늘어난다. 옮긴 세 테스트는 이름이 같다. Progress log에 적는다.

- [x] **Step 5: 커밋** — `refactor: split scripts/lib into common, vm and sb libraries` (`Task: 1`)

### Task 2: git 도구 라이브러리 (중복 1, 4)

**Files:**
- Create: `scripts/lib/git.sh`, `tests/lib-git.bats`
- Modify: `scripts/check-git.sh`, `scripts/check-pr.sh`, `scripts/review.sh`, `scripts/post-review.sh`

**Interfaces:**
- Consumes: `common.sh`의 `die`, `main_checkout_root DIR`
- Produces (`lib/git.sh`, `common.sh`를 source함):
  - `readonly ASSISTED_BY_PATTERN`, `PLAN_PATTERN`, `TASK_PATTERN`, `FORBIDDEN_TRAILERS`. 값은 `check-git.sh:13-16`에서 그대로 옮긴다.
  - `PROBLEMS=""`, `add_problem MESSAGE...`(지금 본문 그대로), `report_problems HEADING`: `PROBLEMS`가 비어 있으면 아무것도 출력하지 않고 0을 돌려준다. 그렇지 않으면 stderr에 `HEADING:`과 목록을 출력하고 `exit 1`한다.
  - `branch_slug BRANCH` → `/`를 `-`로 바꾼 값.
  - `review_out_dir` → `REVIEW_OUT_DIR`가 있으면 그 값, 없으면 `$(main_checkout_root "$PWD")/.review-out`. main checkout을 찾지 못하면 "cannot find the main checkout from $PWD: run it inside a checkout of this repo, or set REVIEW_OUT_DIR"로 죽는다. 지금처럼 현재 디렉터리의 저장소를 기준으로 한다.
  - `review_report_prefix BRANCH ROUND REVIEWER` → `<review_out_dir>/<branch_slug>-r<ROUND>-<REVIEWER>`.

- [x] **Step 1: 실패하는 테스트 작성 (`tests/lib-git.bats`)**

```bash
setup() {
  # shellcheck source=../scripts/lib/git.sh
  . "$REPO_DIR/scripts/lib/git.sh"
}

@test "report_problems is silent without problems and lists every problem under its heading with exit 1" {
  [[ -z "${BM_CONTAINER_UID+x}" ]] || fail "git.sh must not load the VM settings"
  run report_problems "git policy violations"
  assert_success
  assert_output ""
  add_problem "first"
  add_problem "second"
  run report_problems "git policy violations"
  assert_failure 1
  assert_output "$(printf 'git policy violations:\n  - first\n  - second')"
}

@test "review_report_prefix puts slug, round and reviewer in REVIEW_OUT_DIR, else in the main checkout's .review-out" {
  make_worktree_fixture
  cd "$LINKED_WT"
  REVIEW_OUT_DIR=/tmp/out run review_report_prefix plan/16-script-cleanup 2 codex
  assert_output "/tmp/out/plan-16-script-cleanup-r2-codex"
  unset REVIEW_OUT_DIR
  run review_report_prefix plan/16-script-cleanup 1 claude
  assert_output "$MAIN_REPO/.review-out/plan-16-script-cleanup-r1-claude"
}
```

- [x] **Step 2: 실패 확인** — `make test`. `lib-git.bats` 두 테스트가 실패한다(`git.sh` 없음).

- [x] **Step 3: 구현**

- `check-git.sh`: `git.sh`를 source한다. `:13-16`의 공용 패턴과 `:20-25`를 지운다(`BRANCH_PATTERN`, `GIT_CONFIG_KEY_MISSING`, `POLICY_HINT`는 남긴다). `:93-96` → `report_problems "git policy violations"`. 규칙 위반 `:56`, `:66`에 `|| exit 1`을 붙인다.
- `check-pr.sh`: `git.sh`를 source한다. `:13-15`의 공용 패턴과 `:18-23`을 지운다(`TITLE_PATTERN`, `SESSION_LINK_PATTERN`은 남긴다). `:71-74` → `report_problems "PR rule violations"`. `:44`에 `|| exit 1`을 붙인다.
- `review.sh`: `git.sh`를 source한다. 맨 위의 `MAIN_ROOT`, `OUT_DIR`, `WORKTREE_PARENT`(`:17-19`, 규칙 위반 `readonly X="$(…)"`)를 지우고 `main`에서 구한다. `out_dir="$(review_out_dir)" || exit 1`, 절대 경로 검사 메시지 끝은 "unset it to use the main checkout's .review-out"이다. worktree 부모는 `REVIEW_WORKTREE_PARENT`가 없을 때만 `main_checkout_root "$PWD"`로 구한다. `:164`의 slug → `branch_slug`, `:178-180` → `prefix="$(review_report_prefix "$BRANCH" "$round" "$REVIEWER")" || exit 1`.
- `post-review.sh`: `:13-14`를 지운다. `:49-50` → `prefix="$(review_report_prefix "$branch" "$round" "$reviewer")" || exit 1`.

- [x] **Step 4: 통과 확인** — `make check` exit 0. 테스트 이름 목록에는 `lib-git.bats`의 두 개만 늘어난다.

- [x] **Step 5: 커밋** — `refactor: share the trailer rules and review paths in scripts/lib/git.sh` (`Task: 2`)

### Task 3: VM 사전 점검, 공용 값, 존재 확인 (중복 2, 5, 6, 7과 규칙 위반)

**Files:**
- Modify: `scripts/lib/common.sh`, `scripts/lib/vm.sh`, `scripts/lib/sb.sh`, `backup.sh`, `restore.sh`, `deploy.sh`, `status.sh`, `logs.sh`, `verify-vm.sh`, `access-check.sh`, `tunnel.sh`, `bootstrap-vm.sh`, `sb-space.sh`, `verify-mcp.sh`, `review.sh`, `Makefile:12-13`
- Test: `tests/lib-vm.bats`, `tests/lib-sb.bats`

**Interfaces:**
- Produces (`common.sh`): `readonly DEFAULT_BM_PORT=8737`, `readonly DEFAULT_SB_PORT=3000`, `readonly PARTIAL_SUFFIX=".partial"`, `utc_stamp` → `date -u +%Y%m%dT%H%M%SZ`의 출력.
- Produces (`vm.sh`):
  - `require_vm [CMD...]` → `access_mode`로 `BM_ACCESS`를 확인하고, `require_cmd ssh CMD...`, `require_env BM_VM_HOST BM_VM_USER`를 한다. 출력은 없다. 실패하면 각 함수의 메시지로 죽는다.
  - `remote CMD` → ssh만 실행한다. `access_mode`를 부르지 않는다(P3). 머리 주석에 "callers run require_vm first"를 적는다.
  - `access_hint` → `BM_ACCESS`를 직접 읽지 않고 `mode="$(access_mode)" || return 1`로 읽는다.
  - `remote_compose [--if-deployed] ARGS` → `--if-deployed`가 있으면 `$BM_REMOTE_APP_DIR/compose.yaml`이 있을 때만 실행하고, 없으면 아무것도 하지 않고 성공한다.
  - `exists_cmd PATH` → sh 조각 `if [ -e PATH ]; then echo present; else echo absent; fi`.
  - `remote_exists PATH` → VM에서 `present`나 `absent`를 출력한다. VM이 답하지 않으면 0이 아닌 값으로 끝난다.
  - `vm_env`: 포트 기본값은 `DEFAULT_*`를 쓴다.
- Produces (`sb.sh`): `notes_file_state LOCAL_DIR PATH` → 노트 폴더(`in_notes_dir`)에서 `present`나 `absent`를 출력한다. `notes_dir_arg`의 VM 쪽은 `require_vm`을 부른다.
- Produces (`verify-mcp.sh`): `readonly RESPONSE_PREVIEW_BYTES=300`.

- [x] **Step 1: 실패하는 테스트 작성**

`tests/lib-vm.bats`: 옮겨 온 "remote checks BM_ACCESS …" 테스트를 아래로 바꾼다(P3).

```bash
@test "require_vm stops on an unknown BM_ACCESS, a missing command or missing VM settings, before any ssh" {
  BM_ACCESS=SSH run require_vm
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'SSH')"
  run require_vm no-such-command
  assert_failure
  assert_output --partial "missing command 'no-such-command'"
  BM_VM_USER= run require_vm
  assert_failure
  assert_output --partial "missing env BM_VM_USER"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
  BM_ACCESS=ssh run require_vm
  assert_success
}

@test "remote_exists and remote_compose --if-deployed follow what is on the VM, and remote_exists fails when the VM does not answer" {
  local file="$BM_REMOTE_APP_DIR/compose.yaml"
  run remote_exists "$file"
  assert_success
  assert_output absent
  run remote_compose --if-deployed stop
  assert_success
  run grep -F 'docker ' "$STUB_LOG"
  assert_failure
  touch "$file"
  run remote_exists "$file"
  assert_output present
  run remote_compose --if-deployed stop
  assert_success
  run grep -Fx 'docker compose stop' "$STUB_LOG"
  assert_success
  SSH_STUB_FAIL_MATCH="-e $file" run remote_exists "$file"
  assert_failure
  refute_line absent
}
```

`tests/lib-sb.bats`:

```bash
@test "notes_file_state tells present from absent in the local notes folder" {
  run notes_file_state "$SB_LOCAL_NOTES_DIR" index.md
  assert_success
  assert_output absent
  touch "$SB_LOCAL_NOTES_DIR/index.md"
  run notes_file_state "$SB_LOCAL_NOTES_DIR" index.md
  assert_output present
}
```

- [x] **Step 2: 실패 확인** — `make test`. 새 테스트 세 개가 실패한다(함수 없음, `remote`가 아직 모드를 확인하므로 `require_vm`도 없음).

- [x] **Step 3: 구현** (위치는 `e648d5a` 기준)

| 위치 | 바뀌는 것 |
|---|---|
| `deploy.sh:15-16`, `logs.sh:12-13`, `backup.sh:87-88`, `restore.sh:127-128`, `access-check.sh:68-69` | `require_vm` |
| `status.sh:35-37` | `require_vm` 다음에 `mode="$(access_mode)" \|\| exit 1` |
| `verify-vm.sh:178-180` | `require_vm curl jq nc`, `mode="$(access_mode)" \|\| exit 1`, `require_env BM_VM_PUBLIC_IP` |
| `tunnel.sh:25-26` | `require_vm nc`. 모드 검사(`:22-24`)는 지금처럼 앞에 둔다 |
| `sb.sh`의 `notes_dir_arg` 빈 인자 쪽 | `require_vm` |
| `logs.sh:14`, `backup.sh:98`, `status.sh:43` | 접속 실패 안내를 `$(access_hint)`로 통일(스펙 중복 2) |
| `verify-vm.sh:173`, `bootstrap-vm.sh:73`, `tunnel.sh:32`, `vm.sh`의 `vm_env` | `8737`, `3000` → `DEFAULT_BM_PORT`, `DEFAULT_SB_PORT` |
| `Makefile:12-13` | 위에 주석 "Same defaults as DEFAULT_BM_PORT and DEFAULT_SB_PORT in scripts/lib/common.sh" |
| `verify-vm.sh:20` 주석 | "make tunnel's 18737/13000" → `tunnel.sh`의 `DEFAULT_TUNNEL_MCP_PORT`, `DEFAULT_TUNNEL_WEB_PORT`를 이름으로 가리킨다 |
| `backup.sh:90`, `restore.sh:18`, `verify-mcp.sh:16` | `utc_stamp`. 맨 위의 값은 `X="$(…)" \|\| exit 1` 다음 줄에 `readonly X`. `VERIFY_ID`는 환경 값이 있으면 그 값을 쓴다 |
| `backup.sh:12`, `review.sh:21` | `PARTIAL_SUFFIX` 정의 삭제(common). `backup.sh:101,108`의 `.partial`도 `$PARTIAL_SUFFIX` |
| `verify-mcp.sh:87,89,90,110,113,134` | `head -c "$RESPONSE_PREVIEW_BYTES"` |
| `verify-mcp.sh:183`, `access-check.sh:50,57` | `\|\| exit 1`(규칙 위반) |
| `restore.sh:74`, `restore.sh:144` | `remote_compose --if-deployed "<지금 인자 그대로>"`. 롤백의 `up -d --force-recreate --wait --wait-timeout …` 순서를 지킨다(`backup_restore.bats:389`) |
| `restore.sh:87`, `restore.sh:134` | `remote_exists "$ROOT"`. `report_no_previous_data`의 case는 `present`, `absent`, 실패 시 `unknown` |
| `sb-space.sh:37-38`, `sb-space.sh:47-48` | `notes_file_state`. 표지는 `present`이면 changed, `index.md`는 `absent`이면 쓴다. 실패 메시지는 그대로 |

- [x] **Step 4: 통과 확인**

Run: `make check`. 그리고 Review Focus 2의 점검:

```bash
for f in $(grep -lwE 'remote|remote_compose|remote_exists|in_notes_dir|write_notes_file|vm_tailscale_logged_in' scripts/*.sh); do
  grep -qwE 'require_vm|notes_dir_arg' "$f" || echo "no require_vm: $f"
done
```

Expected: `make check` exit 0. 점검은 두 파일만 출력한다. `scripts/bootstrap-vm.sh`는 `remote/` 경로와 주석의 "remote"에 걸리지만 VM에는 `ssh_public HOST`로 가고 `access_mode`를 스스로 확인한다. `scripts/create-doc.sh`는 "remote-tracking"에 걸린다. 테스트 이름 목록에서는 "remote checks BM_ACCESS …"가 "require_vm stops …"로 바뀌고, 두 개가 늘어난다. Progress log에 적는다.

- [x] **Step 5: 커밋** — `refactor: check the VM settings once and share constants and existence checks` (`Task: 3`)

### Task 4: sb 공간 적용을 함수 하나로 (중복 3, P1, P2)

**Files:**
- Modify: `scripts/lib/sb.sh`, `scripts/deploy.sh`, `scripts/restore.sh`, `Makefile:56-65`, `docs/ARCHITECTURE.md:90`
- Test: `tests/lib-sb.bats`

**Interfaces:**
- Consumes: `notes_dir_arg`, `in_notes_dir`, `SB_GITIGNORE_PENDING`, `REPO_DIR`
- Produces (`sb.sh`): `sb_space_apply WHERE RERUN [RECREATE_CMD...]`
  - `WHERE`: `local`(`SB_LOCAL_NOTES_DIR`, 쓰기 스크립트에 `--local`) 또는 `vm`.
  - `RERUN`: 실패 메시지 끝에 붙는 다음 행동. 예: `run 'make deploy' again`.
  - `RECREATE_CMD`: 노트 `.gitignore`가 바뀌었을 때, 표지를 지우기 전에 실행한다. Basic Memory가 멈춰 있어 시작할 때 `.gitignore`를 읽는 경우(restore)에는 주지 않는다.
  - 순서: `"$REPO_DIR/scripts/sb-space.sh" [--local]` → `changed`가 아니면 끝 → `RECREATE_CMD`(실패하면 "could not recreate Basic Memory to load the new notes .gitignore: RERUN") → 표지 삭제 → 쓰기 다시 → `unchanged`가 아니면 죽는다.
  - 메시지(`where`는 local이면 그 폴더, vm이면 `$BM_VM_HOST:$SB_REMOTE_NOTES_DIR`): "could not write the SilverBullet space files in WHERE: fix the error above, then RERUN", "could not remove $SB_GITIGNORE_PENDING in WHERE: RERUN", "could not write the SilverBullet pages in WHERE: fix the error above, then RERUN", "the notes .gitignore changed again while the pages waited, so they were not written: RERUN".

- [x] **Step 1: 실패하는 테스트 작성 (`tests/lib-sb.bats`, Review Focus 4)**

```bash
@test "sb_space_apply recreates Basic Memory between the .gitignore and the pages, and asks again after a failed recreate" {
  setup_stubs docker
  local page="$SB_LOCAL_NOTES_DIR/Library/agent-hub/agent-hub.md"
  run sb_space_apply local "rerun 'make local-up'" false
  assert_failure
  assert_output --partial "rerun 'make local-up'"
  [[ -e "$SB_LOCAL_NOTES_DIR/.gitignore.pending" && ! -e "$page" ]] \
    || fail "a failed recreate must keep the marker and write no pages"
  run sb_space_apply local "rerun 'make local-up'" docker compose up -d --force-recreate basic-memory
  assert_success
  [[ ! -e "$SB_LOCAL_NOTES_DIR/.gitignore.pending" && -e "$page" ]] \
    || fail "the retry must recreate, remove the marker and write the pages"
  run sb_space_apply local "rerun 'make local-up'" false
  assert_success
  run grep -c '^docker compose up -d --force-recreate basic-memory$' "$STUB_LOG"
  assert_output 1
}
```

- [x] **Step 2: 실패 확인** — `make test`. 이 테스트가 실패한다(`sb_space_apply` 없음).

- [x] **Step 3: 구현**

- `deploy.sh`: compose 업로드 → `.env` → `pull -q` → `sb_space_apply vm "run 'make deploy' again" recreate_basic_memory` → `up -d --wait …`. `recreate_basic_memory`는 deploy.sh의 함수다. `:34-36`의 step, 명령, die를 그대로 옮긴다. 머리 주석(`:2-5`)도 새 순서에 맞춘다.
- `restore.sh`: `write_space_files`(`:105-119`)를 지우고, `:168` → `sb_space_apply vm "rerun 'make restore BACKUP=$archive'"`. die가 rollback trap을 부르는 것은 지금과 같다.
- `Makefile`: `:56-57`(`SB_LOCAL_PENDING`과 그 주석)을 지운다. `:62-65` → `. scripts/lib/sb.sh && sb_space_apply local "rerun 'make local-up'" $(COMPOSE) up -d --wait --force-recreate basic-memory`.
- `docs/ARCHITECTURE.md:90`(배포): "compose와 VM용 `.env` 전송 → `docker compose pull` → 공간 파일 쓰기(노트 `.gitignore`가 바뀌었으면 `.gitignore`만 쓰고 Basic Memory만 다시 만든 뒤 관리 페이지·`index.md` 쓰기) → `up -d --wait`".

- [x] **Step 4: 통과 확인** — `make check` exit 0. `vm_ops.bats:58-90`, `backup_restore.bats:215-252`, `main_checkout.bats:46-63`이 그대로 통과한다. 테스트 이름 목록에는 하나만 늘어난다.

- [x] **Step 5: 커밋** — `refactor: apply the SilverBullet space through one function` (`Task: 4`)

### Task 5: 터널 명령과 포트 확인 하나로 (중복 8, P7)

**Files:**
- Modify: `scripts/lib/vm.sh`, `scripts/verify-vm.sh:71-96`, `scripts/tunnel.sh:30-36`
- Test: `tests/vm_ops.bats:204`(P7의 기대 줄), `tests/access.bats:83`(그대로)

**Interfaces:**
- Produces (`vm.sh`):
  - `local_port_open PORT` → `127.0.0.1:PORT`에 무언가 듣고 있으면 0(`nc -z 127.0.0.1 PORT`, 출력 버림). `require_free_port`와 verify의 준비 확인 반복문이 쓴다.
  - `tunnel_args MCP_LOCAL_PORT WEB_LOCAL_PORT [SSH_OPTION...]` → 전역 배열 `TUNNEL_ARGS`를 ssh 인자로 채운다: `-N -o ExitOnForwardFailure=yes SSH_OPTION... -L "$(forward_spec MCP_LOCAL_PORT "${BM_PORT:-$DEFAULT_BM_PORT}")" -L "$(forward_spec WEB_LOCAL_PORT "${SB_PORT:-$DEFAULT_SB_PORT}")" "$BM_VM_USER@$BM_VM_HOST"`. 실행하지 않는다(P7). 배열은 항상 비어 있지 않으므로 bash 3.2의 빈 배열 문제가 없다.
- `open_verify_tunnel`은 인자를 받지 않는다. 원격 포트는 `tunnel_args`가 읽는다.

- [ ] **Step 1: 실패하는 테스트로 바꾸기** — `tests/vm_ops.bats:204`의 기대 줄을 `ssh -N -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=10 -L 127.0.0.1:28737:127.0.0.1:8737 -L 127.0.0.1:23000:127.0.0.1:3000 ubuntu@agent-hub-iap`로 바꾼다. 옵션 순서만 바뀌고, 옵션 집합과 바인딩은 같다.

- [ ] **Step 2: 실패 확인** — `make test`. "ssh mode: probe checks through a verify tunnel …"만 실패한다.

- [ ] **Step 3: 구현**

- `verify-vm.sh`: `tunnel_args "$VERIFY_TUNNEL_MCP_PORT" "$VERIFY_TUNNEL_WEB_PORT" -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS"` 다음에 `ssh "${TUNNEL_ARGS[@]}" &`와 `tunnel_pid=$!`. 준비 확인(`:88`)은 `local_port_open`. `main`의 `open_verify_tunnel "$port" "$sb_port"` → `open_verify_tunnel`.
- `tunnel.sh`: `cmd` 배열(`:21`, `:30-33`)을 `tunnel_args "$mcp_port" "$web_port" -o "ServerAliveInterval=$SERVER_ALIVE_INTERVAL_SECONDS" -o "ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX"`로 바꾼다. `:34`는 `log "running: ssh ${TUNNEL_ARGS[*]}"`, `:36`은 `ssh "${TUNNEL_ARGS[@]}" || status=$?`. 종료 처리(`:37-39`)는 그대로 둔다.

- [ ] **Step 4: 통과 확인** — `make check` exit 0. 그대로 통과해야 하는 테스트: `access.bats:83`의 make tunnel 줄, `vm_ops.bats:195-231`(터널이 남지 않음, 포트 점유, 실패 뒤 터널 정리). 테스트 이름 목록은 같다.

- [ ] **Step 5: 커밋** — `refactor: build the arguments of both SSH tunnels and the port check in scripts/lib/vm.sh` (`Task: 5`)

### Task 6: 스크립트 이름을 `<동사>-<대상>.sh`로 (스펙 4절 V2)

**Files:**
- Rename (`git mv`): 스펙 4절 표의 13개 — `backup.sh`→`backup-notes.sh`, `restore.sh`→`restore-notes.sh`, `remote/bootstrap.sh`→`remote/provision-vm.sh`, `deploy.sh`→`deploy-stack.sh`, `status.sh`→`show-status.sh`, `logs.sh`→`show-logs.sh`, `sb-space.sh`→`sync-sb-space.sh`, `sb-fonts.sh`→`upload-sb-fonts.sh`, `review.sh`→`review-branch.sh`, `review-record.sh`→`post-review-record.sh`, `review-bash-guard.sh`→`guard-reviewer-bash.sh`, `access-check.sh`→`check-access.sh`, `tunnel.sh`→`open-tunnel.sh`
- Modify: Step 2 명령이 찾는 모든 곳(`e648d5a` 기준 30개 파일, 79줄), 모든 실행 스크립트의 usage 줄, `Makefile:103`의 deploy 설명

- [ ] **Step 1: 실패하는 테스트로 바꾸기** — 테스트 안의 스크립트 경로를 새 이름으로 바꾼다. `vm_ops.bats`, `backup_restore.bats`, `main_checkout.bats`, `access.bats`, `sb_space.bats`, `sb_fonts.bats`, `review.bats`, `review_record.bats`, `review_bash_guard.bats:5`, `bootstrap.bats:11`, `repo.bats:197-198`이다. 테스트 이름에 든 옛 스크립트 이름(`backup_restore.bats:467`의 "a backup made by backup.sh …")은 계획 17이 파일을 나눌 때 바꾼다. `review_bash_guard.bats:29`, `:89`의 `scripts/review.sh`, `scripts/?.sh`는 경로가 아니라 가드에 넣는 입력 문자열이므로 두지 않는다.

- [ ] **Step 2: 실패 확인과 참조 목록**

Run: `make test` → 경로를 바꾼 테스트가 실패한다(파일 없음).

```bash
P='(^|[^-a-z])(backup|restore|deploy|status|logs|sb-space|sb-fonts|review|review-record|review-bash-guard|access-check|tunnel)\.sh|remote/bootstrap\.sh'
git grep -nE "$P" -- . ':!docs/plans/plan-2026-10-0*' ':!docs/plans/plan-2026-10-1[0-5]-*' \
  ':!docs/plans/plan-2026-10-13-*' ':!docs/plans/plan-2026-10-14-*' ':!docs/plans/plan-2026-10-15-*' \
  ':!docs/plans/plan-2026-10-16-*' ':!docs/plans/plan-2026-10-20-16-*' \
  ':!docs/specs' ':!docs/decisions' ':!docs/reviews' ':!docs/research'
```

- [ ] **Step 3: 이름 바꾸기와 참조 고치기**

- `git mv` 13개(Files). 같은 커밋에서는 경로 참조와 usage 줄만 바꾼다.
- 위 명령이 찾은 곳을 모두 고친다. Makefile 레시피, 스크립트 사이의 호출(`sb.sh`의 `sb_space_apply`가 부르는 경로, `bootstrap-vm.sh:66`), 스크립트 주석과 리뷰 프롬프트의 예(`review.sh:112`), `.claude/agents/branch-reviewer.md:12`의 훅 경로, `docs/ARCHITECTURE.md`(44, 46-48, 53, 90, 93행), 스킬(`bm-recover:55`, `branch-review:37`, `skill-authoring:37`), `compose.yaml:2`, `silverbullet/agent-hub.md:3`이다.
- usage 줄: 머리 주석은 `# Usage: …` 한 줄이다. usage로 죽는 메시지도 같은 꼴을 쓴다. Make 타깃이 있으면 사람이 치는 Make 명령으로, 없으면 지금처럼 스크립트 파일 이름(`<name>.sh …`)으로 쓴다(스펙 5절 끝). `tests/verify_mcp.bats:121`이 `usage: verify-mcp.sh`를 확인한다.

| 스크립트 | usage |
|---|---|
| `backup-notes.sh` | `make backup` |
| `restore-notes.sh` | `make restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz` (지금 die와 같음) |
| `deploy-stack.sh` | `make deploy` |
| `show-status.sh`, `show-logs.sh` | `make status`, `make logs` |
| `check-access.sh`, `open-tunnel.sh` | `make access-check`, `make tunnel` |
| `verify-vm.sh` | `make verify`, or `make probe` (read-only). `:176`의 die도 이 꼴 |
| `bootstrap-vm.sh` | `make vm-bootstrap HOST=<public-ip, or the SSH host alias in ssh mode>` (머리 주석을 지금 die 꼴에 맞춤) |
| `upload-sb-fonts.sh` | `make sb-fonts [LOCAL=1]`. `notes_dir_arg`는 첫 인자로 usage 문자열을 받는다: `notes_dir_arg USAGE [--local]` |
| `sync-sb-space.sh` | `sync-sb-space.sh [--local]` |
| `verify-mcp.sh`, `verify-sb.sh` | 그대로(`verify-mcp.sh [--host-header HOST] [--read-only] URL`, `verify-sb.sh [--read-only] URL`) |
| `check-git.sh` | `make check-git`, or `check-git.sh [BASE] [BRANCH]` |
| `check-pr.sh` | `PR_TITLE=<title> PR_BODY=<body> check-pr.sh` |
| `review-branch.sh`, `post-review.sh`, `post-review-record.sh` | 지금 die의 `make review …`, `make review-post …`, `make review-record …` |
| `guard-reviewer-bash.sh` | `the branch-reviewer agent's PreToolUse hook (hook input JSON on stdin)` |
| `create-doc.sh` | 그대로(`make new-doc …`) |
| `remote/provision-vm.sh` | `uploaded and run by make vm-bootstrap (stdin: the Tailscale auth key line)` |

- `Makefile:103`: `deploy: ## Copy compose.yaml, the VM .env and the SilverBullet space files to the VM, then start Basic Memory and SilverBullet (waits until healthy)`.

- [ ] **Step 4: 통과 확인**

Run: `make check`, 그리고 Step 2의 `git grep`.
Expected: `make check` exit 0. `git grep`은 `tests/review_bash_guard.bats:29`만 찾는다. 테스트 이름 목록은 같다. `git log --follow --oneline scripts/backup-notes.sh | head -3`이 옛 커밋까지 보여 준다.

- [ ] **Step 5: 커밋** — `refactor: rename scripts to verb-object names` (`Task: 6`)

### Task 7: 로컬 스택과 VM에서 확인 (P6)

메인 세션에서 사용자와 함께 한다. `.env`는 main checkout에만 있고 Makefile이 거기서 읽는다.

- [ ] **Step 1: 로컬 스택** — `docker ps`로 다른 로컬 스택이 없는지 본다(컨테이너 이름이 고정됨). 그 뒤 `make local-up local-verify local-down`. 이 worktree의 `.local-data/`는 새로 생긴다. `make local-up`이 `sb_space_apply local`을 거쳐 Basic Memory를 한 번 다시 만들고, 두 번째 실행에서는 다시 만들지 않는지 로그로 본다.
- [ ] **Step 2: OK가 필요 없는 VM 확인** — `make access-check probe status logs`, `make backup`(컨테이너를 잠시 멈춘다), `make verify`(테스트 노트를 쓰고 지운다). `make tunnel`은 백그라운드로 열어, `scripts/verify-mcp.sh --read-only http://127.0.0.1:18737/mcp`와 `http://127.0.0.1:13000/.ping`이 응답하는지 본 뒤 닫는다.
- [ ] **Step 3: 사용자 OK 뒤 deploy** — `origin/main`이 움직였으면(PR #10 병합 등) 먼저 `git merge origin/main`을 하고 `make check`를 다시 돌린다. 그다음 `make deploy verify`. 공간 파일이 바뀌지 않았으면 Basic Memory를 다시 만들지 않는다. 관리 페이지만 새 스크립트 이름으로 바뀐다.
- [ ] **Step 4: 기록** — 명령과 결과(IP와 세션 id 없이)를 Progress log에 `Verified`로 적고 커밋한다(`Task: 7`).

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과, Task 7의 확인을 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 계획 17(테스트 정리와 생성 규칙): 테스트 파일 이름 변경과 분할(`common.bats` → `lib-common.bats` 포함), 픽스처 이동, 테스트 도우미와 중복 정리, `.bats` lint, 검사 1~5, `script-authoring` 스킬과 `make new-script`, `AGENTS.md`의 Invariants·Skills·Map(P5).
- 계획 12의 미룬 작은 개선(`make tunnel`의 같은 포트 안내, Ctrl-C INT trap 등)은 이 계획의 범위 밖이다. 계획 12 파일의 Follow-ups에 남아 있다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-20 | Command | `git fetch origin` 뒤 worktree `repo-structure`에서 `git switch -c plan/16-script-cleanup --no-track origin/main`(`e648d5a`). `make new-doc TYPE=plan SLUG=script-cleanup` → 이 파일(번호 16). |
| 2026-10-20 | Verified | 스펙 2.1과 5절의 위치를 `e648d5a`에서 다시 확인했다. 스펙 기준 `87e86d4` 뒤로 스크립트 줄은 바뀌지 않았다. 바뀐 것은 계획 13이 더한 `scripts/lib/docs.sh`(`common.sh`를 source하지 않고 방지 줄이 없음)와 `scripts/create-doc.sh`다. Task 1이 `docs.sh`를 맞춘다. |
| 2026-10-20 | Verified | 참조 목록(Task 6 Step 2의 `git grep`): 30개 파일, 79줄. `Makefile` 12, `tests/vm_ops.bats` 14, `docs/ARCHITECTURE.md` 7, `tests/backup_restore.bats` 5, `scripts/deploy.sh`·`scripts/restore.sh`·`tests/main_checkout.bats` 각 4, `tests/access.bats` 3, `scripts/lib/common.sh`·`scripts/review.sh`·`tests/repo.bats`·`tests/review_bash_guard.bats` 각 2, 나머지 18개 파일 각 1(스킬 3, `.claude/agents/branch-reviewer.md`, `compose.yaml`, `silverbullet/agent-hub.md`, 스크립트 8, 테스트 4). |
| 2026-10-20 | Verified | 사용자 결정: 계획과 Decisions P1~P7대로 진행하고, 실행 방식은 A(Native: 한 세션에서 구현, 끝에 브랜치 전체 리뷰 한 번)로 한다. |
| 2026-10-20 | Verified | 초안 PR #15(draft)를 열었다. Start의 첫 커밋 `5eebe31`에서 `make check` exit 0, 213 ok, 커버리지 94.51%. |
| 2026-10-20 | Verified | Task 1: RED `make test` exit 2(`lib-vm.bats` 3개, `lib-sb.bats` 1개 실패: `scripts/lib/vm.sh`, `sb.sh` 없음). GREEN `make check` exit 0, 214개, not ok 0, 커버리지 94.56%(`common.sh` 100%, `vm.sh` 95.45%, `sb.sh` 93.10%). 테스트 이름 목록: 새 테스트 1개만 늘었고, `common.bats`에서 옮긴 세 개는 이름이 같다. |
| 2026-10-20 | Verified | Task 1 계획 수정: `lib-sb.bats`의 자식 셸을 `bash -c` 대신 임시 스크립트 파일로 실행한다. `make coverage`에서 kcov가 export한 `PS4`가 `BASH_SOURCE`를 읽는데, `bash -c`의 최상위에서는 그 값이 없어 `set -u`로 멈췄다(`BASH_SOURCE: unbound variable`). macOS bash 3.2와 `make test`에서는 통과했다. 검사 내용은 같다. |
| 2026-10-20 | Verified | Task 2: RED `make test` exit 2(`lib-git.bats` 2개 실패: `scripts/lib/git.sh` 없음). GREEN `make check` exit 0, 216개, not ok 0, 커버리지 94.44%. 테스트 이름 목록: `lib-git.bats`의 2개만 늘었다. check-git, check-pr, review, post-review는 `git.sh`를 source하고, review와 post-review의 맨 위 `MAIN_ROOT`·`OUT_DIR`·`WORKTREE_PARENT`(규칙 위반 `readonly X="$(…)"` 포함)는 `main`에서 구한다. |
| 2026-10-20 | Verified | Task 3: RED `make test` exit 2(새 테스트 3개 실패: `require_vm`, `remote_exists`, `notes_file_state` 없음). GREEN `make check` exit 0, 218개, not ok 0, 커버리지 94.55%. 테스트 이름 목록: "remote checks BM_ACCESS …"가 "require_vm stops …"로 바뀌고(P3) 2개가 더 늘었다(`remote_exists …`, `notes_file_state …`). Review Focus 2 점검은 계획대로 `scripts/bootstrap-vm.sh`, `scripts/create-doc.sh`만 출력했다. |
| 2026-10-20 | Verified | Task 3 중 발견: `remote_compose`의 인자 없는 `return`이 restore 롤백(EXIT trap) 안에서 trap 직전 상태(die의 1)를 돌려줘, `backup_restore.bats`의 롤백 테스트 3개(18, 25, 28번)가 실패했다. bash는 trap 핸들러에서 실행된 인자 없는 `return`의 상태를 trap 전 마지막 명령에서 가져온다. if/else로 바꾸고 함수 주석에 이유를 적었다. 기존 롤백 테스트가 회귀를 잡는다. |
| 2026-10-20 | Verified | Task 3 계획 수정: (1) `lib-vm.bats`의 "docker를 부르지 않음" 검사는 `grep '^docker '`로 한다. ssh 스텁 로그 줄에도 원격 명령 글자 `docker compose`가 들어 있기 때문이다. (2) `require_vm` 정의에 `# shellcheck disable=SC2120`과 이유를 둔다(CMD는 선택 인자). (3) `backup.sh`의 `.partial` 네 곳(101, 105, 107, 108행)을 모두 `$PARTIAL_SUFFIX`로 바꿨다. (4) `restore.sh`의 `STAMP`는 주변 전역값처럼 readonly 없이 `\|\| exit 1`만 붙였다. |
| 2026-10-20 | Verified | Task 4: RED `make test` exit 2(`sb_space_apply: command not found`). GREEN `make test` exit 0, 그 뒤 `make check` exit 0, 219개, not ok 0, 커버리지 94.48%. 테스트 이름 목록: 1개만 늘었다. 그대로 둔 `vm_ops.bats`의 deploy 테스트(pull 실패 뒤 재시도, 건강하지 않은 컨테이너 포함), `backup_restore.bats`의 공간 파일 테스트 두 개, `main_checkout.bats`의 local-up 테스트가 통과했다. deploy는 pull 다음에 공간 파일을 쓴다(P2). |
