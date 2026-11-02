---
status: active
id: fkcn71m2
spec: docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md
---

# fkcn71m2 Sandbox, Guard and Public Text Hardening Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 2026-11-02 저장소 재검토의 W1·W2·W3·W5(F01~F04, F06~F09 일부, F14, F35)를 고쳐, sandbox 제외 범위가 가드 패턴보다 넓은 틈과 리뷰·공개 경로의 누출 틈을 닫는다.

**Architecture:**
- 임시 파일을 `$TMPDIR` 템플릿으로 만드는 `new_temp`를 `common.sh`에 두어, 공개 텍스트 검사가 sandbox 안에서 돌게 하고 `scripts/check-public-text.sh *` 제외를 뺀다.
- 가드(`scripts/guard-agent-bash.sh`)는 gcloud·gh를 읽기 형태 허용 목록으로, make 호출은 "타깃 + 문서화된 변수 + 평범한 값"만 통과시키는 허용 목록으로 바꾼다. 나머지는 ask다.
- 공개 텍스트 검사에 `local-path` 종류와 diff 모드를 더해, 리뷰 보고서의 절대 경로, 중간 커밋 diff, 병합 커밋 메시지, 게시 전 `--body-file`을 본다.

**Spec:** `docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md`(3.3 가드 훅), 결정 기록 `docs/decisions/adr-2026-10-28-zaptc3gp-agent-trifecta.md`, `docs/decisions/adr-2026-10-26-vtmqpsyx-public-text-guard.md`. 지적 원문은 main checkout `.review-out/full-review-2026-11-02.md`(추적 안 됨)의 2.1절과 5장이다.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 이 계획의 사용자 승인과 아래 "User decisions"의 답.
- 같은 1차에 도는 P-C(운영 견고성), P-E(문서·계획 정리)와 파일이 겹치면 감독 세션에 먼저 알린다. **Reported (2026-11-02, 감독 세션):** `docs/ARCHITECTURE.md:70`(검사 종류 목록)은 동작을 바꾸는 이 계획이 같은 PR에서 고친다. k3bd8k47 계획 Follow-ups의 F35 대상은 P-E가 이 계획의 Task 6으로 적는다.

## User decisions

**Verified (2026-11-02):** 사용자가 계획을 승인하고 D1-A, D2-A, D3-A를 골랐다. D4는 담당 세션이 Task 3의 sandbox 안 실행 결과로 정한다고 알렸다.

- **D1 (F35, ADR zaptc3gp 잔여 위험 문구): A.** 잔여 위험에 "auto 모드에서는 ask를 분류기가 판단해 사람 확인 없이 통과할 수 있다(2026-10-28 `make deploy` 실제 실행, k3bd8k47 Progress log)"와 "F01·F03 형태는 이 계획에서 허용 목록으로 막았다"를 더하고, 결과의 "bypass 모드에서도 매번 프롬프트가 뜬다" 줄 뒤에 "default·bypass 모드 한정, auto 모드는 잔여 위험 참고"를 덧붙인다. 고르지 않은 안: B) 잔여 위험에 한 줄만, C) 넣지 않음.
- **D2 (F03, make 인자): A, 허용 목록.** make 호출의 인자는 타깃 이름과 문서화된 변수(`BRANCH`, `REVIEWER`, `ROUND`, `PR`, `FILE`, `HOST`, `LOCAL`, `BM_WEB`, `FULL`, `HOOK`, `REMOVE`, `TYPE`, `SLUG`, `ID`, `NAME`, `KIND`, `SINCE`, `BACKUP`, `MEMORY_AGENT`, `REVIEW_*`, `LOG_EXPORT_DIR`)의 평범한 값만 통과하고, 옵션·따옴표·백슬래시·`$`·백틱·다른 변수는 ask다. 고르지 않은 안: B) 보고서가 든 형태(따옴표, 백슬래시, `-f/--file/-C/-I/--eval`, `SHELL=`, `MAKEFILES=`)만 ask.
  - 근거 **Verified (2026-11-02):** make 명령줄 변수는 레시피 환경으로 넘어간다. `make -f x.mk BASH_ENV=<파일> t`에서 레시피 bash가 그 파일을 실행했다. `BASH_ENV`, `PATH`, `DOCKER_RUN`, `COMPOSE`처럼 B 목록에 없는 변수도 같은 부류라 B로는 다 막지 못한다.
