# 스크립트·테스트 구조와 생성 규칙 — 설계

- 상태: 승인 (2026-10-16). 기준 커밋은 `main` 87e86d4(계획 12 코드 병합)다.
- 구현 계획: 계획 16(스크립트 정리), 계획 17(테스트 정리와 생성 규칙). 번호는 계획을 쓸 때 모든 브랜치를 훑어 다시 확인한다.
- 근거 조사: [여러 코딩 에이전트가 같은 규칙으로 문서·스크립트·테스트를 만들게 하려면](../research/rsch-2026-10-15-agent-repo-conventions.md) §5
- 함께 읽기: [에이전트 공용 문서 체계](spec-2026-10-15-doc-system.md). 구조 검사의 허용 범위(8.4절의 새 ADR)와 생성 명령의 방식을 그 스펙에서 가져온다.
- 대체 범위: [OCI 설계](spec-2026-10-07-basic-memory-oci-tailscale.md) §5의 `scripts/`·`tests/` 배치(78-109행)와 §7.3의 스크립트 규칙 중 이 문서와 겹치는 부분.

## 1. 목적과 범위

어느 에이전트든 새 스크립트와 테스트를 같은 위치, 같은 이름, 같은 골격으로 만들게 한다. 이미 있는 공유 함수를 다시 만들지 않게 하고, 쌓인 중복을 줄인다. 지금은 테스트 파일이 스크립트 하나에 맞춘 것, 여러 스크립트를 묶은 것, 저장소 전체를 보는 것으로 섞여 있고, 스크립트 이름 규칙이 세 가지이며, 같은 코드가 여러 스크립트와 테스트에 복사돼 있다(2절).

**사용자 결정 (2026-10-15)**
1. 테스트와 스크립트의 폴더 구조와 중복을 정리한다.
2. 강제 수준은 문서 체계 스펙과 같은 B다. 템플릿, 작성 스킬, 생성 명령을 두고, 검사는 위치·이름·짝 파일만 본다.
3. 스킬은 이미 정리했으므로 범위 밖이다.

**사용자 결정 (2026-10-15, 초안 검토)**
- E1. A안: `scripts/`와 `tests/`는 평평하게 둔다. 대신 `scripts/lib/`를 관심사별로 나누고, 테스트 파일은 스크립트와 이름으로 1:1 짝을 맞춘다(3절).
- E2. 실행 스크립트 이름을 가능한 한 `<동사>-<대상>.sh`로 통일한다(4절).
- E3. 테스트 파일 이름은 E2를 반영한 스크립트 이름을 하이픈 그대로 쓰고, 저장소 전체를 보는 테스트는 `repo-` 접두어를 붙인다. 기존 파일은 모두 이 규칙으로 바꾼다(6절).
- E4. 계획 12가 병합된 뒤 계획 16, 17 순서로 진행한다(10절). 초안의 추천안을 그대로 둔다.
- E5. 중복 정리는 5절 표의 항목만 한다. 임시 폴더 도우미, 스텁 공통 머리, `remote/bootstrap.sh`의 복사본은 그대로 둔다. 초안의 추천안을 그대로 둔다. 계획 12가 더한 중복(7·8번)은 2026-10-16 갱신 때 같은 기준으로 더했다.
- E6. 라이브러리 함수 이름에 접두어 규칙을 두지 않는다(3절).
- E7. `review.sh`의 계획 리뷰 문구는 문서 체계의 계획 14가 바꾼다.

**사용자 결정 (2026-10-16, E2의 세부)** 초안을 그대로 받았다.
- V1. 동사 목록(4절 표)과 동사마다의 뜻. 계획 12가 더한 두 스크립트 때문에 `open`을 더하고 `check`의 뜻을 넓혔다.
- V2. 스크립트별 새 이름(`backup-notes`, `deploy-stack`, `remote/provision-vm` 등). 계획 12의 `access-check.sh`는 `check-access.sh`, `tunnel.sh`는 `open-tunnel.sh`다.

**범위 밖**
- 문서: 문서 체계 스펙
- 스킬 구조: ADR 0003
- Make 타깃 이름: 사람이 치는 명령이므로 바꾸지 않는다.
- CI 워크플로 구조, 테스트 이미지 교체, bats·kcov 버전 변경. 단, `.bats` lint를 위해 shfmt를 올려야 하면 이미지 고정 규칙에 따라 올린다(7.4절).
- 기능 변경. 정리는 동작을 바꾸지 않는다.

**완료 조건**
1. 실행 스크립트마다 이름이 짝인 bats 파일이 있고, 짝이 없는 bats 파일은 `repo-*.bats`뿐이다. 검사가 이를 확인한다.
2. `scripts/lib/`가 관심사별 파일로 나뉘고, 파일마다 첫머리에 함수 색인이 있다.
3. 5절 표의 중복이 각각 한 곳으로 모인다.
4. 같은 동작을 두 번 검사하거나 ADR 0004에 어긋나는 테스트를 정리한다.
5. `script-authoring` 스킬, 템플릿 두 개, `make new-script`가 있다.
6. `.bats` 파일도 shellcheck와 shfmt로 검사한다.
7. `make check`가 통과하고 커버리지는 80% 이상을 유지한다.

## 2. 근거가 된 사실 (2026-10-16, `main` 87e86d4)

### 2.1 스크립트

