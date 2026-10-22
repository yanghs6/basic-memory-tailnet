---
status: backlog
spec: none
---

# 20 Agent Sandbox and Permissions Implementation Plan

> 2026-10-22 에이전트 개발 시스템 평가(저장소 밖 기록)에서 나온 백로그 초안입니다. 모든 에이전트 세션의 실행 방식(셸 sandbox, 권한 규칙, 역할 분리)을 바꾸므로, 실행 전에 사용자 승인을 받고 brainstorming → 스펙 → 계획 순서를 거쳐야 합니다. 아래 Task는 후보이고, 설계 질문의 답에 따라 바뀝니다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 어떤 에이전트 역할도 lethal trifecta의 세 다리(자격증명, 신뢰할 수 없는 입력, 외부 통신)를 동시에 쥐지 않고, 파괴적 명령의 사용자 OK는 문장이 아니라 설정이 강제한다.

**Architecture:**
- 셸 명령은 Claude Code sandbox 안에서 돈다. `denyRead`로 자격증명 경로를 막고 `allowedDomains`로 나가는 곳을 줄인다. sandbox에서 못 도는 명령만 정확한 호출 문자열로 `excludedCommands`에 넣고, 그 잔여 위험은 ADR에 적는다.
- 파괴적 명령은 커밋한 `permissions.deny`/`ask`가 막고, `tests/repo-config.bats`가 그 키를 지킨다.
- 외부 글(릴리스 노트)은 자격증명과 쓰기 수단이 없는 역할이 읽고, 작성 역할은 정해진 형식의 요약만 받는다.

**Spec:** none. 모든 세션의 동작을 바꾸는 설계라 활성화 전에 스펙(`make new-doc TYPE=spec SLUG=agent-sandbox`)을 먼저 쓴다. 승인되면 front matter의 `spec:`과 이 줄을 그 경로로 바꾼다.

**Sequence:** 계획 20. 다음을 모두 만족한 뒤 시작한다.
- 사용자가 이 백로그를 승인하고, 아래 설계 질문에 답한 스펙이 `approved`다.
- 계획 18(`docs/plans/plan-2026-10-22-18-public-text-guard.md`, 게시 전 공개 텍스트 검사)과는 독립이다. 리뷰어 보고서를 공개 PR에 올리는 간접 외부 출력은 계획 18이 맡고, Task 5의 표는 그 결과를 반영한다.

## 배경

### Facts

- **Reported (2026-10-22 평가):** D5(보안)가 1점이라 평가 전체가 gated다. 원인 하나는 AP9로, 작성 에이전트(Claude Code)가 세 다리를 모두 쥔다.
  - 자격증명: 머신 계정의 `gh`·push 토큰(`AGENTS.md:34`), `gcloud` `bm-personal`(`:26`), VM SSH 키, main checkout `.env`(`:25`)
  - 신뢰할 수 없는 입력: 업스트림 릴리스 노트(`.agents/skills/bm-upgrade/SKILL.md:35`), 공개 저장소의 PR 댓글, 제3자 스킬
  - 외부 통신: `git push`, `gh pr comment`, 열린 네트워크