- **D3 (F07, 가드의 `--body-file` 검사에서 공개 텍스트가 나올 때): A, 막음.** exit 2로 막고 위치와 종류만 출력한다. ADR zaptc3gp 결정 4("deny는 두 종류만") 뒤에 세 번째 종류로 추가 사실을 적는다. auto 모드에서는 ask가 사람 확인을 보장하지 않기 때문이다. 고르지 않은 안: B) ask 사유에 위치를 적음.
- **D4 (`make check-git` 제외):** A) mktemp 수정 뒤 sandbox 안 실행을 확인하면 `make check-git` 제외를 아예 뺀다(신뢰 범위 축소). 확인이 안 되면 B) 정확 문자열을 두고 `make check-git *`를 더한다. 결과는 Progress log에 적는다.

## Global Constraints

- 스크립트 규칙(`AGENTS.md` Invariants): `#!/usr/bin/env bash` + `set -euo pipefail`, `common.sh` 또는 lib를 source, `die`로 조치할 수 있는 메시지, 이름 붙인 상수, macOS bash 3.2(빈 배열 전개 금지, `x="$(fn)" || exit 1`).
- 테스트를 먼저 쓰고 `make test`로 실패를 본 뒤 구현한다. 테스트를 약하게 만들거나 지우지 않는다.
- 공개 저장소다. 커밋·PR·테스트 입력에 VM IP, 실제 홈 경로, 세션 링크를 쓰지 않는다. 테스트의 가짜 주소·경로는 실행 중에 조립하거나 예외 목록에 오른 must-fail fixture에만 둔다. 기존 파일이 새 `local-path` 종류에 걸리면 `.public-text-exemptions` 규칙대로(경로와 종류만, 값은 쓰지 않음) 처리한다.
- deny는 비밀값·노트 읽기와 백업 삭제, 그리고 D3-A의 공개 텍스트가 든 `--body-file` 게시뿐이다(ADR zaptc3gp 결정 4와 이 계획의 추가).
- `.claude/settings.json`은 sandbox가 셸 쓰기를 막으므로 메인 세션이 Edit 도구로 고친다.
- 커밋 트레일러: `Assisted-by: claude-code claude-opus-5-5`, `Plan: fkcn71m2`, `Task: <N|review|none>`.

## Review Focus