**Verified**
- `scripts/`에는 실행 스크립트 19개, `scripts/remote/bootstrap.sh`, `scripts/lib/common.sh`(224행, source 전용)가 있다. 20개 실행 스크립트는 모두 `main "$@"` 구조다.
- 관심사별로 묶으면 다음과 같다.
  - VM 준비: `bootstrap-vm.sh`, `remote/bootstrap.sh`
  - VM 접속: `access-check.sh`(이 네트워크에서 어느 접속 방식이 되는지 한 번 점검하고 추천, 아무것도 바꾸지 않음), `tunnel.sh`(`ssh` 모드에서 MCP와 웹 UI 포트를 포그라운드 `ssh -N -L`로 127.0.0.1에 연결)
  - VM 운영: `deploy.sh`, `status.sh`, `logs.sh`, `verify-vm.sh`(`ssh` 모드에서는 자체 임시 터널도 연다)
  - 데이터: `backup.sh`, `restore.sh`
  - 웹 UI: `sb-space.sh`, `sb-fonts.sh`, `verify-sb.sh`
  - 엔드포인트 검증: `verify-mcp.sh`(로컬과 `verify-vm.sh`가 함께 씀)
  - git·PR·리뷰 도구: `check-git.sh`, `check-pr.sh`, `review.sh`, `post-review.sh`, `review-record.sh`, `review-bash-guard.sh`
- 이름 규칙이 세 가지다. 동사-대상(`check-git`, `verify-mcp`, `post-review`, `bootstrap-vm`), 구성 요소-대상(`sb-space`, `review-record`), 동사나 명사 하나(`deploy`, `backup`, `logs`)다. Make 타깃과 이름이 뒤집힌 곳이 둘 있다: `vm-bootstrap` → `bootstrap-vm.sh`(`Makefile:97-98`), `review-post` → `post-review.sh`(`Makefile:91-92`). 계획 12의 `access-check.sh`는 동사가 뒤에 오고, `tunnel.sh`는 명사 하나다.
- `common.sh`에 핵심 도우미(log, step, die, require_cmd, require_env, mask)와 VM·SilverBullet·접속 방식 상수와 함수가 함께 있다. 계획 12가 `access_mode`, `access_hint`, `require_free_port`, `forward_spec`, `vm_tailscale_logged_in`을 더했다. git 도구 여섯 개는 log, die, step, require_cmd만 쓰는데도 VM 상수를 함께 읽는다. `common.sh:22`는 source할 때 하위 셸을 실행한다.
- `remote/bootstrap.sh`는 혼자 VM에 올라가 실행되므로 `common.sh`를 source할 수 없다(`bootstrap-vm.sh:60-79`). 그래서 log, die, 상수, 접속 방식 확인이 복사돼 있다.
- 규칙 위반:
  - 명령 치환 뒤 `|| exit 1`이 빠짐: `verify-mcp.sh:183`, `check-git.sh:56`, `check-git.sh:66`, `check-pr.sh:44`, `access-check.sh:50`, `access-check.sh:57`
  - `readonly X="$(...)"`가 실패를 가림: `review.sh:19`, `verify-mcp.sh:16`
  - 같은 숫자의 반복: `head -c 300`이 `verify-mcp.sh`에 여섯 번
  - usage 줄 형식이 두 가지(`usage: make …`, `usage: <script>`)이고, `backup`, `deploy`, `logs`, `status`, `access-check`, `tunnel`에는 usage 줄이 없음. `verify-vm.sh:176`은 Make 타깃이 있는데도 스크립트 형식이다.
  - `Makefile:100`의 deploy 설명이 SilverBullet을 빠뜨림
- 중복은 5절 표에 위치와 함께 정리했다.

### 2.2 테스트

**Verified**
- bats 파일 20개, 테스트 199개, 2,846행이다. `make test`는 `bats tests`로 최상위 파일만 실행한다(`Makefile:46-47`). 커버리지는 kcov가 `scripts/`를 대상으로 재고(`tools/coverage.sh:11`), 실행 권한이 있는 모든 스크립트가 어떤 테스트에서든 한 번은 실행돼야 한다(`tools/coverage.sh:20-29`).
- 파일과 스크립트의 대응이 세 가지로 섞여 있다.
  - 스크립트 하나: `check_git.bats`, `verify_mcp.bats`, `sb_space.bats` 등. 하이픈을 밑줄로 바꿨다.
  - 여러 스크립트: `vm_ops.bats`(deploy, verify-vm, status, logs), `backup_restore.bats`, `bootstrap.bats`(`bootstrap-vm.sh`와 `remote/bootstrap.sh`), `access.bats`(access-check 4개, tunnel 2개, logs 1개)
  - 저장소 전체: `repo.bats`, `skills.bats`, `cloud_neutral.bats`, `github.bats`. `main_checkout.bats`는 Makefile(27-77행), 백업(81-111행), 스킬 문서 grep(115-119행)을 함께 담는다.
- `tests/helpers.bash`의 함수 가운데 `setup_stubs`는 13개 파일이, `use_vm_env`는 8개 파일이 쓴다.
- 테스트 중복:
  - 임시 git 저장소 만들기가 같다: `check_git.bats:5-10`, `review.bats:6-11`
  - MCP 기록 응답 설정이 같다: `verify_mcp.bats:6-9`, `vm_ops.bats:9-10`
  - 그 자리에서 만든 가짜 명령이 다섯 곳 있다. `backup_restore.bats:106-109`는 같은 파일 138-143행의 함수를 복사했다.
  - "스텁이 불리지 않았다"는 검사가 18곳 이상, "저장소 파일과 같다"(`run diff`)가 10곳 이상, "로그 순서" 검사가 네 곳 있다.
