---
status: accepted
id: zaptc3gp
date: 2026-10-28
---

# ADR zaptc3gp: 어느 에이전트 역할도 자격증명, 신뢰할 수 없는 입력, 외부 통신을 한꺼번에 쥐지 못하게 하고, 쥐어야 하는 곳은 사람이 확인한다

- 설계: [에이전트 sandbox와 권한 스펙](../specs/spec-2026-10-27-mpgrfpvn-agent-sandbox.md), [계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md)

## 맥락과 문제

- 작성 에이전트(Claude Code)는 lethal trifecta의 세 다리를 모두 쥐고 있었다. 세 다리는 자격증명(`~/.ssh`, `gcloud`·`gh` 설정, main checkout `.env`), 신뢰할 수 없는 입력(WebFetch, PR 댓글, 릴리스 노트), 외부 통신(`curl`, `git push`, `gh`)이다.
- 파괴적 명령(force-push, `backups/` 삭제, VM 변경)에 대한 사용자 OK는 `AGENTS.md` 문장으로만 지켜졌다. [prose-only ADR](adr-2026-10-27-0svs72hp-prose-only-invariants.md) 표에서 이 규칙들은 "검사 없음"이었다.
- 목표는 어느 역할도 세 다리를 동시에 쥐지 않게 하거나, 쥐더라도 사람의 확인 지점을 거치게 하는 것이다.

## 검토한 대안

스펙 1절의 결정마다 사용자가 고른 대안은 아래 결정에 적었다. 여기서는 큰 갈림길만 둔다.

1. 문장으로만 유지: 비용이 없다. 위 문제가 그대로 남는다.
2. 프로젝트 `.claude/settings.json`의 sandbox, ask·deny, PreToolUse 훅과 읽기 전용 서브에이전트(선택): 커밋되어 테스트할 수 있고 worktree 세션이 그대로 받는다. 사용자 설정과 다른 도구의 작성 세션은 덮지 못한다.
3. 사용자 설정(`~/.claude/settings.json`, `~/.codex/config.toml`)에서 막기: 커밋되지 않아 테스트할 수 없다.

## 결정

1. **Verified (2026-10-28):** 사용자가 스펙 결정 0~11을 승인했다.
2. 셸 명령은 sandbox 안에서 돈다(`allowUnsandboxedCommands: false`). `denyRead`는 `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`, main `.env`다. 허용 도메인은 `github.com`, `api.github.com`뿐이다. 제외 명령은 고정 목록이다(테스트 계열 make 타깃은 정확한 문자열, 변수를 받거나 Docker·ssh·VM에 닿는 타깃은 `make <t> *`, `gh *`, `gcloud *`, `git push *`).
3. 결정 1의 1-C(`permissions.blockReadsOutsideWorkingDirectories: true`)는 쓰지 않고 사용자가 미리 승인한 대체안 **1-B**로 물러선다. **Verified (2026-10-27):** Task 1 spike에서 1-C는 Read 도구의 scratchpad 읽기와 sandbox 안 홈 디렉터리 읽기(auto memory, transcript)를 막아 감독 세션 운영을 깼다. 1-B에서는 이것들이 읽혔고 worktree 미끼, main `.env`, 임의 도메인 `curl`은 막혔다. 증거는 계획의 Progress log(2026-10-27 행)에 있다. main `.env`는 sandbox `denyRead`의 상대 경로와 `Read(~/**/.env)` deny로 막는다(`Read(../../../.env)`는 맞지 않았다).
4. deny는 두 종류만 둔다(결정 11). 비밀값·노트 읽기와 `backups`·`basic-memory.prev` 삭제다. force-push를 포함한 나머지는 ask다: `git push`(force 형태 포함), `gh pr create/edit/comment/ready`, `make review-post`, `make review-record`, VM을 바꾸는 make 타깃, `gcloud` 생성·삭제, `make memory-hooks`. `AGENTS.md`의 "never"는 그대로다. 에이전트는 force-push를 요청하지 않고 ask는 마지막 방어선이다.
5. 규칙 문자열이 놓치는 호출은 PreToolUse 훅 `scripts/guard-agent-bash.sh`가 명령 전체에서 찾는다(`sh -c`, `env`, `git -C`, 스크립트 직접 호출, `-fu` 같은 합친 플래그, `script`·`expect`로 감싼 restore).
6. 릴리스 노트는 WebFetch만 가진 서브에이전트 `release-notes-reader`가 읽고 고정 형식으로 요약한다. PR 댓글은 머신 계정과 사용자 계정이 쓴 것만 작성 세션이 읽는다.
7. `restore-notes.sh`의 `confirm`은 `/dev/tty`에서만 읽는다. Docker 테스트 컨테이너는 `--network none`이다.
8. Codex 리뷰어는 `-c`로 토큰 환경 변수를 빼고(`shell_environment_policy`) permission profile로 `~/.ssh`, `~/.config`, main `.env` 읽기를 deny한다. `~/.config` 전체를 막는 것은 `scripts/`에 클라우드 CLI 디렉터리 이름을 쓰지 못하게 하는 `tests/repo-cloud-neutral.bats` 때문이고, git은 이것 없이 동작함을 확인했다.
9. worktree 세션은 main checkout을 읽지 않는다. 최신 backup은 읽기 전용 `make backup-latest`(`scripts/show-backup.sh`)가 경로와 체크섬 결과만 알려 주고, 리뷰 보고서와 로그 내보내기는 worktree 안 `REVIEW_OUT_DIR`, `LOG_EXPORT_DIR`에 둔다. main `backups/`로 옮기는 일은 사용자가 한다.
10. main checkout에서 여는 세션은 셸로 `.env`를 읽을 수 있다(결정 10-B). 감독 세션은 worktree 코드를 실행하지 않는다는 운영 규칙에 기댄다.

