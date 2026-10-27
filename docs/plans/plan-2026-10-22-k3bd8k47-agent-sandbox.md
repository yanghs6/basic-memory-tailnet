---
status: active
id: k3bd8k47
spec: docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md
---

# k3bd8k47 Agent Sandbox and Permissions Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 어떤 에이전트 역할도 lethal trifecta의 세 다리(자격증명, 신뢰할 수 없는 입력, 외부 통신)를 사람의 확인 없이 동시에 쥐지 않는다. deny는 되돌릴 수 없는 두 가지(비밀값·노트 내용 읽기, `backups`·`.prev-*` 삭제)만 막고, 나머지 파괴적·외부 명령은 설정과 훅이 ask로 묻는다.

**Architecture:**
- Claude Code 셸 명령은 sandbox 안에서 돈다. Docker·ssh·자격증명 CLI를 쓰는 명령만 `excludedCommands`로 밖에서 돈다. 파일 읽기는 `blockReadsOutsideWorkingDirectories`로 worktree 안으로 제한한다.
- 커밋한 `permissions.deny`/`ask`와 PreToolUse 가드 훅(`scripts/guard-agent-bash.sh`)이 문자열 규칙과 그 우회 형태를 처리하고, `tests/repo-config.bats`와 훅의 bats가 이를 지킨다.
- 외부 글(릴리스 노트)은 WebFetch만 가진 독자 서브에이전트가 읽는다. Codex 리뷰어는 토큰 환경 변수 없이, 자격증명 경로를 읽지 못하게 돈다.

**Spec:** `docs/specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md` (1절 사용자 결정 0-11, 3절 설계, 3.10 바뀌는 점)