- 같은 동작을 두 번 검사하는 곳:
  - `vm_env`: `vm_ops.bats:40-45`, `backup_restore.bats:209-212`
  - 매니페스트 형식: `common.bats:37-46`, `backup_restore.bats:58-59`
  - `mask`: `common.bats:11-16`, `bootstrap.bats:135`, `verify_mcp.bats:28-32`
  - 공간 파일 쓰기: `sb_space.bats:69-74`, `vm_ops.bats:48-51`, `backup_restore.bats:226-229`
  - make의 `SB_USER` 처리: `verify_sb.bats:72-84`, `main_checkout.bats:46-63`
- 입력만 다른 테스트(ADR 0004 결정 3): 복원이 위험한 아카이브를 거부하는 경우(`backup_restore.bats:286-298`, `300-316`), 백업이 실패해도 컨테이너를 다시 켜는 경우(94-103, 126-135, 177-186행).
- ADR 0004 결정 2에 어긋나는 테스트:
  - `main_checkout.bats:115-119`: 스킬 문서의 문장을 grep한다.
  - `skills.bats:155-160`: 특정 스킬 세 개가 있는지 확인한다. ADR 0003 결정 7의 검사 목록에 없다.
- 남은 흔적:
  - 낡은 주석: `main_checkout.bats:12-13`이 이제 없는 `tests/repo.bats:65-66`을 가리킨다.
  - 아무 테스트도 쓰지 않는 스텁 옵션: `CLAUDE_STUB_EXIT`, `GH_STUB_EXIT`, `FREE_STUB_AVAILABLE_MB`. 마지막 것은 계획 06이 범위 밖이라 남겼다(계획 06, 198행). 계획 12가 더한 스텁 옵션은 모두 쓰인다.
- lint는 `*.sh`, `*.bash`, `tests/stubs/*`만 본다(`Makefile:29`). `.bats` 파일은 shellcheck와 shfmt를 거치지 않는다.

### 2.3 앞선 계획과의 관계