- **Verified (2026-10-22):** `.claude/settings.json:6-22`에는 `permissions.allow`(make 타깃 8개, `:7-16`)와 `Read(./.env)`, `Read(./backups/**)`, `Read(./.local-data/**)` deny(`:17-21`)만 있다. `sandbox` 키도 Bash `deny`/`ask` 규칙도 없다.
- **Verified (2026-10-22):** `.gitignore:5`가 `.claude/settings.local.json`을 무시하므로 Task 1의 시험 설정은 커밋되지 않는다. `.github/rulesets/main.json`의 `non_fast_forward`·`deletion`은 기본 브랜치에만 걸리므로, 작업 브랜치의 force-push 금지(`AGENTS.md:32`)는 문장으로만 남아 있다.
- **Verified (2026-10-22):** `Makefile:11`이 모든 make 타깃에서 main checkout `.env`를 `-include`한다. VM 타깃은 `scripts/lib/vm.sh:110-112`의 `ssh`로 VM에 닿고, ssh 모드에서는 `~/.ssh/config`의 ProxyCommand를 쓴다(`scripts/lib/vm.sh:53`).
- **Verified (2026-10-22):** `scripts/restore-notes.sh:54-58`의 `confirm`은 `read -r -p`로 표준입력에서 `yes`를 읽고, 테스트도 파이프로 넘긴다(`tests/restore-notes.bats:36-38`). 파이프 금지(`AGENTS.md:27`)는 문장으로만 막혀 있다.
- **Verified (2026-10-22):** Codex 리뷰어는 `scripts/review-branch.sh:137`(`-c 'sandbox_mode="read-only"'`)과 `:139`(`--sandbox read-only`)로 읽기 전용이다. 저장소에는 Codex 프로젝트 설정이 없다. Claude 리뷰어는 `.claude/agents/branch-reviewer.md:4-12`의 도구 목록과 `scripts/guard-reviewer-bash.sh` 훅(exit 2로 차단)으로 제한된다.
- **Verified (2026-10-22, docs, https://code.claude.com/docs/en/sandboxing.md):**
  - 키: `sandbox.filesystem.denyRead`, `sandbox.network.allowedDomains`, `sandbox.excludedCommands`, `sandbox.allowUnsandboxedCommands`(`false`면 `dangerouslyDisableSandbox` 재시도를 무시한다). sandbox 경로에서 `.`은 프로젝트 루트, `~/`는 홈이다.
  - `excludedCommands`는 호출 문자열과 맞춘다. 안에서 `docker`를 부르는 make 타깃은 `docker *`에 맞지 않으므로, `make check`는 그 문자열 그대로 넣어야 한다. 제외된 명령은 사용자 권한 전체로 돈다. 작업 디렉터리의 파일을 실행하는 패턴이면 "Claude can write that file and then run it outside the sandbox".
  - `bypassPermissions` 모드에서는 제외된 명령도 ask 규칙에 맞지 않으면 묻지 않고 돈다.
  - `docker`는 sandbox와 함께 쓸 수 없다. `gh`, `gcloud`는 macOS Seatbelt에서 TLS 검증에 실패할 수 있다. 문서는 `gh *`를 제외하라고 하고, 그러면 "its stored credentials"로 돈다.
  - Read, Edit, WebFetch, WebSearch, 훅, 로컬 MCP 서버는 sandbox 밖에서 돈다. `allowedDomains`는 WebFetch를 제한하지 않는다. WebFetch는 `WebFetch(domain:...)` 권한 규칙을 따른다. 서브에이전트는 부모와 같은 sandbox 설정을 쓴다.
  - `strictAllowlist`는 저장소의 `.claude/settings.json`과 `.claude/settings.local.json`에서는 효과가 없다.
- **Verified (2026-10-22, docs, https://code.claude.com/docs/en/permissions.md):**
  - 평가 순서는 deny → ask → allow다. allow는 deny에 예외를 만들지 못한다. `Bash(make deploy *)`는 인자 없는 `make deploy`에도 맞는다.
  - 규칙은 프로그램이 아니라 명령 문자열과 맞춘다. `Bash(git push *)`는 `git -C . push`도 `sh -c '...'`도 막지 못한다.
  - `Read` deny는 `cat`·`head`·`sed`와 리디렉션에는 걸리지만, `grep -r`이나 Python `open()`에는 걸리지 않는다.
  - 권한 규칙의 절대 경로는 `//`로 시작한다. `/x`와 `./x`는 설정 파일이 있는 곳 기준이다.
  - bypass 모드에서 allow 규칙은 효과가 없다. 그래도 deny는 막고, 명시한 ask 규칙은 묻는다.
- **Verified (2026-10-22, docs, https://code.claude.com/docs/en/hooks.md):** PreToolUse 훅이 exit 2로 끝나면 호출이 막히고 stderr가 에이전트에게 간다. 훅이 `allow`를 내도 deny 규칙을 넘지 못한다.
- **Verified (2026-10-22, docs, https://learn.chatgpt.com/docs/config-file/config-reference):** Codex `shell_environment_policy`에는 `inherit`(`all`/`core`/`none`), `ignore_default_excludes`, `filters`가 있다. `ignore_default_excludes`의 설명("Keeps variables whose names contain KEY, SECRET, or TOKEN", 기본 `true`)은 모호하다. 기본값에서 `GH_TOKEN`이 리뷰어 환경으로 넘어갈 수 있다.
- **Assumption:** worktree 세션의 프로젝트 루트는 그 worktree다. 그러면 `Read(./.env)`는 main checkout `.env`가 아니라 worktree의 (없는) `.env`를 가리킨다. 작성 에이전트는 항상 worktree에서 일하므로, 지금의 deny는 실제 `.env`를 막지 못할 수 있다.
- **Assumption:** Codex `read-only` sandbox는 쓰기만 막고 읽기는 막지 않는다. 그러면 리뷰어도 main checkout `.env`를 읽을 수 있다. 네트워크 기본값은 문서에 workspace-write 기준으로만 나온다.
- **Open question:** sandbox 안에서 `gcloud` IAP SSH(ProxyCommand), `gh` TLS, osxkeychain을 쓰는 HTTPS `git push`가 되는지는 문서로 알 수 없다. Task 1에서 시험한다.

### Design questions

1. 설정 위치와 main checkout 경로: 공개 저장소의 `.claude/settings.json`에는 기기의 절대 경로를 쓸 수 없다. main checkout `.env`, `~/.ssh`, `~/.config/gcloud`를 어떻게 막을 것인가? 후보는 셋이다.
   - (a) 사용자 설정에 절대 경로를 쓴다. 커밋되지 않고 테스트할 수 없다.
   - (b) 프로젝트 설정에 상대 경로를 쓴다. worktree 위치에 기대고, Codex worktree에서는 경로가 다르다.
   - (c) `permissions.blockReadsOutsideWorkingDirectories`(v2.1.257+)를 쓴다. worktree의 git이 읽어야 하는 main `.git`까지 막는지 확인해야 한다.
2. `make check`와 Docker: `make check`를 정확한 문자열로 제외하면, 에이전트가 고친 `Makefile`과 `tests/`가 sandbox 밖에서 돈다(문서가 경고하는 write-then-run). 이 위험을 받아들일 것인가, `Makefile:29` `DOCKER_RUN`에 `--network none`을 더해 컨테이너의 외부 통신을 끊을 것인가? 제외 목록에는 어떤 타깃을 넣는가(`lint`, `test`, `coverage`, `fmt`, `local-*`, VM 읽기 타깃)?
3. 자격증명 CLI: `gh`·`gcloud`·`ssh`·`git push`를 제외하면 그 명령은 저장된 자격증명과 네트워크를 다 가진다. 제외하고 ask로 묻게 할 것인가, 역할을 나눠 신뢰할 수 없는 입력을 읽은 세션은 push·게시·VM 명령을 쓰지 않게 할 것인가? bypass 모드에서는 ask만 묻는다는 점을 전제로 정한다.
4. 규칙 종류: force-push와 `backups` 삭제는 `AGENTS.md:24,32`가 "never"라 deny가 맞다. `make deploy|restore|vm-bootstrap|sb-fonts`와 gcloud 생성·삭제는 `AGENTS.md:23`이 "먼저 묻기"라 ask가 맞는가? 평가는 gcloud 생성·삭제를 deny로 권했지만, 그러면 `bm-recover`의 VM 재생성과 충돌한다. 문자열 규칙은 `sh -c`, `git -C . push`, `scripts/restore-notes.sh` 직접 호출로 피해 갈 수 있다. 이것을 PreToolUse 훅의 부분 문자열 검사로 보완할 것인가?
5. 네트워크와 WebFetch: sandbox 허용 도메인은 무엇인가(`github.com`, `api.github.com`, 그 밖)? WebFetch·WebSearch는 `allowedDomains`가 막지 못한다. 작성 세션에서 WebFetch를 deny하면 같은 설정을 쓰는 서브에이전트 독자도 읽지 못한다(**Assumption:** 권한 규칙도 서브에이전트에 그대로 적용된다).
6. 입력 분리의 효과: 독자 역할의 요약이 작성 세션으로 돌아오면 다리를 끊은 것인가, 좁힌 것뿐인가? 요약을 고정 형식(버전, 마이그레이션 여부, 바뀐 플래그·환경 변수·경로·도구의 원문 인용)으로 묶을지, 사람이 릴리스 노트를 직접 읽을지 정한다. `AGENTS.md:14`는 핀을 바꾸기 전에 릴리스 노트를 읽으라고 한다. Codex·Gemini CLI·Antigravity가 `bm-upgrade`를 실행할 때는 어떻게 나누는가? 다른 계정이 쓴 공개 PR 댓글은 누가 읽는가?
7. restore 확인: `/dev/tty`는 파이프를 막는다. 하지만 `script`·`expect`처럼 pty를 만드는 명령으로 피할 수 있고, `Bash(make restore *)` ask는 `script -q /dev/null make restore ...`에 맞지 않는다. 그래도 충분한가? 성공 경로를 시험하려고 환경 변수 같은 시험용 입구를 두면, 그것이 곧 에이전트의 우회로가 된다. 사용자가 Claude Code의 `!` 셸 모드에서 `make restore`를 실행하면 터미널이 붙는가?
8. Codex 리뷰어 환경: `shell_environment_policy`를 `scripts/review-branch.sh:137,139`의 `-c` 인자로 줄 것인가, 사용자 `~/.codex/config.toml`에 둘 것인가? `--sandbox read-only`의 네트워크와 읽기 범위는 실제 실행으로 확인한다.

## Global Constraints

- 공개 저장소다. 커밋하는 설정·테스트·문서에 홈 디렉터리 같은 로컬 절대 경로, IP 주소, tailnet 호스트 이름, 세션 id를 쓰지 않는다(`AGENTS.md:28`).
- 시험 중에도 `.env`, `backups/`, `.local-data/`의 내용을 읽지 않는다. `denyRead` 검사는 scratch 디렉터리의 미끼 파일로 한다.
- VM이나 클라우드에 닿는 Step은 메인 세션에서 사용자와 함께 한다. 바꾸는 명령(`make deploy`, `restore`, `vm-bootstrap`, `sb-fonts`, gcloud 생성·삭제)은 이 계획에서 실행하지 않는다. ask 규칙은 프롬프트가 뜨는 것만 확인하고 거절한다.
- `gcloud`는 `--configuration=bm-personal`로만 쓴다(`AGENTS.md:26`).
- 스크립트는 macOS bash 3.2에서 돌아야 하고, bats 테스트를 먼저 쓴다(`AGENTS.md:16,18`). 테스트를 약하게 고쳐 통과시키지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 20`, `Task: <N|review|none>`.

## Review Focus

1. 설정 키가 빠지거나 제외 패턴이 넓어지는 변경(`make *`, `docker *`, `bash *`)이 생기면 `make check`가 실패해야 한다 → Task 2의 테스트.
2. 터미널 없이(에이전트 Bash, CI) 실행한 `restore-notes.sh`는 ssh를 부르기 전에, 해결 방법을 담은 메시지로 실패해야 한다 → Task 4.
3. 독자 역할 정의에 Bash나 쓰기 도구가 다시 들어가면 실패해야 한다 → Task 3.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `.claude/settings.local.json` (git ignore, 커밋 안 함) | 시험용 sandbox 설정 | 1 |
| `.claude/settings.json` | sandbox, Bash deny/ask | 2 |
| `tests/repo-config.bats` | 설정 키와 독자 역할 정의 검사 | 2, 3 |
| `.agents/skills/bm-upgrade/SKILL.md` | 3단계의 릴리스 노트 읽기를 독자 역할에 넘김 | 3 |
| `.claude/agents/release-notes-reader.md` | 셸·쓰기 도구가 없는 독자 서브에이전트 | 3 |
| `scripts/restore-notes.sh`, `tests/restore-notes.bats` | `yes`를 `/dev/tty`에서만 읽음 | 4 |
| `docs/decisions/`의 새 ADR, `docs/ARCHITECTURE.md` | 역할별 trifecta 표와 잔여 위험 | 5 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/20-agent-sandbox` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Sandbox spike

**Files:**
- Create: `.claude/settings.local.json`(git ignore, 커밋하지 않는다). 사용자 설정에서만 먹는 키는 scratch 파일과 `claude --settings`로 시험한다.
- Modify: 이 계획의 Progress log

동작: 코드는 바꾸지 않고, 실제 저장소에서 sandbox를 켰을 때 무엇이 깨지는지 기록한다. 실패하는 테스트는 없다(조사 Task).

- [ ] **Step 1:** 시험 설정을 둔다: `sandbox.enabled: true`, `allowUnsandboxedCommands: false`, 미끼 파일을 `denyRead`에, `allowedDomains`에 `github.com`과 `api.github.com`.
- [ ] **Step 2:** 다음을 차례로 실행한다(VM에 닿는 두 줄은 사용자와 함께, 어느 것도 VM을 바꾸지 않는다).
  - `make check`: 제외 없이 한 번, `excludedCommands: ["make check"]`로 한 번
  - `git push --dry-run origin HEAD`, `gh api user --jq .login`
  - 미끼 파일을 `cat`, `grep -r`, `python3 -c 'open(...)'`, Read 도구로 각각 읽기
  - main checkout `.env`를 `denyRead`에 넣은 상태의 `make help`(`Makefile:11`의 `-include`가 어떻게 되는지. 내용은 출력되지 않는다)
  - `gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(status)'`, `make probe`
  - `codex exec --sandbox read-only`로 `env | cut -d= -f1`(이름만), `curl -sI https://api.github.com`
- [ ] **Step 3:** 시험 키를 `.claude/settings.local.json`에서 지운다.

Run: 위 명령
Expected: 명령마다 sandbox 안 성공·실패, 오류 첫 줄, 필요한 제외 항목이 Progress log에 `Verified`로 남는다.

커밋: `docs: record the sandbox spike`, 트레일러 `Plan: 20`, `Task: 1`.

### Task 2: Committed sandbox and permission rules

**Files:**
- Modify: `.claude/settings.json:6-22`
- Test: `tests/repo-config.bats`(새 `@test`, `:152-176` 리뷰어 테스트 뒤)

동작:
- `sandbox`: `enabled: true`, `allowUnsandboxedCommands: false`, `filesystem.denyRead`(설계 질문 1의 답), `network.allowedDomains`, `excludedCommands`(Task 1이 필요하다고 확인한 정확한 문자열만. 예: `make check`)
- `permissions.ask`: `Bash(make deploy *)`, `Bash(make restore *)`, `Bash(make vm-bootstrap *)`, `Bash(make sb-fonts *)`, gcloud 생성·삭제(설계 질문 4의 답에 따라 deny로 옮길 수 있다)
- `permissions.deny`: 기존 Read 3개 + force-push(`--force`, `--force-with-lease`, `-f`, `+` refspec) + `backups`를 지우는 `rm -r`/`rm -rf`

- [ ] **Step 1: 실패하는 테스트 작성:** `the Claude Code settings keep the sandbox on, exclude only exact commands, and deny or ask before destructive commands`. `jq`로 다음을 검사한다.
  - `.sandbox.enabled == true`, `.sandbox.allowUnsandboxedCommands == false`, `denyRead`와 `allowedDomains`가 비어 있지 않음
  - `excludedCommands`의 어느 항목에도 `*`가 없음
  - 위 ask·deny 항목과 기존 Read deny 3개가 모두 있음
  - 파일에 홈 디렉터리 절대 경로가 없음
  - 검사 함수가 키 하나를 지운 사본에서 실패하는지도 확인한다(`tests/repo-cloud-neutral.bats`의 첫 사례와 같은 방식).
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 테스트가 `.sandbox`가 null이라 실패한다.
- [ ] **Step 3: 최소 구현:** `.claude/settings.json`에 위 키를 넣는다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0, 커버리지 80% 이상. 새 세션을 Manual 모드로 열어 `make deploy`에 "Bash command" 프롬프트가 뜨는 것을 확인하고 거절한다.
- [ ] **Step 5: 커밋:** `feat: enable the Claude Code sandbox and ask before VM commands`, 트레일러 `Plan: 20`, `Task: 2`.

### Task 3: Release-notes reader without credentials

**Files:**
- Create: `.claude/agents/release-notes-reader.md`
- Modify: `.agents/skills/bm-upgrade/SKILL.md:35`(3단계), `:23`(체크리스트 3번)
- Test: `tests/repo-config.bats`

동작: 3단계에서 작성 세션은 릴리스 페이지를 직접 열지 않는다. 독자 역할이 https://github.com/basicmachines-co/basic-memory/releases 에서 현재 버전과 목표 버전 사이의 노트를 읽고 고정 형식으로 답한다. Claude Code에서 독자는 `tools: WebFetch`만 있고 `disallowedTools`에 Bash, Write, Edit, NotebookEdit가 있는 서브에이전트다. 작성 세션은 그 요약을 사용자에게 보이고, 7단계 전에 확인을 받는다. 다른 도구에서 어떻게 할지는 설계 질문 6의 답을 따른다. 스킬 본문에는 클라우드 이름을 쓰지 않는다(`tests/repo-cloud-neutral.bats`).

- [ ] **Step 1: 실패하는 테스트 작성:** `the release-notes reader has no shell or write tool and bm-upgrade hands step 3 to it`. 리뷰어 테스트(`tests/repo-config.bats:152-176`)처럼 frontmatter를 읽어 다음을 검사한다.
  - `tools:` 줄이 설계가 정한 목록과 같고, Bash·Write·Edit가 없음
  - `disallowedTools`에 Bash·Write·Edit가 있음
  - `SKILL.md` 3단계가 독자 이름을 담음
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 독자 정의 파일이 없어 새 테스트가 실패한다.
- [ ] **Step 3: 최소 구현:** 독자 정의를 쓰고 3단계와 체크리스트를 고친다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋:** `feat: read Basic Memory release notes in a role without credentials`, 트레일러 `Plan: 20`, `Task: 3`.

### Task 4: Restore confirmation from the terminal

**Files:**
- Modify: `scripts/restore-notes.sh:54-58`(`confirm`), `:8`(Usage 주석)
- Test: `tests/restore-notes.bats:36-38`(`restore_with_answer`), `:142`(거부 사례 표)

동작: `confirm`은 `/dev/tty`에서만 읽는다. 터미널을 열 수 없으면 ssh를 부르기 전에 `die`로 끝나고, 메시지는 사용자 자신의 터미널에서 `make restore`를 실행하라고 알린다. 파이프로 넘긴 `yes`는 받지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성:** `:142`의 거부 사례 표에 `piped yes without a terminal`을 더한다: `printf 'yes\n' | scripts/restore-notes.sh <archive>`가 실패하고, 메시지가 터미널을 요구하며, `$STUB_LOG`에 ssh 호출이 없어야 한다. 성공 경로의 `restore_with_answer yes`(4곳)는 pty로 답을 넘기도록 helper를 바꾼다(**Assumption:** 테스트 이미지(`tools/Dockerfile:4`의 kcov 이미지)에 util-linux `script`가 있다).
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 지금 코드는 파이프의 `yes`를 받아 복원을 진행하므로 새 사례가 실패한다.
- [ ] **Step 3: 최소 구현:** `confirm`의 `read`를 `/dev/tty`로 돌리고, 열기 실패를 `die`로 바꾼다(bash 3.2 문법).
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋:** `fix: read the restore confirmation from the terminal, not stdin`, 트레일러 `Plan: 20`, `Task: 4`.

### Task 5: Trifecta ADR

**Files:**
- Create: `make new-doc TYPE=adr SLUG=agent-trifecta`가 `docs/decisions/`에 만드는 ADR
- Modify: `docs/ARCHITECTURE.md:75-84`(신뢰 경계에 에이전트 쪽 항목 하나와 ADR 링크), front matter `reviewed`

동작:
- ADR에 역할별 표를 둔다. 행은 작성 메인 세션, 작성 서브에이전트(구현·Task 리뷰), 릴리스 노트 독자, Codex 리뷰어, Claude `branch-reviewer`, CI다. 칸마다 다리가 있는지와, 없앤 다리는 그 기제(설정 키, 도구 목록, 훅, 테스트)를 적는다.
- 결과 절에는 잔여 위험을 적는다.
  - `excludedCommands`의 항목마다: 사용자 권한 전체로 돌고, 고친 파일을 sandbox 밖에서 실행할 수 있다
  - sandbox 밖에서 도는 도구: Read, WebFetch, 훅, 로컬 MCP
  - 문자열 매칭 우회(`sh -c`, `git -C . push`, 스크립트 직접 호출)와 `restore`의 pty 우회
  - bypass 모드에서는 allow가 무효이고 ask·deny만 남는다
  - 리뷰어 보고서의 공개 게시(계획 18)

- [ ] **Step 1:** 새 테스트는 없다. `tests/repo-docs.bats`가 이름, front matter, 링크를 검사한다. ADR의 "확인 방법" 줄에 Task 2·3·4의 테스트 이름을 적는다.
- [ ] **Step 2:** Run: `make check` / Expected: exit 0.
- [ ] **Step 3: 커밋:** `docs: record the agent trifecta decision`, 트레일러 `Plan: 20`, `Task: 5`.

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 제3자 스킬·플러그인 고정(marketplace `sha`, `autoUpdate`)은 사용자 설정의 일이라 이 계획에서 뺀다.
- 옛 공개 커밋의 세션 링크(평가 AP10)는 이 계획 밖이다. 이력 재작성은 `AGENTS.md:32`가 금지한다.
- 다른 에이전트가 MCP로 쓴 Basic Memory 노트를 신뢰할 수 없는 입력으로 볼지 정한다. MCP 서버는 sandbox 밖에서 돈다.
- Gemini CLI·Antigravity의 sandbox 설정(지금 `.gemini/settings.json`에는 `context.fileName`만 있다)과 Codex 작성 세션의 다리 점검.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