### 역할별 세 다리 (구현 후)

**Verified (2026-10-28):** 아래는 이 브랜치의 파일을 열어 확인한 값이다.

| 역할 | 자격증명 | 신뢰할 수 없는 입력 | 외부 통신 | 끊는 기제 |
|---|---|---|---|---|
| 작성 메인 세션 (Claude) | sandbox 안에서는 `~/.ssh`, `~/.config/gcloud`, `~/.config/gh`, main `.env`를 못 읽는다. 제외 명령(`gh`, `gcloud`, `git push`, ssh를 쓰는 make 타깃)은 자격증명을 쓴다. Read 도구는 `deny`가 비밀 경로를 막지만 worktree 밖 다른 파일은 읽는다(1-B) | WebFetch(남음), PR 댓글(작성자 필터) | Bash는 허용 도메인 두 개뿐. push·PR 게시·VM 변경은 ask. 제외 명령은 sandbox 밖 | `.claude/settings.json`의 `sandbox`·`permissions`·`hooks`, `scripts/guard-agent-bash.sh`. 테스트: `tests/repo-config.bats`의 "the Claude Code settings keep the sandbox on, …", `tests/guard-agent-bash.bats` |
| 작성 서브에이전트 | 부모와 같음 | 부모와 같음 | 부모와 같음 | 부모 설정 상속 |
| 릴리스 노트 독자 | 없음(Bash·쓰기 도구 없음) | 있음(릴리스 노트) | WebFetch만 | `.claude/agents/release-notes-reader.md` 도구 목록. 테스트: `tests/repo-config.bats`의 "the release-notes reader has no shell or write tool and bm-upgrade hands step 3 to it" |
| Codex 리뷰어 | 토큰 환경 변수 제거, `~/.ssh`·`~/.config`·main `.env` 읽기 deny | 리뷰 대상 브랜치 | 없음(네트워크 꺼짐) | `scripts/review-branch.sh`의 `-c` 인자. 테스트: `tests/review-branch.bats`의 "both codex calls strip token-like env vars and run under a deny profile …", "the deny path of the main .env is quoted for TOML …" |
| Claude `branch-reviewer` | 쓰기 도구 없음. 읽기는 기존 가드 훅 범위 | 리뷰 대상 브랜치 | 없음(`git diff/log/show`만) | `.claude/agents/branch-reviewer.md`, `scripts/guard-reviewer-bash.sh`. 테스트: `tests/repo-config.bats`의 "the Claude reviewer agent cannot edit files and runs every Bash call through the guard hook, …" (이 계획이 바꾸지 않았다) |
| CI | GitHub 토큰(Actions) | PR 내용 | 있음 | 범위 밖(기존 ruleset) |

