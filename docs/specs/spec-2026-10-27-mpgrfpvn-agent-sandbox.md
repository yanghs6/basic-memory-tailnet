---
status: approved
id: mpgrfpvn
date: 2026-10-27
---

# 에이전트 sandbox와 권한 — 설계

- 구현 계획: [agent-sandbox 계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md). 계획 하나와 PR 하나로 이 스펙 전체를 구현한다(7절).

## 1. 목적과 범위

작성 에이전트(Claude Code)는 지금 lethal trifecta의 세 다리를 모두 쥔다. 세 다리는 자격증명, 신뢰할 수 없는 입력, 외부 통신이다. 파괴적 명령에 대한 사용자 OK도 AGENTS.md 문장으로만 지켜진다. 이 스펙은 다음 세 가지를 정한다.
- 셸 명령을 sandbox에 넣는다.
- 밖으로 나가는 명령과 VM을 바꾸는 명령은 설정과 훅으로 묻거나 막는다.
- 외부 글은 쓰기 수단이 없는 역할이 읽는다.

목표는 어느 역할도 세 다리를 동시에 쥐지 않게 하거나, 쥐더라도 사람의 확인 지점을 거치게 하는 것이다.

**사용자 결정 (2026-10-27)**
0. 백로그 승인: 계획 k3bd8k47을 brainstorming → 스펙 → 계획 순서로 진행한다.
1. 자격증명 경로(1-C): 프로젝트 설정에서 `~/` 경로(`~/.ssh`, `~/.config/gcloud`)를 막고, `permissions.blockReadsOutsideWorkingDirectories: true`로 worktree 밖 전체(main checkout `.env` 포함)를 막는다. Task 1에서 git이나 `make`의 `-include`가 깨지면, main `.env`를 상대 경로(1-B)로 막는 쪽으로 물러선다.
2. `make check`와 Docker(2-B): 테스트 계열 make 타깃을 정확한 문자열로 sandbox 제외 목록에 넣는다. 함께 `DOCKER_RUN`에 `--network none`을 더한다. Makefile 레시피 줄이 sandbox 밖에서 도는 위험은 ADR에 적는다.
3. 자격증명 CLI(3-B): `gh`, `gcloud`, ssh를 쓰는 make 타깃은 sandbox에서 제외한다. 밖으로 내보내는 명령만 ask로 묻는다: `git push`, `gh pr create/edit/comment/ready`, `make review-post`, `make review-record`. VM 읽기 타깃과 `gh` 조회는 묻지 않는다.
4. 규칙 종류(4-B): force-push와 `backups`·`.prev-*` 삭제는 deny다. VM 변경 make 타깃과 gcloud 생성·삭제는 ask다. 문자열 규칙을 피해 가는 호출(`sh -c`, `env`, `git -C`, 스크립트 직접 호출)은 커밋한 PreToolUse 훅이 명령 전체에서 부분 문자열을 찾아 막거나 묻는다.
5. 네트워크(5-A): Bash 허용 도메인은 `github.com`, `api.github.com`에 Task 1에서 필요하다고 확인한 것만 더한다. WebFetch와 WebSearch는 지금처럼 둔다. 남는 위험은 ADR에 적는다.
6. 입력 분리(6-A): Claude Code에서는 WebFetch만 가진 독자 서브에이전트가 릴리스 노트를 읽고 고정 형식으로 요약한다. 작성 세션은 그 요약을 사용자에게 보이고 확인을 받는다. 다른 도구에서는 사용자가 릴리스 노트를 읽고 같은 형식으로 답한다. PR 댓글은 머신 계정과 사용자 계정이 쓴 것만 작성 세션이 읽는다.
7. restore 확인(7-A): `restore-notes.sh`의 `confirm`은 `/dev/tty`에서만 읽는다. 시험용 입구는 두지 않는다. 테스트는 `script`로 만든 pty로 답을 넘긴다.
8. Codex 리뷰어(8-B): `review-branch.sh`가 `-c` 인자로 다음 두 가지를 넘긴다.
   - `shell_environment_policy`로 토큰이 담긴 환경 변수를 뺀다.
   - `--sandbox` 대신 permission profile을 써서 `~/.ssh`, `~/.config/gcloud`, main `.env` 읽기를 deny한다.
   Task 1에서 profile을 `-c`로 줄 수 없다고 확인되면, 환경 변수만 빼는 쪽(8-A)으로 물러선다.