**Sequence:** 스펙이 `approved`다(2026-10-27). 다른 계획과는 독립이다. 동시에 진행 중인 mk823xbp(PR #30)가 Makefile·AGENTS.md·훅 설치를 바꾸므로, 나중에 병합하는 쪽이 `git merge origin/main`으로 맞춘다.

## Global Constraints

- 공개 저장소다. 커밋하는 설정·훅·테스트·문서에 홈 디렉터리 절대 경로, IP 주소, tailnet 호스트 이름, 세션 id를 쓰지 않는다. 설정 경로는 `~/`와 `./`만 쓴다.
- `.env`, `backups/`, `.local-data/`의 내용은 시험 중에도 읽거나 출력하지 않는다. 막히는지는 scratch 디렉터리의 미끼 파일로, 실제 파일에는 성공·실패만 본다.
- `.claude/settings.json`, `.claude/settings.local.json`의 시험 설정은 사용자 OK를 받고 이 worktree에서만 둔다. main checkout의 설정과 사용자 설정(`~/.claude/settings.json`, `~/.codex/config.toml`)은 바꾸지 않는다.
- VM에 닿는 명령(`make probe` 포함)은 감독 세션에 먼저 묻는다. VM을 바꾸는 명령(`make deploy`, `restore`, `vm-bootstrap`, `sb-fonts`, gcloud 생성·삭제)은 이 계획에서 실행하지 않는다. ask 프롬프트는 뜨는 것만 확인하고 거절한다.
- `permissions.deny`에는 결정 11의 두 종류만 둔다. 그 밖은 ask다.
- 스크립트는 macOS bash 3.2에서 돌고, bats 테스트를 먼저 쓴다. `@test` 수를 줄이지 않는다.
- AGENTS.md는 바꾸지 않는다. 바꿀 줄이 생기면 사용자에게 먼저 묻는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: k3bd8k47`, `Task: <N|review|none>`.

## Review Focus

1. `excludedCommands`에 고정 목록 밖의 `*` 패턴(`make *`, `docker *`, `bash *`)이 생기거나, `permissions.deny`에 결정 11 밖의 항목이 생기면 `make check`가 실패해야 한다 → Task 2.
2. 가드 훅은 `sh -c`, `env`, `git -C .`로 감싼 force-push와 `backups` 삭제를 잡고, 오류나 잘못된 JSON에서는 막는 쪽으로 끝나야 한다 → Task 3.
3. 터미널 없이(에이전트 Bash, CI) 실행한 `restore-notes.sh`는 ssh를 부르기 전에, 해결 방법을 담은 메시지로 실패해야 한다 → Task 6.
4. 독자 역할 정의에 Bash나 쓰기 도구가 다시 들어가면 실패해야 한다 → Task 5.
5. Codex 호출 인자에서 환경 정책이 빠지면 실패해야 한다 → Task 7.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `.claude/settings.local.json` (git ignore, 커밋 안 함) | spike용 시험 설정 | 1 |
| `.claude/settings.json` | sandbox, `blockReads…`, deny/ask, 훅 등록 | 2, 3 |
| `tests/repo-config.bats` | 설정 키와 독자 정의 검사 | 2, 5 |
| `scripts/guard-agent-bash.sh`, `tests/guard-agent-bash.bats` | 가드 훅 | 3 |
| `Makefile` | `DOCKER_RUN --network none`, 9-A 읽기 전용 타깃 | 4, 8 |
| `.claude/agents/release-notes-reader.md` | 셸·쓰기 도구가 없는 독자 | 5 |
| `.agents/skills/bm-upgrade/SKILL.md` | 3단계를 독자에게 넘김 | 5 |
| `.agents/skills/git-workflow/references/review-and-merge.md` | PR 댓글 거르기, 출력 위치, archive 옮기기 | 5, 8 |
| `scripts/restore-notes.sh`, `tests/restore-notes.bats` | `yes`를 `/dev/tty`에서만 읽음 | 6 |
| `scripts/review-branch.sh`, `tests/review-branch.bats` | Codex 환경 정책·permission profile | 7 |
| 9-A의 새 스크립트와 bats, `.agents/skills/bm-recover/SKILL.md` | 최신 backup 경로·체크섬 확인 | 8 |
| `docs/decisions/`의 새 ADR, ADR `0svs72hp`, `docs/ARCHITECTURE.md` | 역할별 trifecta 표, 잔여 위험 | 9 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/k3bd8k47-agent-sandbox` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [x] 첫 커밋(스펙 문서와 이 계획 개정)에서 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다. 감독 세션에 알린다.

### Task 1: Sandbox spike

**Files:**
- Create: `.claude/settings.local.json`(git ignore, 커밋하지 않는다)
- Modify: 이 계획의 Progress log

동작: 코드는 바꾸지 않고, 이 worktree에서 sandbox와 `blockReads…`를 켰을 때 무엇이 깨지는지 기록한다. 시험 설정을 두기 전에 사용자 OK를 받는다. 실패하는 테스트는 없다(조사 Task).

- [ ] **Step 1:** 시험 설정: `sandbox.enabled: true`, `allowUnsandboxedCommands: false`, scratch 미끼 파일을 `denyRead`에, `allowedDomains`에 `github.com`, `api.github.com`, `permissions.blockReadsOutsideWorkingDirectories: true`. 새 세션을 이 worktree에서 연다.
- [ ] **Step 2:** 다음을 차례로 실행하고, 명령마다 성공·실패, 오류 첫 줄, 필요한 제외 항목을 적는다.
  - `git status`, `git log -1`, `git fetch origin`(worktree의 git이 main `.git`을 읽는지)
  - `make help`, `make new-id`(main `.env`의 `-include`)
  - `make check`: 제외 없이 한 번, `excludedCommands: ["make check"]`로 한 번. 컨테이너 안 `script` 존재(`docker run --rm <tools image> which script`), `--network none`으로 이미지 pull이 되는지
  - `git push --dry-run origin HEAD`, `gh api user --jq .login`(제외 전·후)
  - 미끼 파일을 `cat`, `grep -r`, `python3 -c 'open(...)'`, Read 도구로 읽기. scratch 디렉터리 파일을 Read 도구로 읽기
  - `gcloud ... describe --configuration=bm-personal --format='value(status)'`와 `make probe`: 감독 세션 OK 뒤에만
  - `make review`의 Claude 리뷰어(`claude -p --agent branch-reviewer`)가 새 설정에서 도는지(작은 시험 브랜치나 이 브랜치의 dry run)
  - `codex exec`에 `-c` permission profile(`extends=":read-only"`, `~/.ssh` deny)과 `shell_environment_policy`를 주고 `env | cut -d= -f1`(이름만), `ls ~/.ssh`(결과는 성공·실패만)
  - Claude Code `!` 모드에서 `[ -t 0 ] && echo tty || echo no-tty`
  - 감독 세션 요청(2026-10-27), 운영에 필요한 경로:
    - 작업 디렉터리 밖에서 Read·Edit·Write·Bash가 되는지: auto memory 폴더(`~/.claude/projects/<project>/memory/`)와 세션 scratchpad. 다른 세션 transcript(`~/.claude/projects/*/*.jsonl`) 읽기가 막히면 스펙 영향(3.10)에 적는다.
    - mk823xbp(PR #30) memory hook(SessionStart·Stop의 `make memory-sync`, SessionStart의 `make memory-index`)이 새 설정에서 돌고 `make tunnel`로 Basic Memory에 닿는지. 커밋한 가드 훅과 사용자 hook의 순서·timeout이 서로 방해하지 않는지. hook이 메모리 폴더와 Codex memories를 읽는지. #30이 먼저 병합되면 이 확인을 #32 병합 전에 실제 설치 상태로 다시 한다.
    - worktree에서 도는 make 타깃이 main checkout을 쓰는 경로: `.env` `-include`(VM 타깃), `backups/`(`make backup`), `.review-out/`(`review-post`, `review-record`), `log-exports/`(`export-logs`). 제외된 make 타깃은 sandbox 밖에서 돌므로 영향이 없어야 한다. sandbox 안에서 도는 타깃에서 깨지는 곳을 적는다.
- [ ] **Step 3:** 결과로 정한다: 1-C 유지 또는 1-B, 8-B 또는 8-A, `excludedCommands`·`allowedDomains` 최종 목록, `export-logs` 출력 위치. Progress log에 `Verified`로 남긴다.
- [ ] **Step 4:** 시험 키를 `.claude/settings.local.json`에서 지운다.

커밋: `docs: record the sandbox spike`, 트레일러 `Plan: k3bd8k47`, `Task: 1`.

### Task 2: Committed sandbox and permission rules

**Files:**
- Modify: `.claude/settings.json`
- Test: `tests/repo-config.bats`(새 `@test`, 리뷰어 테스트 `:223-248` 뒤)

동작: 스펙 3.2의 키를 Task 1이 정한 목록으로 넣는다. `permissions.allow` 8개는 그대로 둔다.

- [ ] **Step 1: 실패하는 테스트 작성:** `the Claude Code settings keep the sandbox on, deny only secret reads and backup deletion, and ask before outward or VM commands`. `jq`로 검사한다.
  - `.sandbox.enabled == true`, `.sandbox.allowUnsandboxedCommands == false`, `.permissions.blockReadsOutsideWorkingDirectories == true`(1-B로 물러섰으면 그 대신 main `.env` 상대 경로 deny)
  - `denyRead`에 `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`. `allowedDomains`가 비어 있지 않음
  - `excludedCommands`의 `*` 항목이 테스트에 고정한 목록 안에만 있음
  - `permissions.deny`의 모든 항목이 비밀값·노트 읽기 또는 `backups`·`basic-memory.prev` 삭제 규칙임
  - 스펙 3.2의 ask 항목이 모두 있음
  - 파일에 홈 디렉터리 절대 경로가 없음
  - 검사 함수가 키 하나를 지운 사본과 `make *`를 더한 사본에서 실패함
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: `.sandbox`가 null이라 새 테스트가 실패한다.
- [ ] **Step 3: 최소 구현:** `.claude/settings.json`에 키를 넣는다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋:** `feat: enable the Claude Code sandbox and ask before outward and VM commands`, `Task: 2`.

### Task 3: Bash guard hook

**Files:**
- Create: `scripts/guard-agent-bash.sh`, `tests/guard-agent-bash.bats`(`make new-script`)
- Modify: `.claude/settings.json`(`hooks.PreToolUse`), `tests/repo-config.bats`(훅 등록 검사)

동작(스펙 3.3): `.tool_input.command`를 읽는다.
- `rm`과 `backups`·`basic-memory.prev`가 함께 있으면 exit 2와 stderr 안내.
- force-push 계열(`push`와 `--force`, `--force-with-lease`, ` -f`, `+refspec`)과 VM 변경 스크립트(`restore-notes.sh`, `deploy-stack.sh`, `bootstrap-vm.sh`, `upload-sb-fonts.sh`) 직접 호출, `script`·`expect`와 `restore`가 함께 있을 때는 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":...}}`.
- 그 밖에는 exit 0, 출력 없음.
- 오류나 잘못된 입력에서는 exit 2(fail closed, `guard-reviewer-bash.sh`와 같은 방식).

- [ ] **Step 1: 실패하는 테스트 작성:** 표 형식으로 deny·ask·통과 사례. 우회 형태(`sh -c '...'`, `env git push --force`, `git -C . push -f`, `git push origin +main`)와 정상 사례(`git push origin plan/x`, `rm -rf .review-out`, 평범한 `git log`), 잘못된 JSON.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 스크립트가 없어 실패한다.
- [ ] **Step 3: 최소 구현:** 스크립트와 `hooks.PreToolUse` 등록(`"$CLAUDE_PROJECT_DIR"/scripts/guard-agent-bash.sh || exit 2`).
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: add the agent Bash guard hook for backup deletion and force-push`, `Task: 3`.

### Task 4: Test containers without network

**Files:**
- Modify: `Makefile:43`(`DOCKER_RUN`)
- Test: `tests/repo-make.bats`(`DOCKER_RUN`에 `--network none`이 있음)

- [ ] **Step 1: 실패하는 테스트 작성:** `test containers run without network`.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 테스트가 실패한다.
- [ ] **Step 3: 최소 구현:** `DOCKER_RUN`에 `--network none`.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0(lint, test, coverage, secret-scan이 네트워크 없이 돈다).
- [ ] **Step 5: 커밋:** `feat: run the test containers without network`, `Task: 4`.

### Task 5: Release-notes reader and PR comment filter

**Files:**
- Create: `.claude/agents/release-notes-reader.md`
- Modify: `.agents/skills/bm-upgrade/SKILL.md:35`(3단계), `:23`(체크리스트 3번), `.agents/skills/git-workflow/references/review-and-merge.md`
- Test: `tests/repo-config.bats`

동작(스펙 3.5): 독자는 `tools: WebFetch`, `disallowedTools: Bash, Write, Edit, NotebookEdit`이고 고정 형식으로 답한다. 3단계는 Claude Code에서는 독자에게, 다른 도구에서는 사용자에게 같은 형식을 요청한다. 요약은 사용자 확인을 거친다. PR 댓글은 머신 계정과 사용자 계정의 것만 읽는다. 거르는 명령이 스크립트가 되면 `script-authoring`을 따른다.

- [ ] **Step 1: 실패하는 테스트 작성:** `the release-notes reader has no shell or write tool and bm-upgrade hands step 3 to it`.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 독자 정의가 없어 실패한다.
- [ ] **Step 3: 최소 구현:** 독자 정의, 스킬 3단계·체크리스트, review-and-merge의 댓글 규칙.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0(`repo-skills.bats`, `repo-cloud-neutral.bats` 포함).
- [ ] **Step 5: 커밋:** `feat: read release notes in a role without credentials and filter PR comments by author`, `Task: 5`.

### Task 6: Restore confirmation from the terminal

**Files:**
- Modify: `scripts/restore-notes.sh:67-71`(`confirm`), `:11`(Usage 주석)
- Test: `tests/restore-notes.bats:36-38`(`restore_with_answer`), `:142`(거부 사례 표)

동작(스펙 3.6): `confirm`은 `/dev/tty`에서만 읽는다. 열 수 없으면 ssh 전에 `die`로 끝나고, 사용자 터미널에서 `make restore`를 실행하라고 안내한다. 시험용 입구는 두지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성:** 거부 사례 표에 `piped yes without a terminal`을 더한다(`$STUB_LOG`에 ssh 호출 없음). `restore_with_answer`는 `script`로 만든 pty로 답을 넘긴다(16곳 그대로, `@test` 수 유지).
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 지금 코드는 파이프 `yes`를 받아 새 사례가 실패한다.
- [ ] **Step 3: 최소 구현:** `read`를 `/dev/tty`로 돌리고, 열기 실패를 `die`로 바꾼다(bash 3.2).
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `fix: read the restore confirmation from the terminal, not stdin`, `Task: 6`.

### Task 7: Codex reviewer environment

**Files:**
- Modify: `scripts/review-branch.sh:184,187`
- Test: `tests/review-branch.bats`

동작(스펙 3.7): codex 호출에 `-c 'shell_environment_policy.inherit="core"'`, `-c 'shell_environment_policy.ignore_default_excludes=false'`. Task 1이 8-B를 확인했으면 `--sandbox read-only`·`sandbox_mode` 대신 `-c` permission profile(`~/.ssh`, `~/.config/gcloud`, `~/.config/gh`, 실행 시점에 계산한 main `.env` deny, 네트워크 끔).

- [ ] **Step 1: 실패하는 테스트 작성:** codex stub이 받은 인자에 환경 정책(과 profile)이 있음.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 새 사례가 실패한다.
- [ ] **Step 3: 최소 구현:** 인자를 더한다.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: strip tokens from the Codex reviewer and deny its credential reads`, `Task: 7`.

### Task 8: Main checkout access from worktrees

**Files:**
- Create: 9-A 읽기 전용 스크립트와 bats(`make new-script`, 이름은 `script-authoring`의 동사 규칙), Make 타깃
- Modify: `Makefile`, `.claude/settings.json`(`excludedCommands`), `.agents/skills/bm-recover/SKILL.md:37`, `.agents/skills/git-workflow/references/review-and-merge.md:14,40`, Task 1 결과에 따라 `scripts/export-logs.sh` 또는 문서

동작(스펙 3.8): 새 타깃은 main `backups/`의 최신 archive 경로와 `.sha256`·`.manifest`가 있는지만 출력한다(내용은 출력하지 않는다). `bm-recover` 2단계가 그 타깃을 부른다. worktree 세션의 리뷰 보고서와 로그 내보내기는 worktree 안에 둔다. archive 옮기기는 사용자에게 명령을 알려 주고 맡긴다.

- [ ] **Step 1: 실패하는 테스트 작성:** fixture `backups/`(가짜 archive와 체크섬)로 최신 경로와 확인 결과를 출력하고, archive가 없으면 해결 방법을 담아 실패하는 사례.
- [ ] **Step 2: 실패 확인:** Run: `make test` / Expected: 스크립트가 없어 실패한다.
- [ ] **Step 3: 최소 구현:** 스크립트, 타깃, 제외 목록, 스킬과 reference.
- [ ] **Step 4: 통과 확인:** Run: `make check` / Expected: exit 0.
- [ ] **Step 5: 커밋:** `feat: let worktree sessions find the latest backup without reading the main checkout`, `Task: 8`.

### Task 9: Trifecta ADR and docs

**Files:**
- Create: `make new-doc TYPE=adr SLUG=agent-trifecta`
- Modify: `docs/decisions/adr-2026-10-27-0svs72hp-prose-only-invariants.md`(표), `docs/ARCHITECTURE.md:89-98`(신뢰 경계)

동작(스펙 3.9): ADR에 스펙 3.1의 역할별 표와 잔여 위험(제외 명령의 write-then-run, sandbox 밖 도구, 문자열·훅 우회, bypass 모드, WebFetch, 10-B)을 적는다. ADR `0svs72hp` 표의 force-push, `backups` 삭제, VM 변경 전 묻기, restore `yes` 칸을 "일부"로 바꾸고 근거로 Task 2·3·6 테스트를 적는다.

- [ ] **Step 1:** 새 테스트는 없다. `tests/repo-docs.bats`가 이름, front matter, 링크를 검사한다.
- [ ] **Step 2:** Run: `make check` / Expected: exit 0.
- [ ] **Step 3: 커밋:** `docs: record the agent trifecta decision`, `Task: 9`.

### Finish: review and hand-off

- [ ] 완료 조건 7(Manual 모드 새 세션: `make deploy`·`git push`·`git push --force` 프롬프트를 확인하고 거절, 미끼 `backups` 경로 `rm` 차단)을 Progress log에 `Verified`로 적는다.
- [ ] Progress log에 그날 `make check` 결과를 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 세션의 설정에 영향을 주므로, 리뷰 대기로 넘기기 전과 병합 전에 감독 세션에 알린다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 사용자 OK를 받고 `gh pr ready <PR>`을 실행한다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 제3자 스킬·플러그인 고정(marketplace `sha`, `autoUpdate`)은 사용자 설정의 일이라 이 계획에서 뺀다.
- 옛 공개 커밋의 세션 링크(평가 AP10)는 이 계획 밖이다. 이력 재작성은 `AGENTS.md:33`이 금지한다.
- 다른 에이전트가 MCP로 쓴 Basic Memory 노트를 신뢰할 수 없는 입력으로 볼지 정한다. MCP 서버는 sandbox 밖에서 돈다.
- Gemini CLI·Antigravity의 sandbox 설정(지금 `.gemini/settings.json`에는 `context.fileName`만 있다)과 Codex 작성 세션의 다리 점검.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-27 | Reported | 스펙 승인 전 사실 재확인(b64b86e)과 문서 확인은 스펙 2절에 있다. 원래 계획(2026-10-22)의 Facts와 Design questions는 스펙 1·2절로 옮겼다. |
| 2026-10-27 | Verified | Start: `make check` exit 0(total line coverage 89.06%), `make check-git` OK, `scripts/check-public-text.sh`(스펙·계획·PR 본문) 0건. dfbdd82 push, 초안 PR #32. |