## 결과

좋아지는 것:
- push, PR 게시, VM 변경, force-push는 bypass 모드에서도 매번 프롬프트가 뜬다(ask는 bypass에서도 남는다). `backups`·`basic-memory.prev` 삭제는 사람이 승인해도 실행되지 않는다.
- 작성 세션의 셸 명령이 `~/.ssh` 등 자격증명 경로와 임의 도메인에 닿지 못한다. 릴리스 노트는 쓰기 수단이 없는 역할이 읽는다. restore 확인은 에이전트가 파이프로 넘길 수 없다.

치르는 것(잔여 위험):
- **Assumption:** 제외 명령 범주마다 사용자 권한 전체로 돈다. `make check` 같은 제외 타깃은 에이전트가 고친 Makefile과 테스트를 sandbox 밖에서 실행한다(write-then-run). 막는 것은 컨테이너 네트워크(`--network none`)뿐이고, 호스트 쪽 레시피 줄은 막지 못한다. 리뷰가 Makefile·테스트 변경을 본다.
- sandbox 밖에서 도는 도구는 sandbox가 닿지 않는다: Read 도구(비밀 경로는 `deny`가, 그 밖은 1-B라 읽힌다), WebFetch, 훅, 로컬 MCP 서버.
- 문자열·훅 검사는 우회할 수 있다. 변수·인코딩, `env VAR=x scripts/<VM 스크립트>`, VM 스크립트 앞의 `xargs`·`nohup`·`time`·`exec` 래퍼, `HEAD:+x` 같은 refspec 형태의 force-push는 훅이 잡지 못한다. push·게시 ask가 마지막 확인 지점이다. 반대로 `rm`과 `backups`가 한 명령에 있으면 막으므로 안전한 쪽의 오탐이 있다.
- bypass 모드(권한 확인 건너뛰기)에서는 allow 규칙이 의미 없어지고 ask·deny와 훅만 남는다. sandbox는 그대로 적용된다.
- WebFetch로 들어오는 외부 글과 URL을 통한 유출은 남는다. WebFetch·WebSearch는 그대로 두었다. 외부로 나가는 명령은 ask다.
- main checkout 세션은 셸로 `.env`를 읽을 수 있다(결정 10-B). Read 도구는 `deny`로 막힌다.
- restore를 `script`·`expect`로 pty를 만들어 부르면 확인 질문을 넘길 수 있다. 훅은 그 형태를 ask로만 묻는다(deny 아님).
- **Reported (Claude Code 문서):** worktree 세션도 main checkout의 추적되지 않는 `.claude/settings.local.json`을 읽고 승인한 권한을 거기에 저장한다. 새 설정을 약하게 만드는 allow가 그 파일에 생길 수 있다. 2026-10-27에 이 파일을 점검했을 때 겹치는 allow는 없었다.
- Codex 리뷰어는 `~/.config` 전체를 읽지 못한다. 리뷰에 필요하지 않다고 확인했다.
- Codex·Gemini CLI·Antigravity 작성 세션은 바뀌지 않는다(범위 밖).
- 이 설정은 다른 세션의 프롬프트를 늘린다. 병합 전에 감독 세션에 알리고, 병합 뒤 worktree 세션은 `git merge origin/main`과 재시작이 필요하다.
- 확인 방법: `tests/repo-config.bats`의 설정·독자 사례(Task 2, 5), `tests/guard-agent-bash.bats`(Task 3), `tests/repo-make.bats`의 "test containers run without network"(Task 4), `tests/restore-notes.bats`의 "restore refuses before any ssh when the answer is not yes, …"(Task 6), `tests/review-branch.bats`(Task 7), `tests/show-backup.bats`(Task 8). `make check`가 이들을 모두 돌린다. 새 세션에서 `git push`·`make deploy`의 프롬프트와 미끼 `backups` 경로 `rm` 차단을 보는 수동 확인은 계획의 Progress log에 적는다.