9. worktree에서 main checkout을 쓰는 절차(9-A):
   - 필요한 읽기는 sandbox 밖에서 도는 읽기 전용 make 타깃으로 만든다. 예를 들어 최신 backup 경로와 체크섬 확인 결과만 출력하는 타깃이다.
   - 리뷰 보고서와 로그 내보내기는 worktree 안 디렉터리에 둔다(`REVIEW_OUT_DIR`, `LOG_EXPORT_DIR`).
   - archive를 main `backups/`로 옮기는 일은 사용자 몫이다.
10. main checkout 세션의 `.env`(10-B): sandbox `denyRead`에 `./.env` 등을 더하지 않는다. main checkout에서 연 세션(감독 세션)은 셸로 `.env`를 읽을 수 있다. 이것은 ADR에 잔여 위험으로 적는다. 기존 `Read(./.env)` deny는 Read 도구에만 걸린다.
11. deny는 최소로 한다(결정 4를 좁힌다). deny에는 되돌릴 수 없는 두 가지만 둔다.
    - 비밀값과 노트 내용 읽기: `.env`, `backups/`, `.local-data/`, `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`
    - `backups/`와 `/srv/basic-memory.prev-*` 삭제
    force-push를 포함해 나머지 파괴적 명령은 모두 ask다. AGENTS.md:33의 "never"는 그대로 둔다. 에이전트는 force-push를 요청하지 않고, ask는 마지막 방어선이다. `blockReadsOutsideWorkingDirectories`는 명령 규칙이 아니라 경로 울타리로 결정 1에 따라 남긴다. Task 1에서 정당한 읽기(scratch 디렉터리 등)를 많이 막으면 1-B로 물러선다.

**범위 밖**
- Codex·Gemini CLI·Antigravity **작성** 세션의 sandbox: 계획 Follow-ups에 둔다. Codex는 리뷰어만 다룬다.
- 제3자 스킬·플러그인 고정: 사용자 설정의 일이다.
- 사용자 설정 `~/.claude/settings.json`과 `~/.codex/config.toml` 변경: 커밋되지 않아 테스트할 수 없다. 사용자 결정 1·8에서 프로젝트 쪽을 골랐다.
- Basic Memory MCP 노트를 신뢰할 수 없는 입력으로 볼지: 계획 Follow-ups에 둔다.

**완료 조건**
1. `make check`가 통과한다. 새 `tests/repo-config.bats` 사례가 다음 경우에 실패한다.
   - sandbox 키, ask·deny 항목, 훅 등록 가운데 하나가 빠졌을 때
   - 정해진 목록 밖의 제외 항목에 `*`가 들어갔을 때
   - `permissions.deny`에 결정 11의 두 종류 밖의 항목이 생겼을 때
2. 가드 훅(`scripts/guard-agent-bash.sh`)의 bats 테스트가 다음을 확인한다.
   - `backups`·`.prev-*` 삭제를 우회 형태 포함 exit 2로 막는다.
   - force-push(우회 형태 포함)와 VM 변경 스크립트 직접 호출에 ask를 낸다.
   - 일반 명령은 통과시킨다.
3. 파이프로 넘긴 `yes`로 `restore-notes.sh`를 실행하면 ssh를 부르기 전에 실패한다. `@test` 수는 줄지 않는다.
4. `review-branch.sh` bats가 codex 호출 인자에 환경 정책을 확인한다. Task 1 결과에 따라 permission profile도 확인한다.
5. 독자 서브에이전트 정의에 Bash와 쓰기 도구가 없는지 테스트가 확인한다.
6. trifecta ADR이 `accepted`이고, ADR `0svs72hp` 표가 이번에 검사가 생긴 칸을 고쳤으며, `ARCHITECTURE.md` 신뢰 경계에 에이전트 항목이 있다.
7. 새 세션을 Manual 모드로 열어 다음을 확인하고 Progress log에 남긴다.
   - `make deploy`와 `git push`에서 프롬프트가 뜬다(거절한다).
   - `git push --force`에서 프롬프트가 뜨고(거절한다), `backups`를 지우는 `rm`은 막힌다(미끼 경로로 시험).