- 계획 11(PR #6, `4c84dba`)과 계획 12의 코드(PR #8, `87e86d4`)는 병합됐다. 이 스펙의 사실은 그 뒤의 `main`에서 다시 확인했다.
- 계획 12의 남은 Task 8(VM 이전)은 결과 PR에서 계획 파일, ADR 0006, 접속 방식 설계, 런북만 고친다(계획 12의 Task 8 Files). 스크립트와 테스트는 바꾸지 않는다.

### 2.4 앞선 결정

- OCI 설계 §5는 평평한 `scripts/`와 `lib/common.sh`, 그 함수 계약을 정했다(78-109행, 94행). `remote/bootstrap.sh`는 로컬에서 단위 테스트한다(96행). §9는 실행 스크립트마다 테스트에서 실행되게 했다(288행).
- ADR 0003 결정 7: 작성 스킬, 템플릿, 검사 테스트를 한 묶음으로 둔다. 이 스펙의 생성 규칙이 같은 모양을 따른다.
- ADR 0004: 남길 테스트와 새로 쓰지 않을 테스트를 정했다(18-31행). 계획 06이 이 기준으로 테스트를 한 번 줄였다.

## 3. 배치 (E1)

| 안 | 모양 | 장점 | 단점 |
|---|---|---|---|
| **A. 평평하게 두고 lib만 나눔 (추천)** | `scripts/<name>.sh`, `scripts/remote/`, `scripts/lib/<관심사>.sh`. `tests/<짝 이름>.bats` | 경로 깊이에 기대는 코드(`common.sh:22`의 `REPO_DIR`, 스크립트 세 곳의 `REPO_DIR`, shellcheck `source=`)와 `bats tests`, kcov 설정이 그대로다. rbenv, kubernetes `hack/`, bats-core, asdf가 같은 방식이다 | 파일 수가 늘면 목록이 길어진다 |
| B. 관심사별 하위 폴더 | `scripts/{vm,data,web,git}/`, `tests/scripts/...` | 폴더만 봐도 묶음이 보인다 | Makefile 약 20행, CI 2행, 훅 경로와 그 검사, 테스트 약 45곳, 깊이에 기대는 코드를 모두 고쳐야 한다. `bats -r`이 필요하고 `setup_suite` 위치가 실행 순서에 따라 달라진다 |
| C. 모든 스크립트를 Make 타깃 이름으로 바꿈 | `scripts/<target>.sh` 하나씩, git 도구는 `scripts/dev/` | 이름 규칙이 하나가 된다 | 다른 스크립트나 CI가 부르는 스크립트(verify-mcp, sb-space, check-pr)에는 타깃이 없어 규칙이 여전히 둘이다. 바뀌는 곳은 B와 비슷하다 |

**결정한 배치**

```text
scripts/
  <name>.sh              실행 스크립트(실행 권한). 이름 규칙은 4절
  remote/<name>.sh       VM에 올려 실행. 혼자 동작하므로 lib/를 source하지 않는다
  lib/common.sh          핵심: log, step, die, require_cmd, require_env, mask, REPO_DIR, 공용 상수
  lib/vm.sh              VM 접속과 원격 실행: remote, remote_compose, vm_env, require_vm, notes_dir_arg, manifest_cmd, sha256_of, remote_exists,
                         접속 방식(access_mode, access_hint, require_free_port, forward_spec, vm_tailscale_logged_in, ssh 옵션 생성)
  lib/sb.sh              SilverBullet: SB 상수, require_sb_user 계열, in_notes_dir, write_notes_file, sb_space_apply
  lib/git.sh             git·PR·리뷰 도구: 트레일러 패턴, add_problem, report_problems, review_out_dir
tests/
  <name>.bats            scripts/<name>.sh 의 짝
  remote-<name>.bats     scripts/remote/<name>.sh 의 짝
  lib-<name>.bats        scripts/lib/<name>.sh 의 짝
  repo-<topic>.bats      저장소 전체 규칙(짝 없음)
  helpers.bash           공용 도우미
  stubs/<command>        외부 명령 하나당 가짜 실행 파일 하나
  fixtures/<name>/       그 짝 테스트가 쓰는 기록 데이터
```

- 함수의 정확한 소속은 계획 16이 정한다. 위 목록은 2절의 사용처를 기준으로 한 초안이다. `main_checkout_root`는 `backup.sh`와 리뷰 도구가 함께 쓰므로 `common.sh`에 둔다.
- 관심사 라이브러리(`vm.sh`, `sb.sh`, `git.sh`)는 맨 위에서 `common.sh`를 source하고, bash 3.2에서 동작하는 이중 source 방지 줄(`[ -n "${_BM_LIB_VM:-}" ] && return 0`)을 둔다. 스크립트는 필요한 라이브러리만 source한다. kubernetes `hack/lib`이 쓰는 방식이다(근거 조사 §5).
- 라이브러리 파일마다 첫머리 주석에 함수 색인(이름과 한 줄 설명)을 둔다. 에이전트는 새 도우미를 쓰기 전에 이 색인을 읽는다. 함수 이름에 접두어 규칙은 두지 않는다. 기존 이름을 모두 바꾸는 비용에 비해 얻는 것이 적고, 파일 위치와 색인이 같은 역할을 한다.
- `AGENTS.md` Invariants의 "source `scripts/lib/common.sh`"는 "`scripts/lib/common.sh`나 그것을 source하는 `scripts/lib/` 라이브러리를 source한다"로 바뀐다. `remote/`는 예외라고 적는다.

## 4. 스크립트 이름 (E2)

실행 스크립트(`scripts/*.sh`, `scripts/remote/*.sh`)는 모두 `<동사>-<대상>.sh`로 쓴다. 동사는 아래 목록에서 고르고, 대상은 `[a-z0-9]+(-[a-z0-9]+)*`다. 라이브러리(`scripts/lib/*.sh`)는 동작이 아니라 주제를 담으므로 `<주제>.sh`(예: `vm.sh`)로 쓴다. Make 타깃 이름은 사람이 치는 명령이므로 바꾸지 않는다. 그래서 타깃과 스크립트 이름이 다를 수 있고, 둘의 대응은 `Makefile`이 정본이다.

**동사 목록 (V1)** — `script-authoring` 스킬에 같은 표를 두고, 검사가 그 표를 읽는다(9절). 새 동사가 필요하면 표에 행을 더한다.

| 동사 | 뜻 | 예 |
|---|---|---|
| bootstrap | 새 VM을 처음 쓸 수 있게 준비한다(로컬에서 실행) | `bootstrap-vm` |
| provision | VM 안에서 패키지와 서비스를 설치한다 | `remote/provision-vm` |
| deploy | 서비스를 배포하거나 다시 띄운다 | `deploy-stack` |
| backup | 데이터를 내려받아 보관한다 | `backup-notes` |
| restore | 보관본으로 되돌린다 | `restore-notes` |
| show | 상태나 로그를 출력만 하고 바꾸지 않는다 | `show-status`, `show-logs` |
| verify | 실행 중인 서비스를 끝에서 끝까지 확인한다 | `verify-mcp`, `verify-sb`, `verify-vm` |
| check | 규칙이나 환경을 점검하고 결과만 알린다. 아무것도 바꾸지 않는다 | `check-git`, `check-pr`, `check-access` |
| open | 연결을 포그라운드로 열어 두고, 끝나면 그 종료 코드로 끝난다 | `open-tunnel` |
| sync | 파일을 원하는 상태로 맞춘다. 여러 번 실행해도 결과가 같다 | `sync-sb-space` |
| upload | 만든 파일을 VM에 올린다 | `upload-sb-fonts` |
| review | 리뷰를 실행한다 | `review-branch` |
| post | PR에 게시한다 | `post-review`, `post-review-record` |
| guard | 훅에서 명령을 걸러 낸다 | `guard-reviewer-bash` |
| create | 템플릿에서 파일을 만든다 | `create-doc`, `create-script` |

**이름 변경 (V2)**

| 지금 | 바뀐 뒤 | 부르는 곳(그대로) |
|---|---|---|
| `backup.sh` | `backup-notes.sh` | `make backup` |
| `restore.sh` | `restore-notes.sh` | `make restore` |
| `remote/bootstrap.sh` | `remote/provision-vm.sh` | `bootstrap-vm.sh`가 VM에 올려 실행 |
| `deploy.sh` | `deploy-stack.sh` | `make deploy` |
| `status.sh` | `show-status.sh` | `make status` |
| `logs.sh` | `show-logs.sh` | `make logs` |
| `sb-space.sh` | `sync-sb-space.sh` | `make local-up`, `deploy`, `restore` |
| `sb-fonts.sh` | `upload-sb-fonts.sh` | `make sb-fonts` |
| `review.sh` | `review-branch.sh` | `make review` |
| `review-record.sh` | `post-review-record.sh` | `make review-record` |
| `review-bash-guard.sh` | `guard-reviewer-bash.sh` | 리뷰어 에이전트 훅(`.claude/agents/branch-reviewer.md:12`) |
| `access-check.sh` | `check-access.sh` | `make access-check` |
| `tunnel.sh` | `open-tunnel.sh` | `make tunnel` |
| `bootstrap-vm.sh`, `verify-vm.sh`, `verify-mcp.sh`, `verify-sb.sh`, `check-git.sh`, `check-pr.sh`, `post-review.sh` | 그대로(이미 맞음) | |
| 새 스크립트 | `create-doc.sh`(문서 체계 계획 13), `create-script.sh`(계획 17) | `make new-doc`, `make new-script` |

- 원격 스크립트를 `provision-vm`으로 부르는 이유: 로컬의 `bootstrap-vm.sh`와 같은 이름이면 "bootstrap-vm을 고쳐라"가 두 파일을 가리키게 된다. VM 안에서 하는 일(스왑, Docker, Tailscale 설치)은 provision이 정확하다.
- CI(`pr-rules.yml`)가 부르는 `check-git.sh`, `check-pr.sh`는 이름이 그대로다.
- 이름을 바꾸면 고칠 곳: `Makefile`, 다른 스크립트의 호출(`deploy`·`restore` → `sync-sb-space`, `bootstrap-vm` → `remote/provision-vm`), 리뷰어 훅 경로와 그 검사(`tests/repo.bats:180-181`), 짝 테스트, 계속 고치는 문서(`AGENTS.md`, `README.md`, ARCHITECTURE, 런북, 스킬). 기록 문서(완료 계획, 스펙, ADR)의 옛 스크립트 이름은 그때의 실제 이름이므로 그대로 둔다.

## 5. 공유 라이브러리와 중복 정리 (E5)

| # | 중복 | 위치(2026-10-16) | 정리 | 위험 |
|---|---|---|---|---|
| 1 | 트레일러 패턴, `add_problem`, 문제 보고 | `check-git.sh:13-16,22-25,93-96`, `check-pr.sh:13-15,20-23,71-74` | `lib/git.sh`로 모은다. 두 스크립트의 규칙이 따로 바뀌지 않게 된다 | 낮음 |
| 2 | VM 사전 점검(`require_cmd ssh` + `require_env BM_VM_HOST BM_VM_USER`)과 접속 실패 안내 | `deploy.sh:15-16,21`, `logs.sh:12-13`, `status.sh:36-37,40,43`, `backup.sh:87-88`, `restore.sh:127-128,135`, `common.sh:177-178`, `access-check.sh:68-69`, `tunnel.sh:25-26`, `verify-vm.sh:179-180` | `lib/vm.sh`의 `require_vm` 하나로 모은다. 안내는 이미 있는 `access_hint`(`common.sh:105`)로 통일한다. 지금 `logs.sh`와 `backup.sh`는 안내를 쓰지 않고, `status.sh:43`은 자기 문구를 쓴다 | 낮음 |
| 3 | sb-space 적용 순서(바뀌었는가 → 재생성 → 표지 삭제 → 재실행 → 변화 없음 확인) | `Makefile:62-65`, `deploy.sh:29-43`, `restore.sh:110-118` | `lib/sb.sh`의 함수 하나로 모으고, Makefile은 스크립트를 한 줄로 부른다 | 중간. `vm_ops.bats:58-90`, `backup_restore.bats:215-252`, `main_checkout.bats:46-63`이 덮는다 |
| 4 | main checkout 루트, 리뷰 출력 폴더, 브랜치 접두어 | `review.sh:17-18,164,178-180`, `post-review.sh:13-14,49-51` | `main_checkout_root`(`common.sh:220`)를 다시 쓰고, 출력 폴더와 접두어는 `lib/git.sh`로 | 낮음 |
| 5 | 같은 값의 반복 | 포트 8737·3000(`Makefile:12-13`, `common.sh:165,168`, `bootstrap-vm.sh:73`, `tunnel.sh:32`, `verify-vm.sh:173`), `make tunnel`의 18737·13000을 되풀이하는 주석(`verify-vm.sh:20`), UTC 시각 형식(`backup.sh:90`, `restore.sh:18`, `verify-mcp.sh:16`), `PARTIAL_SUFFIX`(`backup.sh:12`, `review.sh:21`), 응답 미리보기 길이(`verify-mcp.sh`의 `head -c 300` 여섯 번) | 이름 붙은 상수와 `utc_stamp` 함수로 모은다. 주석은 상수 이름을 가리킨다. `remote/bootstrap.sh`는 자기 상수를 유지한다 | 낮음 |
| 6 | 원격 파일 존재 확인, 가드가 붙은 compose 호출 | `restore.sh:74,87,134,144`, `sb-space.sh:37,47` | `lib/vm.sh`의 `remote_exists`로 모으고 `remote_compose`가 가드를 받게 한다 | 낮음~중간 |
| 7 | 접속 방식 읽기 | `mode="$(access_mode)" \|\| exit 1`이 다섯 곳(`access-check.sh:46`, `bootstrap-vm.sh:48`, `status.sh:35`, `tunnel.sh:22`, `verify-vm.sh:178`), `remote()`가 다시 읽음(`common.sh:136-138`), `access_hint`는 `access_mode`를 거치지 않고 `BM_ACCESS`를 직접 읽음(`common.sh:105-106`) | 2번의 `require_vm`이 모드를 확인하고, `access_hint`는 `access_mode`를 쓴다. 모드가 필요한 스크립트만 값을 받는다 | 낮음 |
| 8 | ssh 옵션과 포트 열림 확인 | ssh 옵션 네 벌(`common.sh:138`, `verify-vm.sh:80-82`, `tunnel.sh:30-33`, `bootstrap-vm.sh:15`), `nc -z 127.0.0.1` 두 곳(`common.sh:123`, `verify-vm.sh:88`) | 두 터널(`verify-vm`의 임시 터널, `make tunnel`)은 `lib/vm.sh`의 명령 생성 함수 하나를 쓰고 차이(BatchMode, ServerAlive)는 인자로 준다. 포트 확인도 함수 하나로 | 중간. verify 터널의 포트 점유 판정(계획 12 리뷰 R1-F1)이 걸려 있다. `vm_ops.bats`와 `access.bats`가 덮는다 |

- 하지 않는 것:
  - 임시 폴더 + `trap` 도우미: 네 곳뿐이고 trap 순서를 잘못 합치면 정리 코드가 사라질 위험이 있다.
  - `remote/bootstrap.sh`의 복사본: 혼자 업로드되는 파일에 라이브러리를 이어 붙이면 업로드 경로가 바뀐다. 보안에 민감한 경로이므로 예외로 문서화한다.
- 함께 고치는 규칙 위반: 2.1절의 `|| exit 1` 여섯 곳, `readonly X="$(...)"` 두 곳, usage 줄(사람이 실제로 실행하는 형태, 즉 Make 타깃이 있으면 `usage: make <target> …`), `Makefile:100`의 설명.
- 줄 번호는 87e86d4 기준이다. 계획 16이 시작할 때 `git grep`으로 위치를 다시 만든다.

## 6. 테스트 배치와 이름 (E3)

| 대상 | 테스트 파일 | 예 |
|---|---|---|
| `scripts/<name>.sh` | `tests/<name>.bats` | `check-git.bats`, `deploy-stack.bats`, `verify-vm.bats` |
| `scripts/remote/<name>.sh` | `tests/remote-<name>.bats` | `remote-provision-vm.bats` |
| `scripts/lib/<name>.sh` | `tests/lib-<name>.bats` | `lib-common.bats`, `lib-vm.bats` |
| 저장소 전체 규칙 | `tests/repo-<topic>.bats` | `repo-docs.bats`, `repo-skills.bats`, `repo-make.bats` |

- 이름은 스크립트 이름을 하이픈 그대로 쓴다. 변환 규칙이 없어야 에이전트가 틀리지 않는다.
- 평평하게 두는 이유: `bats`는 `-r` 없이는 하위 폴더를 실행하지 않고, `setup_suite.bash`는 처음 실행되는 파일의 폴더에서만 찾는다. `helpers.bash`의 `REPO_DIR`(`helpers.bash:6`)도 테스트 파일이 `tests/` 바로 아래에 있다고 가정한다. 하위 폴더의 이점은 이름 짝으로도 얻는다(근거 조사 §5).
- 기존 파일의 이동:

| 지금 | 바뀐 뒤 |
|---|---|
| `vm_ops.bats` | `deploy-stack.bats`, `verify-vm.bats`, `show-status.bats`, `show-logs.bats` |
| `backup_restore.bats` | `backup-notes.bats`, `restore-notes.bats` |
| `bootstrap.bats` | `bootstrap-vm.bats`, `remote-provision-vm.bats` |
| `common.bats` | `lib-common.bats`(+ 새 `lib-vm.bats`, `lib-sb.bats`, `lib-git.bats`) |
| `check_git.bats`, `check_pr.bats`, `verify_mcp.bats`, `verify_sb.bats`, `post_review.bats` | `check-git.bats`, `check-pr.bats`, `verify-mcp.bats`, `verify-sb.bats`, `post-review.bats` |
| `sb_space.bats`, `sb_fonts.bats` | `sync-sb-space.bats`, `upload-sb-fonts.bats` |
| `review.bats`, `review_record.bats`, `review_bash_guard.bats` | `review-branch.bats`, `post-review-record.bats`, `guard-reviewer-bash.bats` |
| `repo.bats` | 주제별 `repo-scripts.bats`(strict mode, bash 3.2), `repo-make.bats`(Makefile), `repo-config.bats`(compose, `.env`, `CLAUDE.md`, `.gemini/settings.json`, 리뷰어 에이전트), `repo-docs.bats`(링크, 경로, 문서 체계 검사) |
| `skills.bats`, `github.bats`, `cloud_neutral.bats` | `repo-skills.bats`, `repo-github.bats`, `repo-cloud-neutral.bats` |
| `main_checkout.bats` | Makefile 부분은 `repo-make.bats`, 백업 부분은 `backup-notes.bats`, 스킬 문서 grep은 삭제 |
| `access.bats` | `check-access.bats`(access-check 4개), `open-tunnel.bats`(tunnel 2개). "모드를 읽지 않는 VM 타깃도 모르는 `BM_ACCESS`에서 멈춘다"(logs로 확인)는 `show-logs.bats` |

- 픽스처는 쓰는 테스트의 짝 이름 폴더에 둔다: `fixtures/mcp-json/`, `fixtures/mcp-sse/` → `fixtures/verify-mcp/json/`, `fixtures/verify-mcp/sse/`, `fixtures/os-release` → `fixtures/remote-provision-vm/os-release`. 다른 짝의 픽스처를 쓸 때(`vm_ops.bats:9-10`처럼 `verify-vm`이 MCP 응답 두 벌을 쓰는 경우)는 도우미를 통한다.
- 스텁은 지금처럼 `tests/stubs/<command>`에 외부 명령 하나당 하나를 둔다. 아무 테스트도 쓰지 않는 옵션 세 개(2.2절)는 지운다. 스텁마다 있는 세 줄 머리(shebang, `set -euo pipefail`, 로그 한 줄)는 공통화하지 않는다. `setup_stubs`는 스텁을 심볼릭 링크로 PATH에 올리므로(`helpers.bash:10-20`), 스텁이 공용 파일을 읽으려면 링크를 따라 실제 위치를 찾아야 한다. 그 복잡도에 비해 얻는 것은 파일당 세 줄이다.

## 7. 테스트 도우미와 중복 정리

### 7.1 `helpers.bash`에 더할 도우미

| 도우미 | 대신하는 것 |
|---|---|
| `init_git_repo`, `agent_commit` | `check_git.bats:5-20`, `review.bats:6-22`의 같은 코드 |
| `use_mcp_fixtures` | `verify_mcp.bats:6-9`, `vm_ops.bats:8-10` |
| `fake_cmd NAME BODY` | 그 자리에서 만든 가짜 명령 다섯 곳 |
| `assert_stub_called`, `refute_stub_called`, `assert_log_order` | 스텁 로그 grep과 awk 순서 검사 |
| `assert_same_file` | `run diff`로 저장소 파일과 비교하는 곳 |

### 7.2 같은 동작은 한 번만

- 2.2절의 두 번 검사하는 곳은 그 함수가 사는 라이브러리의 짝 테스트(`lib-*.bats`)에 하나만 남긴다. 스크립트 테스트에서는 그 함수를 부른다는 사실만 본다.
- 입력만 다른 테스트는 반복문 하나로 합친다(ADR 0004 결정 3).
- 계획 06의 규칙(계획 06, 41-42행)을 따른다. 테스트를 합칠 때 입력과 단언을 모두 옮기고, 고아가 된 도우미는 지운다.

### 7.3 ADR 0004에 맞춤

- 삭제: `main_checkout.bats:115-119`(문서 문장 grep), `skills.bats:155-160`(특정 스킬의 존재. ADR 0003 결정 7의 목록 밖).
- 유지(계획 06이 일부러 남김): `cloud_neutral.bats:17-25`(검사 도우미 자체), `review.bats:177`(리뷰어 허용 목록 보호).
- 유지(보안 불변식): `repo.bats:172-184`(리뷰어 에이전트가 파일을 고칠 수 없음).
- 정리: 낡은 주석 `main_checkout.bats:12-13`, 복사본 `backup_restore.bats:106-109`, `bootstrap.bats`에서 열 번 반복되는 `setup_stubs docker`(setup으로 옮김).

### 7.4 `.bats` lint

- `Makefile`의 `SH_FILES`에 `*.bats`를 더한다. `.editorconfig`에 `[*.bats]` 절을 두고 shfmt의 `language_dialect = bats`를 지정한다. `make lint`는 shfmt에 서식 옵션을 주지 않으므로 `.editorconfig`를 읽는다.
- **Assumption:** 지금 고정한 shfmt v3.12.0과 shellcheck v0.11.0이 bats 파일을 처리한다. 계획 17의 첫 Step이 확인한다. shfmt가 처리하지 못하면 릴리스 노트를 읽고 고정 버전을 올린다(`AGENTS.md`의 이미지 고정 규칙).

## 8. 생성 규칙과 템플릿

### 8.1 `script-authoring` 스킬

- `.agents/skills/script-authoring/SKILL.md`(영어), `assets/script.sh`, `assets/test.bats`, `.claude/skills/script-authoring` 링크.
- 내용:
  - 위치와 이름(3절, 4절, 6절). 4절의 동사 표는 이 스킬에만 둔다. 스펙의 표는 처음 값이고, 이후 정본은 스킬이다.
  - 어떤 라이브러리를 source하는지, 도우미를 쓰기 전에 라이브러리 색인을 읽을 것
  - 테스트 먼저, 스텁과 픽스처의 자리
  - ADR 0004의 "쓰지 않는 테스트"
  - Make 타깃을 더하는 법(`##` 설명과 `.PHONY`, `tests/repo.bats`가 검사)
  - `AGENTS.md` Invariants의 bash 3.2 규칙은 되풀이하지 않고 가리킨다.
- `AGENTS.md`의 `## Skills`에 "스크립트, Make 타깃, bats 테스트, 스텁, 픽스처를 더하거나 바꿀 때: `script-authoring`"을 더한다. 파일을 바꾸므로 `git-workflow`와 함께 쓴다.

### 8.2 템플릿

- `assets/script.sh`: shebang, `set -euo pipefail`, 머리 주석(목적과 usage 한 줄), 라이브러리 source(`# shellcheck source=` 포함), `readonly` 상수, 함수, `main "$@"`. 지금 실행 스크립트 20개가 모두 `main "$@"` 구조이므로 같은 모양이다. lint 대상(`*.sh`)이므로 템플릿도 shellcheck와 shfmt를 통과한다.
- `assets/test.bats`: `setup() { load helpers; … }`, 함수 밖에 코드를 두지 않음, 성공 경로 하나와 실패 경로 하나의 자리.

### 8.3 `make new-script`

- `make new-script NAME=<name> [KIND=script|remote|lib]`가 `scripts/create-script.sh`를 실행한다. `script`과 `remote`의 이름이 4절 규칙(동사 표의 동사로 시작)에 맞지 않으면 거부한다.
- 템플릿에서 스크립트(`script`과 `remote`는 실행 권한을 준다)와 짝 테스트를 만든다. 파일이 이미 있으면 실패한다. 마지막에 "Make 타깃이 필요하면 `##` 설명과 `.PHONY`를 더하라"를 출력한다.
- `make new-doc`(문서 체계 스펙 8.2절)과 같은 방식이다. 두 스크립트가 같은 템플릿 채우기 함수를 쓰게 되면 `lib/common.sh`에 둔다.

## 9. 검사

문서 체계 스펙의 새 ADR(8.4절)이 허용하는 "짝 파일의 존재"와 "위치와 파일 이름" 검사다. `tests/repo-scripts.bats`에 둔다.

1. 짝: `scripts/*.sh`, `scripts/remote/*.sh`, `scripts/lib/*.sh`마다 6절의 짝 테스트 파일이 있다. 반대로 `tests/*.bats` 가운데 `repo-*.bats`가 아닌 파일은 모두 존재하는 스크립트의 짝이다.
2. `scripts/remote/*.sh`는 `scripts/lib/`를 source하지 않는다.
3. 관심사 라이브러리는 `common.sh`를 source한다.
4. 이름: 실행 스크립트는 `<동사>-<대상>.sh`이고 동사가 `script-authoring` 스킬의 동사 표에 있다.
5. 스크립트 경로: `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, 런북, 스킬, `Makefile`, `.github/`, `.claude/agents/`의 `scripts/...sh` 표기가 실제 파일을 가리킨다. 기록 문서는 옛 이름을 그대로 두므로(4절) 범위 밖이다.

이미 있는 검사(strict mode, bash 3.2 금지 문법, 커버리지, 클라우드 중립, Make 타깃 설명)는 파일만 옮기고 그대로 둔다. 실패 메시지는 어긋난 파일과 고칠 방법(`make new-script` 또는 짝 이름)을 출력한다.

## 10. 계획 분할과 순서 (E4)

| 계획 | 범위 | 시작 조건 |
|---|---|---|
| 16 스크립트 정리 | `lib/` 분리와 함수 색인, 5절 표의 중복, 4절의 이름 변경과 호출처 갱신, 2.1절의 규칙 위반, 새 라이브러리의 짝 테스트(`lib-*.bats`, 새 이름 규칙) | 문서 체계 계획 14 병합 뒤(계획 14는 계획 12 결과 PR 뒤) |
| 17 테스트 정리와 생성 규칙 | 6절의 파일 이동과 이름 변경, 픽스처 이동, 7절의 도우미와 중복 정리, `.bats` lint, 9절의 검사, `script-authoring` 스킬(동사 표 포함), 템플릿, `scripts/create-script.sh`와 `make new-script`, `AGENTS.md`의 Invariants·Skills·Map | 계획 16 병합 뒤 |

- 계획 11과 12의 코드는 병합됐고(2.3절), 5절 표와 4절의 이름은 그 결과를 반영했다.
- 스크립트를 먼저 정리한다. 테스트 이름이 바뀌기 전의 테스트가 리팩터링의 안전망이고, 이름 바꾼 스크립트의 짝 이름을 계획 17이 한 번에 맞출 수 있다. 계획 16은 기존 테스트 파일 안의 스크립트 경로만 고친다.
- 문서 체계의 계획 13~15와는 대부분 다른 파일을 고친다. 계획 13의 `scripts/create-doc.sh`와 `tests/create-doc.bats`는 처음부터 이 스펙의 이름 규칙을 따른다. 계획 14의 문서 검사 파일 이름도 `tests/repo-docs.bats`로 처음부터 정한다. 계획 14가 런북 이름을 바꾸면 스크립트 메시지의 런북 경로도 함께 바뀌므로, 계획 16은 그 뒤의 `main`에서 시작한다.

## 11. 위험과 대응

| 위험 | 대응 |
|---|---|
| 이름 변경으로 참조가 깨짐(Makefile, 스크립트 사이의 호출, 테스트, 리뷰어 훅 경로 `.claude/agents/branch-reviewer.md:12`와 그 검사, 계속 고치는 문서) | 계획 16의 첫 Step이 `git grep`으로 참조 목록을 만든다. 9절 검사 5가 남은 옛 경로를 잡는다. CI가 부르는 `check-git.sh`, `check-pr.sh`는 이름이 그대로다 |
| VM에 올리는 스크립트 이름이 바뀌어 부트스트랩이 깨짐 | `bootstrap-vm.sh`는 원격 파일을 임시 이름(`/tmp/bm-bootstrap.XXXXXX`)으로 올리므로 VM 쪽 경로는 바뀌지 않는다. 로컬 경로 한 줄만 바뀐다. `remote-provision-vm.bats`와 `bootstrap-vm.bats`가 덮는다 |
| 손에 익은 이름이 바뀌어 사람이 헷갈림 | 사람이 치는 Make 타깃은 그대로다. 스크립트를 직접 부르는 일은 드물다 |
| 라이브러리를 나누다 source 순서나 전역 변수가 어긋남 | 짝 테스트(`lib-*.bats`)를 먼저 쓰고, 기존 스크립트 테스트가 통과하는지 Task마다 `make check`로 확인한다 |
| 테스트 파일을 나누고 합치다 단언이 빠짐 | 테스트 이름 목록을 옮기기 전후로 비교해 Progress log에 남긴다(빠진 것은 7.2절의 의도된 정리뿐이어야 한다) |
| 커버리지가 80% 아래로 떨어짐 | 중복 테스트를 지우기 전에 같은 줄을 덮는 테스트가 남는지 kcov 결과로 본다 |
| 문서 체계 계획 13~15와 충돌 | 10절의 순서 |
| `.bats` lint를 켜면 기존 파일이 대량으로 실패 | `make fmt`로 서식을 먼저 맞추고, shellcheck 경고는 고치거나 이유를 단 지시문으로 남긴다 |

## 12. Open questions

1. (결정됨, 2026-10-16) V1, V2(1절): 동사 목록과 스크립트별 새 이름은 초안대로 하고, 계획 12의 두 스크립트는 `check-access.sh`, `open-tunnel.sh`로 한다.
2. (결정됨, 2026-10-15) 라이브러리 함수 이름에 접두어 규칙을 두지 않는다(E6).
3. (결정됨, 2026-10-15) `review.sh`(새 이름 `review-branch.sh`)의 계획 리뷰 문구는 문서 체계의 계획 14가 바꾼다(E7).