1. `TMPDIR`이 비었거나 `/`로 끝날 때 `new_temp`가 `/tmp`나 이중 슬래시 없이 만든다(Task 1 lib 테스트).
2. gcloud 리소스 이름이 읽기 동사와 같은 경우(`gcloud compute instances start list`)는 ask다(Task 4).
3. `sh -c '...'` 안의 gcloud·gh·make도 검사한다. 따옴표를 지운 뒤에만 보면 놓친다(Task 4, 5).
4. make 인자의 `$(...)`·백틱은 sandbox 제외에 맞으면 밖에서 돌 수 있으므로 ask다(Task 5).
5. diff 모드는 지운 줄(`-`)을 보지 않고, 예외 목록 파일에 추가한 줄은 넘긴다. 바이너리 diff는 내용이 없어 검사하지 않고, 따옴표 친 경로는 예외 없이 검사한다(Task 9).
6. `--body-file -`(stdin)과 변수로 된 경로는 검사할 수 없으니 기존 ask로 둔다(Task 10).

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `scripts/lib/common.sh` | `new_temp [-d] NAME` | 1 |
| `scripts/check-public-text.sh`, `scripts/lib/mcp.sh`, `scripts/sync-agent-memory.sh`, `scripts/export-logs.sh`, `scripts/verify-web.sh`, `scripts/verify-sb.sh`, `scripts/upload-sb-fonts.sh`, `scripts/post-review-record.sh` | `mktemp` 호출을 `new_temp`로 | 1 |
| `tests/lib-common.bats`, `tests/repo-scripts.bats` | 헬퍼 동작, 템플릿 없는 `mktemp` 금지 | 1 |
| `scripts/check-public-text.sh`, `tests/check-public-text.bats` | ls-files 실패·0개 처리, `local-path`, diff 모드 | 2, 8, 9 |
| `Makefile`, `.claude/settings.json`, `tests/repo-config.bats` | `make check-git BRANCH=`, 제외 목록 | 3 |
| `scripts/guard-agent-bash.sh`, `tests/guard-agent-bash.bats` | 게시 스크립트 ask, gcloud·gh·make 허용 목록, 감싸기, `--body-file` 검사 | 3, 4, 5, 10 |
| `scripts/review-branch.sh`, `tests/review-branch.bats` | Codex deny 추가, 보고서 경로 상대화 | 7, 8 |
| `scripts/check-git.sh`, `tests/check-git.bats` | 중간 커밋 diff, 병합 커밋 메시지 | 9 |
| `.public-text-exemptions`, `tests/fixtures/check-public-text/` | `local-path` fixture | 8 |
| `docs/ARCHITECTURE.md`(`:70` 검사 종류) | 새 종류와 diff 검사 | 8, 9 |
| ADR zaptc3gp, ADR 0svs72hp, `.agents/skills/git-workflow/SKILL.md` | 추가 사실, 상태, Publish 1 문장 | 3, 6, 7, 9, 10 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/fkcn71m2-sandbox-guard-hardening` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 이 계획을 `make new-doc TYPE=plan SLUG=sandbox-guard-hardening ID=fkcn71m2`로 넣고 `status: active`로 커밋·push한 뒤 초안 PR을 연다. PR 본문에 "병합 직후 main checkout을 pull하고 세션을 다시 시작"을 적는다.

### Task 1: `new_temp` helper and the mktemp call sites (W1, F08)

**Files:**
- Modify: `scripts/lib/common.sh`, 위 표의 8개 스크립트(10곳 + `post-review-record.sh`)
- Test: `tests/lib-common.bats`, `tests/repo-scripts.bats`

**Interfaces:**
- Produces: `new_temp [-d] NAME` → `${TMPDIR:-/tmp}`(끝 `/` 제거) 아래 `NAME.XXXXXX` 파일(또는 `-d`면 폴더)을 만들고 경로를 출력한다. 실패하면 0이 아닌 값으로 끝나므로 호출자는 `x="$(new_temp n)" || exit 1`.

- [x] **Step 1: 실패하는 테스트 작성:** lib 테스트 하나(파일·폴더가 `$TMPDIR/NAME.` 아래 생김, `TMPDIR`이 `/`로 끝나도 같음, `TMPDIR`이 없으면 `/tmp`). repo 테스트 하나(`scripts/`와 `scripts/lib/`에서 `common.sh` 밖의 로컬 `$(mktemp` 호출 0건, `scripts/remote/`와 ssh로 넘기는 원격 `mktemp`는 제외).
- [x] **Step 2: 실패 확인:** Run: `make test` / Expected: 두 테스트만 실패(`new_temp` 없음, 기존 호출 9곳 이상 검출).
- [x] **Step 3: 최소 구현:** 헬퍼와 함수 색인 줄, 각 호출을 `new_temp <스크립트 이름>`으로.
- [x] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0. 이 세션 sandbox에서 `printf hello | scripts/check-public-text.sh --label probe -`가 exit 0(전에는 `mkstemp failed`, exit 1).
- [x] **Step 5: 커밋:** `fix: create temporary files under TMPDIR so checks run inside the sandbox`, `Task: 1`.

### Task 2: repo file list failures in the public text check (W1, F14)

**Files:** Modify `scripts/check-public-text.sh` / Test `tests/check-public-text.bats`

- [x] **Step 1: 실패하는 테스트 작성:** 인자 없이 돌릴 때 ① index를 깨뜨린 임시 저장소에서 `git ls-files`가 실패하면 exit 1과 조치 메시지 ② 파일이 하나도 없는 저장소에서 exit 1("no text files").
- [x] **Step 2: 실패 확인:** Run: `make test` / Expected: 두 경우 모두 지금은 성공으로 끝나 실패.
- [x] **Step 3: 최소 구현:** `git ls-files -z -co --exclude-standard`를 `new_temp` 파일로 받고 `|| die`, 검사할 파일이 0개면 `die`.
- [x] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [x] **Step 5: 커밋:** `fix: fail the public text check when git cannot list the repo files`, `Task: 2`.

### Task 3: sandbox exclusions, `make check-git BRANCH=` and posting scripts (W1, F08, F09 일부)

**Files:**
- Modify: `Makefile`(`check-git`), `.claude/settings.json`, `scripts/guard-agent-bash.sh`, `.agents/skills/git-workflow/SKILL.md`(Publish 1의 "fails inside the Claude Code sandbox" 절), ADR zaptc3gp(결정 2 뒤 추가 사실)
- Test: `tests/repo-config.bats`(고정 제외 목록), `tests/guard-agent-bash.bats`, `tests/repo-make.bats`

동작:
- `make check-git BRANCH=<b>`는 `scripts/check-git.sh origin/main "<b>"`를 부른다. 비우면 지금처럼 현재 브랜치다.
- 제외 목록에서 `scripts/check-public-text.sh *`를 뺀다. D4-A면 `make check-git`도 빼고, D4-B면 `make check-git *`를 더한다. 허용 규칙에 `Bash(make check-git *)`를 더한다.
- `post-review.sh`·`post-review-record.sh` 직접 호출(명령 위치, 경로 접두어 허용)은 ask("this script posts to a pull request"). sandbox 안에서도 이제 공개 텍스트 검사를 통과해 `gh`까지 닿을 수 있기 때문이다(F08 수정 제안).

- [ ] **Step 1: 실패하는 테스트 작성:** repo-config 고정 목록 갱신, guard ask 사례(`scripts/post-review.sh 1 plan/x codex`, `bash scripts/post-review-record.sh 1 f`, `sh -c './scripts/post-review.sh 1 b codex'`)와 통과 사례(`cat scripts/post-review.sh`, `shellcheck scripts/post-review-record.sh`), repo-make 사례(`make -n check-git BRANCH=work/x`가 그 브랜치를 넘김).
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 사례만 실패.
- [ ] **Step 3: 최소 구현.**
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0. 이 세션 sandbox에서 `scripts/check-git.sh origin/main plan/fkcn71m2-sandbox-guard-hardening`과 `make check-git BRANCH=plan/fkcn71m2-sandbox-guard-hardening`이 통과(D4 판단 근거, Progress log에 기록).
- [ ] **Step 5: 커밋:** `feat: run the public text check inside the sandbox and check any branch with make check-git`, `Task: 3`.

### Task 4: gcloud and gh read allow-lists in the guard (W2, F01, F02)

**Files:** Modify `scripts/guard-agent-bash.sh` / Test `tests/guard-agent-bash.bats`

동작:
- gcloud: 명령 위치(감싸기 포함)의 호출마다, 따옴표 친 문자열을 한 토큰으로 줄이고 `;&|()`·줄바꿈에서 자른 뒤 플래그와 플래그 값을 뺀다. 남은 토큰이 `(그룹)* 읽기동사 (인자)*`일 때만 통과한다. 그룹은 고정 목록(`config configurations compute instances firewall-rules disks addresses networks zones regions operations images projects services iam service-accounts keys auth billing accounts logging logs components alpha beta` 등), 읽기 동사는 `list describe info version help get-value get-iam-policy get-serial-port-output read`. 토큰이 없으면(`gcloud --version`) 통과. 그 밖은 ask("this cloud CLI call is not a read-only form").
  - 이유: 지금 패턴은 명령 어디서나 쓰기 동사를 찾는 거부 목록이라 `start`, `ssh`, `scp`, `update-from-file`, `add-iam-policy-binding`, `services enable`, `configurations activate`, `auth print-access-token`을 놓친다. 명령 위치가 아닌 gcloud(`grep gcloud docs`, 파이프 뒤)는 sandbox 제외에 맞지 않아 자격증명 없이 sandbox 안에서 돈다.
- gh: 명령 위치 호출마다 전역 플래그(`-R`, `--repo`)를 건너뛰고 `<명령> <하위 명령>`을 본다. 통과: `pr view|list|diff|checks|status`, `issue view|list|status`, `run view|list|watch`, `workflow view|list`, `release view|list`, `repo view|list`, `gist view|list`, `label|secret|variable|cache list`, `ruleset view|list|check`, `search *`, `auth status`(`-t`, `--show-token` 없을 때), `status`, `version`, `help`, 인자 없음·`--version`, 그리고 지금처럼 필드 없는 GET `api`. 나머지는 ask("this gh call is not a read-only form").
- 한 명령에 gcloud·gh 호출이 여럿이면 모두 본다.

- [ ] **Step 1: 실패하는 테스트 작성:** ask: `gcloud compute instances start x`, `gcloud compute ssh agent-hub --command "sudo docker compose down"`, `gcloud compute scp a agent-hub:b`, `gcloud projects add-iam-policy-binding p --member m --role r`, `gcloud services enable x`, `gcloud compute instances update-from-file x --source f`, `gcloud config configurations activate x`, `gcloud auth print-access-token`, `gcloud compute instances start list`, `gcloud compute instances list && gcloud compute instances start x`, `sh -c 'gcloud compute instances start x'`, `gh run cancel 1`, `gh run rerun 1`, `gh workflow run x`, `gh workflow disable x`, `gh secret set X`, `gh variable set X`, `gh label create x`, `gh alias set co 'pr checkout' --shell`, `gh extension install x`, `gh extension exec x`, `gh auth token`, `gh auth status --show-token`, `gh pr checkout 1`, `gh repo clone x`, `gh pr view 1 && gh pr merge 1`. 통과: `gcloud --configuration=bm-personal compute instances describe agent-hub-01 --zone z --format='value(status)'`, `gcloud config configurations list`, `gcloud config list`, `gcloud auth list`, `gcloud info`, `grep -rn gcloud docs`, `gh pr diff 1`, `gh pr checks 1`, `gh run view 1 --log`, `gh auth status`, `gh search prs x`, `gh -R a/b pr view 3`. 기존 사례는 모두 그대로 둔다.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 ask 사례만 실패.
- [ ] **Step 3: 최소 구현:** 상수(그룹, 읽기 동사, gh 읽기 형태)와 호출 하나를 판정하는 함수 두 개. 기존 `CLOUD_CHANGE_PATTERN`·`GH_WRITE_PATTERN`은 허용 목록이 대신한다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: ask before every cloud CLI and gh call that is not a read-only form`, `Task: 4`.

### Task 5: make argument allow-list, wrappers and the guard header (W2, F03, 3장 헤더 주석)

**Files:** Modify `scripts/guard-agent-bash.sh` / Test `tests/guard-agent-bash.bats`

동작(D2-A):
- 명령 위치를 넓힌다: `VAR=x` 대입 접두어, `env VAR=x`, `time`, `nohup`, `exec`, `command`, `nice`, `xargs`, `sudo` 뒤도 명령 위치로 본다. 그러면 `BM_WEB=on make deploy`, `env BM_WEB=on make deploy`, `time make restore`, `GH_REPO=a/b gh pr create`, `nohup scripts/deploy-stack.sh`도 ask다(보고서 3장).
- make 호출마다 `;&|()<>`·줄바꿈까지 인자를 본다. 끝에 붙은 닫는 따옴표(`sh -c '...'`)는 뺀다. 인자가 타깃 이름(`[a-z0-9][a-z0-9-]*`)이거나 허용 변수의 평범한 값(`[A-Za-z0-9._/:@%+,=-]*`)이 아니면 ask("this make call passes an option, a quoted or expanded argument or an undocumented variable, which can run code outside the repo's Makefile outside the sandbox"). make 앞의 대입 접두어도 같은 허용 목록으로 본다.
- 헤더 주석을 실제 동작대로 고친다: 잡는 감싸기 목록, 허용 목록 방식, 못 잡는 형태(변수 치환, 인코딩, `eval`, 별칭·함수, 스크립트 파일 안의 명령).

- [ ] **Step 1: 실패하는 테스트 작성:** ask: `make probe "deploy"`, `make probe 'deploy'`, `make probe dep\loy`, `make probe -f x.mk`, `make probe --file=x.mk`, `make probe -C /tmp/x`, `make probe --eval=x`, `make probe SHELL=./x.sh`, `make probe MAKEFILES=x.mk`, `make probe BASH_ENV=./x.sh`, `make probe DOCKER_RUN=x`, `make check-git BRANCH=$(id)`, ``make probe HOST=`id` ``, `BASH_ENV=./x.sh make probe`, `BM_WEB=on make deploy`, `env BM_WEB=on make deploy`, `time make restore`, `GH_REPO=a/b gh pr create`, `nohup scripts/deploy-stack.sh`. 통과: `make check 2>&1`, `make check-git BRANCH=plan/abcdefgh-x`, `make review BRANCH=plan/abcdefgh-x REVIEWER=codex ROUND=2`, `make new-doc TYPE=plan SLUG=a-b ID=abcdefgh`, `make export-logs SINCE=24h`, `make memory-sync FULL=1`, `cd x && make backup`, 기존 통과 사례 전부.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 ask 사례만 실패.
- [ ] **Step 3: 최소 구현.**
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: ask before make calls with options, expansions or undocumented variables`, `Task: 5`.

### Task 6: trifecta ADR residual risks (W2, F35)

**Files:** Modify `docs/decisions/adr-2026-10-28-zaptc3gp-agent-trifecta.md`

- [ ] **Step 1:** D1-A 문구를 결과와 잔여 위험에 더한다. 결정 문장은 고치지 않고 뒤에 "(2026-11-0x 추가, 계획 fkcn71m2)"로 사실을 덧붙인다: 결정 5 뒤에 허용 목록 방식, 잔여 위험의 "make와 gh 패턴도 같다" 문장 뒤에 이제 잡는 형태.
- [ ] **Step 2: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 3: 커밋:** `docs: record the guard allow-lists and the auto mode limit in the trifecta ADR`, `Task: 6`.

### Task 7: Codex reviewer denies the main backups and notes (W3, F04)

**Files:** Modify `scripts/review-branch.sh`(`codex_isolation_args`), ADR zaptc3gp 결정 8 뒤 추가 사실 / Test `tests/review-branch.bats`

- [ ] **Step 1: 실패하는 테스트 작성:** "both codex calls … deny profile" 사례에 main `backups`, `.local-data` 절대 경로가 deny에 있는지 더한다. TOML 따옴표 사례도 세 경로 모두.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 단언만 실패.
- [ ] **Step 3: 최소 구현:** `.env`와 같은 TOML 이스케이프로 두 경로를 더한다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `fix: deny the Codex reviewer the main checkout backups and local data`, `Task: 7`.

### Task 8: `local-path` kind and repo-relative review reports (W5, F06)

**Files:**
- Modify: `scripts/check-public-text.sh`(`KIND_IDS`에 `local-path`, 이름 `local path`, `MASK_HINT`), `scripts/review-branch.sh`(보고서를 옮기기 전에 리뷰 worktree 접두어를 지움), `.public-text-exemptions`(머리 주석의 종류 목록, fixture 줄), `docs/ARCHITECTURE.md:70`(검사 종류)
- Create: `tests/fixtures/check-public-text/local-path.txt`(must-fail)
- Test: `tests/check-public-text.bats`, `tests/review-branch.bats`, `tests/post-review.bats`

동작:
- `local-path`: `/Users/<이름>/`, `/home/<이름>/`(이름은 `[A-Za-z0-9._-]+`), `/private/var/folders/`, `/var/folders/`. `<you>`·`$HOME`·`~` 같은 자리표시는 맞지 않는다. 컨테이너 사용자 `/home/appuser/`(compose.yaml)는 허용 이름 상수로 둔다. **Verified (2026-11-02):** 지금 저장소에서 이 모양에 맞는 줄은 `/home/appuser/`뿐이다.
- `review-branch.sh`: 두 보고서에서 리뷰 worktree 경로 접두어(`$WT/`)를 문자 그대로 지워 저장소 상대 경로로 만든다. 남은 절대 경로는 `make review-post`의 공개 텍스트 검사가 거부한다.

- [ ] **Step 1: 실패하는 테스트 작성:** check-public-text 종류 사례에 `local-path` 줄들, pass fixture에 `/home/appuser/.basic-memory`, `/Users/<you>/`, `$HOME/x`. review-branch: codex 스텁이 `$PWD/scripts/x.sh:12`를 쓰면 최종 보고서에는 `scripts/x.sh:12`만 있다. post-review: 실행 중 조립한 홈 경로가 든 보고서는 게시하지 않는다.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 사례만 실패.
- [ ] **Step 3: 최소 구현.**
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0(트리 검사가 새 종류로도 통과).
- [ ] **Step 5: 커밋:** `feat: flag local home and temp paths and strip the review worktree from reports`, `Task: 8`.

### Task 9: history diffs and merge messages in check-git (W5, F07)

**Files:** Modify `scripts/check-public-text.sh`(`--diff` 모드), `scripts/check-git.sh`, ADR 0svs72hp `:29` 행, `docs/ARCHITECTURE.md:70`(diff 검사 한 구절) / Test `tests/check-public-text.bats`, `tests/check-git.bats`

**Interfaces:**
- Produces: `check-public-text.sh --diff [--exemptions FILE] -`: stdin의 `git log -p --unified=0 --format='commit %h'` 출력에서 추가된 줄만 보고, 그 줄이 들어간 파일 경로로 예외를 맞추며, `<sha> <path>:<새 줄 번호>: <kind>`를 값 없이 출력한다.

동작:
- `check-git.sh`는 `base..head`의 병합 아닌 커밋 diff를 `--no-ext-diff --no-textconv --no-color`로 뽑아 diff 모드로 검사한다. 예외 목록은 검사하는 head의 `.public-text-exemptions`(`git show <head>:…`)다. 최종 트리에 남은 예외만 PR diff에 보여 리뷰가 볼 수 있기 때문이다.
- 병합 커밋은 트레일러 검사 없이 메시지만 공개 텍스트 검사를 한다.
- 걸린 커밋은 short SHA와 경로·줄만 알린다. 해결은 이력 재작성이라 "ask the human"(`POLICY_HINT`)이다. CI `pr-rules`도 같은 스크립트를 돌린다.
- ADR 0svs72hp `:29` 행 상태를 "일부"로 바꾸고, 검사 지점(트리, 모든 커밋 diff·메시지, 병합 메시지, CI의 PR 본문, 가드의 `--body-file`)과 남는 틈(`--body` 직접 입력, GitHub 화면 편집, 다른 도구 세션은 CI 전에 게시)을 적는다.

- [ ] **Step 1: 실패하는 테스트 작성:** check-public-text: diff 입력에서 추가 줄만 걸림, 지운 줄은 통과, 예외 경로의 추가 줄은 통과, 줄 번호가 새 파일 기준. check-git: 커밋 1이 가짜 주소(실행 중 조립)를 넣고 커밋 2가 지우면 실패하고 커밋 1의 SHA와 경로를 알리되 값은 출력하지 않음, head 예외 목록에 오른 fixture 추가는 통과, 메시지에 공개 텍스트가 든 병합 커밋은 실패.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 사례만 실패.
- [ ] **Step 3: 최소 구현:** awk 검사 함수는 그대로 쓰고 파일 모드와 diff 모드의 main 블록만 나눈다.
- [ ] **Step 4: 통과 확인:** Run: `make check`, `make check-git` / Expected: 둘 다 exit 0(이 브랜치의 must-fail fixture는 head 예외로 통과).
- [ ] **Step 5: 커밋:** `feat: check every commit diff and merge message of a branch for public text`, `Task: 9`.

### Task 10: guard checks the body file before posting (W5, F07)

**Files:** Modify `scripts/guard-agent-bash.sh`, ADR zaptc3gp 결정 4 뒤 추가 사실(D3-A) / Test `tests/guard-agent-bash.bats`

동작:
- `gh pr create|edit|comment`에 `--body-file <p>`, `--body-file=<p>`, `-F <p>`가 있으면 hook 입력의 `.cwd` 기준으로 파일을 찾아 `scripts/check-public-text.sh`로 검사한다. 걸리면 exit 2와 위치·종류(값 없음)로 막는다. 깨끗하면 지금처럼 ask.
- `-`(stdin), `$`·백틱이 든 경로, 없는 파일은 검사하지 않고 지금처럼 ask.

- [ ] **Step 1: 실패하는 테스트 작성:** 실행 중 조립한 가짜 주소가 든 본문 파일로 세 플래그 형태가 exit 2로 끝남, 깨끗한 파일은 ask, `--body-file -`는 ask, 출력에 값이 없음.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 사례만 실패.
- [ ] **Step 3: 최소 구현.**
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: check the PR body file for public text before gh posts it`, `Task: 10`.

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다. 본문에 "병합 직후 main checkout을 pull하고 세션을 다시 시작(`.claude/settings.json`과 가드가 바뀜)"을 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰(`make review BRANCH=plan/fkcn71m2-sandbox-guard-hardening REVIEWER=codex`)와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 사용자 OK를 받아 `gh pr ready <PR>`을 실행하고 감독 세션과 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 가드가 hook 입력의 `permission_mode`로 auto 모드를 알아보고 VM 변경·게시 ask를 거부로 바꾸는 방안(F35의 근본 대책). **Assumption:** PreToolUse 입력에 `permission_mode`가 있다(문서 확인 전). 별도 계획 후보.
- F05·W4(리뷰어 설정·훅을 base에서 주입), F09의 리뷰 규칙 3 문구와 `review-branch.sh`가 `check-git` 결과를 넣는 일(W6), F10 체크리스트는 이 계획 밖이다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-11-02 | Verified | `make new-id`가 `fkcn71m2`를 냈고 `origin/plan/fkcn71m2-*` 브랜치는 없다. 브랜치를 `plan/fkcn71m2-sandbox-guard-hardening`으로 바꿨다(`.git/config` 갱신은 sandbox가 막았지만 옛 브랜치에 설정 항목이 없어 영향 없음). |
| 2026-11-02 | Verified | scratchpad의 makefile로 `make -s -f x.mk FOO=1 BASH_ENV=<파일> t`를 돌리자 레시피에 `FOO=1`이 보였고 `BASH_ENV` 파일이 실행됐다(D2 근거). |
| 2026-11-02 | Verified | `git grep`으로 `local-path` 모양을 찾으니 `/home/appuser/`(컨테이너 경로) 10개 파일뿐이었다. |
| 2026-11-02 | Verified | 사용자가 Basic Memory 초안 보드의 초안을 승인하고 D1-A, D2-A, D3-A를 골랐다. |
| 2026-11-02 | Verified | Task 1: 테스트를 먼저 쓰자 `make test`(테스트 279개)에서 새 테스트 둘만 실패했다. lib 테스트는 `new_temp: command not found`로, repo 테스트는 로컬 `$(mktemp` 호출 11곳을 찾아 실패했다(`scripts/remote/`와 `bootstrap-vm.sh`가 ssh로 넘기는 원격 `mktemp`는 걸리지 않음). 구현 뒤 `make check`는 exit 0, total line coverage 89.32%(최소 80%)였다. 이 세션 sandbox에서 stdin `hello`로 돌린 `scripts/check-public-text.sh --label probe -`는 바꾸기 전 `mkstemp failed ... Operation not permitted`로 exit 1, 바꾼 뒤 출력 없이 exit 0이었다. |
| 2026-11-02 | Verified | Task 2: 테스트를 먼저 쓰자 `make test`(테스트 280개)에서 새 테스트 하나만 실패했다. 빈 저장소에서 인자 없이 돌린 검사가 exit 0으로 끝났기 때문이다. 임시 저장소의 `.git/index`를 깨뜨리자 `git ls-files`는 exit 128, `git rev-parse --show-toplevel`은 exit 0이었고, 바꾸기 전 스크립트는 git 오류만 남긴 채 exit 0이었다. 구현 뒤 `make check`는 exit 0, total line coverage 89.34%(최소 80%)였다. |