## 2. 근거가 된 사실 (2026-10-27, `main` b64b86e, `fe7eb38`에서 일부 다시 확인)

- **Verified (`fe7eb38`):** `make export-logs`(`Makefile:158`)는 기본으로 main checkout의 `log-exports/`에 쓰고, `LOG_EXPORT_DIR`이 있으면 그 위치를 쓴다(`scripts/export-logs.sh:36-42`).
- **Verified:** `.claude/settings.json:6-22`에는 allow(make 타깃 8개, `:7-16`)와 Read deny 3개(`:17-21`)만 있다. sandbox, Bash ask·deny, hooks는 없고, 이 파일을 지키는 테스트도 없다.
- **Verified:** force-push 금지(`AGENTS.md:33`), `backups` 삭제 금지(`:25`), VM 변경 전 묻기(`:24`), restore `yes`를 파이프로 넘기지 않기(`:28`)는 모두 검사가 없다(ADR `0svs72hp` 표 `:58,59,62,66`). 검사를 더하는 PR은 그 표도 함께 고친다(`:82`).
- **Verified:** `restore-notes.sh:67-71`의 `confirm`은 stdin에서 읽는다. `tests/restore-notes.bats:36-38`의 helper가 파이프로 답을 넘기고, 이 helper를 `restore_with_answer yes` 형태로 16곳에서 부른다.
- **Verified:** `Makefile:43` `DOCKER_RUN`에는 `--network` 옵션이 없다. `gateway-lock`(`:105`)과 `tools-image`(`:51`)는 `DOCKER_RUN`을 쓰지 않는다.
- **Verified:** `review-branch.sh`의 codex 호출(`:184`, `:187`)은 `sandbox_mode="read-only"`·`--sandbox read-only`를 쓰고 stdin을 닫는다. 환경 변수는 거르지 않는다.
- **Verified:** `.agents/skills/bm-upgrade/SKILL.md:35` 3단계에서는 작성 에이전트가 릴리스 페이지를 직접 연다. `BM_WEB=on`이면 바뀐 도구를 `ALLOWED_TOOLS`와 비교한다.
- **Verified (문서, https://code.claude.com/docs/en/sandboxing.md):**
  - `excludedCommands`는 호출 문자열과 맞춘다. 제외된 명령은 사용자 권한 전체로 돈다.
  - `docker`는 sandbox와 함께 쓸 수 없다. `gh`·`gcloud`는 Seatbelt에서 TLS 검증에 실패할 수 있다.
  - Read, WebFetch, 훅, 로컬 MCP는 sandbox 밖에서 돈다. 서브에이전트는 부모의 sandbox를 그대로 쓴다.
  - `sandbox.network.strictAllowlist`는 저장소 설정에서 효과가 없다.
- **Verified (문서, https://code.claude.com/docs/en/permissions.md):**
  - 평가 순서는 deny → ask → allow다.
  - bypass 모드에서 allow는 효과가 없다. deny는 막고, 명시한 ask는 묻는다.
  - 앞에서 벗겨 내는 래퍼는 고정 목록(`timeout`, `nice`, `xargs` 등)이다. `env`와 `sh -c`는 규칙을 피해 간다.
  - 서브에이전트는 부모의 권한 규칙을 물려받는다.
- **Verified (문서, https://code.claude.com/docs/en/settings-reference.md):**
  - `permissions.blockReadsOutsideWorkingDirectories`는 v2.1.257 이상에서 동작한다. 설치된 버전은 2.1.311이다.
  - 어느 설정 파일에서든 `true`면 적용되고, file 도구는 모든 모드에서 거부한다. sandbox가 켜져 있으면 sandbox 안 명령에도 적용된다.
  - 저장소 settings의 `additionalDirectories`는 예외로 인정되지 않는다.
- **Verified (문서, https://code.claude.com/docs/en/hooks.md):** PreToolUse 훅이 exit 2로 끝나면 호출이 막힌다. 훅이 allow를 내도 deny·ask 규칙을 넘지 못한다.
- **Verified (문서, https://learn.chatgpt.com/docs/config-file/config-reference, 로컬 `codex sandbox` 실행):**
  - `shell_environment_policy.ignore_default_excludes`의 기본값은 `true`다. 그래서 `GH_TOKEN`이 `codex exec` 셸에 넘어간다.
  - `read-only`는 쓰기만 막는다(`~/.ssh` 목록 읽기가 성공했다). 네트워크는 꺼져 있다.
  - permission profile의 `"deny"`는 읽기를 막지만, `--sandbox`나 `sandbox_mode`가 있으면 무시된다(https://learn.chatgpt.com/docs/permissions.md).
- **Assumption:** sandbox 안에서 worktree의 git이 main `.git`(common dir)을 읽는 동작이 `blockReadsOutsideWorkingDirectories`에 막히는지는 문서에 없다. Task 1에서 시험한다.
- **Assumption:** 테스트 이미지(`tools/Dockerfile`)에 util-linux `script`가 있다. Task 1에서 확인한다.
- **Assumption:** 커밋한 `.claude/settings.json`이 바뀌면, 이미 실행 중인 세션은 재시작해야 새 설정을 읽는다.

## 3. 설계

### 3.1 역할별 세 다리 (적용 후)

| 역할 | 자격증명 | 신뢰할 수 없는 입력 | 외부 통신 | 끊는 기제 |
|---|---|---|---|---|
| 작성 메인 세션 (Claude) | 제외된 CLI만 씀. 파일 읽기는 worktree 안으로 제한 | WebFetch (남음) | push·게시는 ask | sandbox, `blockReads…`, ask 규칙, 가드 훅 |
| 작성 서브에이전트 | 부모와 같음 | 부모와 같음 | 부모와 같음 | 부모 설정 상속 |
| 릴리스 노트 독자 | 없음 (Bash·쓰기 없음) | 있음 | WebFetch만 | 서브에이전트 도구 목록, 테스트 |
| Codex 리뷰어 | 토큰 환경 변수 제거, 자격증명 경로 읽기 deny | 리뷰 대상 브랜치 | 없음 (네트워크 꺼짐) | `-c` 환경 정책, permission profile |
| Claude `branch-reviewer` | 파일 읽기는 worktree 안으로 제한 | 리뷰 대상 브랜치 | 없음 (`git diff/log/show`만) | 기존 가드 훅, `blockReads…` |
| CI | GitHub 토큰 (Actions) | PR 내용 | 있음 | 범위 밖 (기존 ruleset) |

### 3.2 Claude Code 프로젝트 설정 (`.claude/settings.json`)

- `sandbox.enabled: true`, `sandbox.allowUnsandboxedCommands: false`
- `sandbox.filesystem.denyRead`: `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`. `~/.config/gh`를 더한 것은 작성자 판단이다.
- `sandbox.network.allowedDomains`: `github.com`, `api.github.com`, 그리고 Task 1에서 필요하다고 확인한 도메인.
- `sandbox.excludedCommands`: 최종 목록은 Task 1 결과로 정한다.
  - 테스트 계열(인자 없이 쓰므로 정확한 문자열): `make check`, `make test`, `make lint`, `make coverage`, `make fmt`, `make check-git`
  - Docker·ssh를 쓰는 타깃: `make local-*` 각 타깃, `make probe|status|logs|export-logs|verify|backup|access-check|tunnel`, `make review`, `make review-post`, `make review-record`, VM 변경 타깃 4개, 9-A의 새 읽기 전용 타깃
    - 인자를 받는 타깃(`BRANCH=`, `PR=`, `BACKUP=`, `LOCAL=1`, `BM_WEB=on` 등)은 `make <타깃> *`로 쓴다. 정확한 문자열은 실제 호출과 맞지 않기 때문이다. 이 형태는 작성자 판단이다.
  - 자격증명 CLI: `gh *`, `gcloud *`, `git push *`. `gcloud`를 제외하는 것은 작성자 판단이다. `denyRead`가 `~/.config/gcloud`를 막으므로, 제외하지 않으면 OK 없이 허용된 `describe`/`list`까지 실패한다. `git push`는 제외하면서 ask도 건다.
  - `*`가 든 항목은 `tests/repo-config.bats`에 고정한 목록(위의 자격증명 CLI 3개와 인자를 받는 make 타깃)에만 허용한다. 목록 밖에 `*`가 있으면 테스트가 실패한다. `make *`, `docker *`, `bash *`처럼 넓은 패턴이 그 예다.
- `permissions.blockReadsOutsideWorkingDirectories: true`
- `permissions.deny` (결정 11: 이 두 종류만 둔다):
  - 비밀값과 노트 내용 읽기: 기존 Read 3개, `Read(~/.ssh/**)`, `Read(~/.config/gcloud/**)`, `Read(~/.config/gh/**)`
  - `backups`·`basic-memory.prev` 삭제 문자열 규칙
- `permissions.ask`:
  - force-push 문자열 규칙(`git push --force*`, `-f`, `--force-with-lease`, 중간 위치 `*`)
  - `Bash(git push *)`
  - `Bash(gh pr create *)`, `Bash(gh pr edit *)`, `Bash(gh pr comment *)`, `Bash(gh pr ready *)`
  - `Bash(make review-post *)`, `Bash(make review-record *)`
  - `Bash(make deploy *)`, `Bash(make restore *)`, `Bash(make vm-bootstrap *)`, `Bash(make sb-fonts *)`
  - gcloud 생성·삭제(`gcloud compute instances create|delete`, 방화벽 규칙 생성·삭제)
- 기존 `permissions.allow` 8개는 그대로 둔다. bypass가 아닌 모드에서 프롬프트를 줄여 준다.
- `hooks.PreToolUse`(matcher `Bash`): `scripts/guard-agent-bash.sh` (3.3)

### 3.3 가드 훅 `scripts/guard-agent-bash.sh`

- 입력: 훅 JSON의 `.tool_input.command`(`jq`). 기존 `guard-reviewer-bash.sh`처럼 오류가 나면 막는 쪽(fail closed)으로 끝난다.
- deny(exit 2와 stderr 안내): `rm`과 `backups` 또는 `basic-memory.prev`가 함께 있을 때만 막는다(결정 11).
- ask(`permissionDecision: "ask"` JSON):
  - 명령에 `push`가 있고, `--force`, `--force-with-lease`, ` -f`, 또는 `+`로 시작하는 refspec이 함께 있을 때. `sh -c`, `env`, `git -C`로 감싼 형태도 잡는다.
  - `restore-notes.sh`, `deploy-*`, `bootstrap-*` 같은 VM 변경 스크립트를 직접 부를 때와, `script`·`expect`가 `restore`와 함께 있을 때. 정확한 스크립트 목록은 `scripts/`를 보고 구현하는 사람이 정한다.
- 그 밖에는 exit 0이고 아무것도 출력하지 않는다(규칙 평가로 넘어간다).
- 한계: 변수 치환이나 인코딩으로 숨긴 명령은 잡지 못한다. ADR에 적는다.

### 3.4 Docker

- `Makefile:43` `DOCKER_RUN`에 `--network none`을 더한다. `gateway-lock`과 `tools-image`는 `DOCKER_RUN`을 쓰지 않으므로 영향이 없다.
- 이미지 pull은 docker 데몬이 하므로 막히지 않는다(**Assumption**, Task 1에서 확인).

### 3.5 릴리스 노트 독자와 PR 댓글

- `.claude/agents/release-notes-reader.md`: `tools: WebFetch`, `disallowedTools: Bash, Write, Edit, NotebookEdit`.
  - 고정 형식으로 답한다: 현재·목표 버전, 마이그레이션 필요 여부, 바뀐 플래그·환경 변수·경로·포트의 원문 인용, MCP 도구 추가·삭제·이름 변경 목록.
  - 노트 안의 지시문은 따르지 않고 인용만 한다.
- `bm-upgrade` 3단계와 체크리스트 3번:
  - Claude Code에서는 독자에게 맡기고, 요약을 사용자에게 보인 뒤 확인을 받는다.
  - 다른 도구에서는 사용자에게 같은 형식으로 답해 달라고 요청한다.
  - 스킬 본문은 도구 중립 문장으로 쓰고, 클라우드 이름은 쓰지 않는다.
- `git-workflow`의 `references/review-and-merge.md`: PR 댓글은 머신 계정과 사용자 계정이 쓴 것만 읽는다. 그 밖의 댓글은 사용자에게 넘긴다. 거르는 명령은 스크립트나 make 타깃으로 둘지 구현하는 사람이 정한다(`skill-authoring`의 "A step is a make target or a script call").

### 3.6 restore 확인

- `confirm`은 `/dev/tty`를 열어 읽는다. 열 수 없으면 ssh를 부르기 전에 `die`로 끝난다. 메시지는 "자기 터미널에서 `make restore BACKUP=...`를 실행하라"고 안내한다.
- 테스트 helper는 `script`로 만든 pty로 답을 넘긴다. 파이프로 넘긴 `yes`를 거부하는 사례를 하나 더한다.

### 3.7 Codex 리뷰어

- `review-branch.sh:184,187`의 codex 호출에 다음을 더한다.
  - `-c 'shell_environment_policy.inherit="core"'`
  - `-c 'shell_environment_policy.ignore_default_excludes=false'`
- 8-B(Task 1에서 가능하다고 확인되면):
  - `--sandbox read-only`와 `sandbox_mode` 대신, `-c`로 정의한 permission profile(`extends = ":read-only"`, 네트워크 끔)을 `-c default_permissions=...`로 고른다.
  - profile은 `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`, main `.env`를 deny한다.
  - main `.env` 경로는 스크립트가 `git rev-parse --git-common-dir`로 실행 시점에 계산한다. 그래서 커밋하는 파일에 절대 경로가 들어가지 않는다.

### 3.8 worktree에서 main checkout을 쓰는 절차 (9-A)

- 새 읽기 전용 make 타깃 하나: main `backups/`에서 최신 archive의 경로와 `.sha256`·`.manifest`가 있는지만 출력한다. 내용은 출력하지 않는다. 이름은 `script-authoring` 규칙에 맞춰 구현하는 사람이 정한다. 이 타깃은 sandbox 제외 목록에 넣고, `bm-recover` 2단계(`.agents/skills/bm-recover/SKILL.md:37`)가 이 타깃을 부르게 한다.
- `review-and-merge.md`: worktree 세션에서는 `REVIEW_OUT_DIR`을 worktree 안 `.review-out/`(gitignore)으로 둔다. `:14`에 이미 대안으로 나와 있으므로 이를 기본 절차로 바꾼다. archive를 main `backups/`로 옮기는 일(`:40`)은 사용자에게 명령을 알려 주고 맡긴다.
- `make export-logs`(PR #31, `fe7eb38`)는 기본으로 main checkout의 `log-exports/`에 쓴다. worktree 세션은 `LOG_EXPORT_DIR`을 worktree 안으로 둔다. 기본 출력 위치를 바꿀지, 문서에만 적을지는 구현하는 사람이 Task 1 결과를 보고 정한다.
- Claude 리뷰어(`claude -p --agent branch-reviewer`, `review-branch.sh:198`)도 새 프로젝트 설정(sandbox, 가드 훅, ask)을 받는다. `-p`에서는 ask가 거부로 처리된다. 리뷰가 그대로 도는지 Task 1에서 확인한다.

### 3.9 문서

- 새 trifecta ADR(`make new-doc TYPE=adr SLUG=agent-trifecta`): 3.1 표와 잔여 위험을 적는다.
- ADR `0svs72hp` 표: force-push, `backups` 삭제, VM 변경 전 묻기, restore `yes` 칸을 "일부"로 바꾸고 근거로 이번 테스트를 적는다.
- `docs/ARCHITECTURE.md` 신뢰 경계(`:89-98`)에 에이전트 항목 하나를 더한다.
- AGENTS.md는 고치지 않는 것을 기본으로 한다. 바꿀 줄이 생기면 사용자에게 먼저 묻는다.

### 3.10 적용 후 일하는 방식이 어떻게 바뀌는가

| 상황 | 지금 | 적용 후 |
|---|---|---|
| Claude 세션의 셸 명령 | 사용자 권한 전체로 돈다 | sandbox 안에서 돈다. 정해진 make 타깃과 `gh`만 밖에서 돈다 |
| `make check` | 그대로 돈다 | 그대로 돈다(제외 목록). 컨테이너는 네트워크가 없다 |
| `git push`, `gh pr create/comment/ready` | 묻지 않는다 | bypass 모드를 포함해 매번 프롬프트가 뜬다 |
| `make deploy/restore/vm-bootstrap/sb-fonts` | 문장으로만 묻는다 | 프롬프트가 뜬다. 스크립트를 직접 불러도 훅이 묻는다 |
| force-push | 문장으로만 금지한다 | 우회 형태까지 프롬프트가 뜬다(결정 11) |
| `backups`·`.prev-*` 삭제 | 문장으로만 금지한다 | 규칙과 훅이 막는다. 사람이 승인해도 실행되지 않는다 |
| worktree 밖 파일 읽기(main `.env`, `~/.ssh`) | `./.env` deny만 있어 worktree에서는 실제 `.env`를 막지 못한다 | Read 도구, `cat` 등, sandbox 안 명령 모두 거부된다 |
| `curl`로 임의 도메인 접속 | 된다 | 허용 목록 밖이면 sandbox가 사용자에게 묻는다 |
| WebFetch·WebSearch 조사 | 된다 | 그대로 된다 |
| `bm-upgrade` 릴리스 노트 | 작성 세션이 직접 읽는다 | 독자 서브에이전트의 고정 형식 요약을 사용자가 확인한다 |
| `make restore` | 파이프로 넘긴 `yes`도 받는다 | 사용자 터미널에서만 된다. `!` 모드에서 되는지는 Task 1에서 확인 |
| Codex 리뷰어 | `GH_TOKEN`이 넘어가고 `~/.ssh`를 읽을 수 있다 | 토큰 환경 변수가 빠지고, 자격증명 경로 읽기가 막힌다 |
| main checkout에서 여는 감독 세션 | 같다 | 같은 프로젝트 설정을 받는다. 병합 뒤 재시작하면 프롬프트가 늘어난다. 셸로 `.env`를 읽는 길은 남는다(10-B) |
| `bm-recover`의 backup 고르기 | 에이전트가 main `backups/`를 `ls` | 새 읽기 전용 make 타깃이 경로와 체크섬 확인 결과만 알려 준다 |
| 리뷰 보고서·로그 내보내기 | main checkout에 쓰고 읽는다 | worktree 세션은 worktree 안에 쓰고 읽는다 |
| worktree 정리 전 archive 옮기기 | 에이전트가 옮긴다 | 사용자가 옮긴다(에이전트가 명령을 알려 준다) |
| Codex·Gemini·Antigravity 작성 세션 | 같다 | 바뀌지 않는다(범위 밖) |

## 4. 보안

- 비밀값을 새로 만들지 않는다. 커밋하는 설정·훅·테스트에는 `~/`와 상대 경로만 쓴다. 절대 경로, IP, 세션 id는 쓰지 않는다(`check-public-text.sh`).
- 시험은 scratch 디렉터리의 미끼 파일로 한다. `.env`, `backups/`, `.local-data/`의 내용은 읽지도 출력하지도 않고, 성공·실패만 기록한다.
- 이 변경은 작성 세션의 권한을 줄이기만 한다. 공개로 노출되는 곳이나 인증에는 영향이 없다.

## 5. 테스트와 검증

- `tests/repo-config.bats`:
  - 설정 키를 검사하는 사례. 키 하나를 지운 사본에서 실패하는 것도 확인한다.
  - 독자 정의를 검사하는 사례.
- `tests/guard-agent-bash.bats`(`make new-script`): deny·ask·통과를 표 형식으로 검사한다. 우회 형태(`sh -c`, `env`, `git -C .`)를 포함한다.
- `tests/restore-notes.bats`: pty helper로 바꾸고, 파이프 거부 사례를 더한다. `@test` 수는 줄이지 않는다.
- `tests/review-branch.bats`: codex stub이 받은 인자를 검사한다.
- 수동 확인: Task 1 spike(Progress log `Verified`)와 완료 조건 7.
- 모든 커밋 전에 `make check`를 돌린다.

## 6. 위험과 대응

| 위험 | 대응 |
|---|---|
| `blockReads…`가 worktree의 git이 main `.git`을 읽는 것이나 scratch 디렉터리 읽기를 막는다 | Task 1에서 확인한다. 막히면 1-B(상대 경로)로 물러선다 |
| force-push가 ask라 사람이 실수로 승인한다 | `main`은 GitHub ruleset이 막는다. 작업 브랜치는 reflog와 원격 PR 이력으로 되살린다. 프롬프트에 훅이 이유를 적는다 |
| 제외된 make 타깃이 에이전트가 고친 Makefile을 sandbox 밖에서 실행한다 | `--network none`, ADR 잔여 위험, 리뷰 |
| 훅이 오탐으로 정상 명령을 막는다 | 테스트 표에 정상 사례를 넣고, 오류 메시지에 해결 방법을 담는다 |
| 문자열·훅 검사를 변수나 인코딩으로 피해 간다 | ADR 잔여 위험. push·게시 ask가 마지막 확인 지점이다 |
| WebFetch로 들어온 외부 글과 URL을 통한 유출 | ADR 잔여 위험. 외부로 나가는 명령은 ask |
| 병합 직후 다른 세션에 프롬프트가 늘거나 명령이 실패한다 | 병합 전에 감독 세션에 알린다. 진행 중 세션은 재시작 시점을 정한다 |
| Codex permission profile이 실험 기능이라 동작이 바뀐다 | 8-A로 물러설 수 있게 하고, bats로 인자를 고정한다 |
| main checkout 세션이 셸로 `.env`를 읽는다(10-B) | ADR 잔여 위험. 감독 세션은 worktree 코드를 실행하지 않는다는 운영 규칙에 기댄다 |
| 새 설정 때문에 복구 절차(`bm-recover`)가 막힌다 | 9-A 읽기 전용 타깃, Task 1에서 worktree 세션으로 2단계를 시험한다 |

## 7. 계획 분할

계획은 [agent-sandbox 계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md) 하나로 하고, PR도 하나로 한다.

| Task | 범위 |
|---|---|
| 1 | spike: sandbox·`blockReads…`·git·`make check`·`gh`·push·`script`·`!` tty·Codex profile·Claude 리뷰어(`claude -p`)·main `.env` `-include`를 시험한다(설정은 자기 worktree의 `settings.local.json`에만 두고, 사용자 OK를 받는다) |
| 2 | `.claude/settings.json`과 `repo-config.bats` |
| 3 | `guard-agent-bash.sh`와 그 bats, 훅 등록 |
| 4 | `DOCKER_RUN --network none` |
| 5 | 독자 서브에이전트, `bm-upgrade`, PR 댓글 거르기 |
| 6 | restore `/dev/tty` |
| 7 | Codex 리뷰어 `-c` 인자 |
| 8 | 9-A: 읽기 전용 backup 타깃, `bm-recover` 2단계, `review-and-merge.md`의 출력 위치·archive 옮기기, `export-logs` 출력 위치 |
| 9 | trifecta ADR, ADR `0svs72hp` 표, `ARCHITECTURE.md` |

## 8. Open questions

1. 없음. Task 1의 결과에 따라 물러서는 쪽(1-B, 8-A)은 이미 정해 두었다.
