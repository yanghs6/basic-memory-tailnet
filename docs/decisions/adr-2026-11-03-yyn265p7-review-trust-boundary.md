---
status: accepted
id: yyn265p7
date: 2026-11-03
---

# ADR yyn265p7: 리뷰 도구는 origin/main에서 가져오고, 리뷰 대상 브랜치의 코드는 컨테이너 안에서만 돌린다

- 대체 범위: [ADR zaptc3gp](adr-2026-10-28-zaptc3gp-agent-trifecta.md)(agent trifecta)의 역할별 표 중 "Claude `branch-reviewer`" 행과 잔여 위험의 "리뷰가 Makefile·테스트·훅 변경을 본다" 문장을 보완한다. 그 ADR의 결정 문장은 바꾸지 않는다.

## 맥락과 문제

2026-11-02 저장소 재검토(F05, F09, F10, P3-05)와 [k3bd8k47 계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md) Follow-ups가 같은 문제를 가리킨다. 리뷰 대상 브랜치가 자기 리뷰어를 바꿀 수 있다.

**Verified (코드, 2026-11-03):**
- `scripts/review-branch.sh:222-226`은 리뷰 대상 브랜치의 detached worktree에서 `claude -p --agent branch-reviewer`를 실행한다. 리뷰어 정의(`.claude/agents/branch-reviewer.md`), 가드 훅(`scripts/guard-reviewer-bash.sh`), `.claude/settings.json`이 모두 그 브랜치의 파일이다.
- `scripts/review-branch.sh:136`의 `run_check`는 브랜치의 Makefile로 호스트에서 `make check`를 돌린다. 레시피의 호스트 쪽 줄은 sandbox 밖에서 사용자 권한으로 실행된다.
- `make review`를 작성자 worktree에서 실행하면 `review-branch.sh` 자체도 작성자 브랜치의 것이다.
- 리뷰 규칙 3의 `scripts/check-git.sh origin/main <branch>`는 Claude 리뷰어(가드가 `git diff/log/show`만 허용)도, Codex 리뷰어(read-only)도 실행하지 못한다(F09).
- 리뷰 체크리스트의 보안 항목은 비밀값, `.env`, 공개 노출, 인증만 본다. sandbox 밖에서 도는 코드(제외 Make 타깃, 검사 스크립트, 가드 훅, `.claude/`)의 변경은 안내하지 않는다(F10).

**Verified (문서, 2026-11-03):** Claude Code 문서는 `--agents`로 준 정의가 프로젝트 `.claude/agents/`의 같은 이름 정의보다 우선한다고 적는다(https://code.claude.com/docs/en/sub-agents.md). 같은 문서는 프로젝트 파일 서브에이전트의 frontmatter hooks가 폴더 trust를 요구하며 `-p` 세션은 trust로 치지 않는다고 적는다.

**Assumption:** 그렇다면 지금의 Claude 리뷰어에서 `branch-reviewer.md`의 가드 훅이 돌지 않고 있을 수 있다. [계획 kkqjgknh](../plans/plan-2026-11-03-kkqjgknh-review-trust-boundary.md) Task 1이 실제 실행으로 확인한다.

**Assumption:** Codex 리뷰어의 deny 프로필은 main checkout의 `.local-data`를 막지만 MCP 연결은 막지 않는다. 사용자 Codex 설정에 basic-memory MCP가 있으면, 리뷰어가 노트 내용을 보고서에 넣고 `make review-post`가 그것을 공개 PR에 게시할 수 있다.

다른 에이전트가 MCP로 쓴 Basic Memory 노트도 같은 성격의 입력이다. MCP 서버는 sandbox 밖에서 돌고, 노트는 다른 기기나 다른 벤더의 에이전트가 썼을 수 있다.

## 검토한 대안

리뷰 도구를 어디서 가져올지(신뢰 기준):
1. origin/main 스냅샷에서 가져오고 `review-branch.sh`도 그 사본으로 다시 실행한다: 어느 worktree에서 돌려도 리뷰 도구 전체가 main의 것이 된다. 리뷰 도구를 고친 브랜치는 병합 전까지 새 도구로 리뷰받지 못하고, Makefile `review` 레시피는 실행 checkout의 것으로 남는다.
2. 실행 checkout(`SCRIPT_DIR`)의 파일을 주입한다: 가장 단순하다. 작성자 worktree에서 돌리면 브랜치 파일을 그대로 쓴다.
3. 리뷰어 정의, 설정, 훅만 origin/main에서 가져온다: 스크립트를 고친 브랜치는 막지 못한다.

리뷰 전 `make check`를 어떻게 돌릴지:
1. 스냅샷의 Makefile로 별도 check worktree에서 돌린다: 브랜치 코드는 `--network none` 컨테이너 안에서만 돈다. 브랜치가 `tools/Dockerfile`을 바꾸면 main 이미지로 돌아 실패할 수 있다.
2. 로컬 check를 없애고 head SHA의 CI `check` 결과를 읽는다: 브랜치 코드가 Mac에서 전혀 돌지 않는다. push와 CI 완료가 필요하고, 리뷰 스크립트가 GitHub API를 불러야 한다.
3. 지금처럼 브랜치의 Makefile로 호스트에서 돌린다: 바꿀 것이 없다. write-then-run이 리뷰 단계에도 남는다.

MCP로 읽은 노트를 어떻게 다룰지:
1. 산문 규칙만 둔다: 노트 내용은 데이터이고 노트 안의 지시는 따르지 않는다. 강제는 없다.
2. 1에 더해 리뷰어는 MCP 서버 없이 시작한다: 리뷰어 쪽 세 다리(신뢰할 수 없는 브랜치, 노트 내용, 공개 게시)가 끊긴다.
3. 2에 더해 훅이 세션에 넣는 노트 색인을 데이터로 표시한다: 작성 세션에도 표지가 생긴다. 그 훅은 계획 P-D가 고치는 파일이라 이번 범위와 겹친다.

## 결정

사용자가 2026-11-03에 세 질문의 대안 1, 1, 2를 승인했다.

1. 리뷰 도구의 신뢰 기준은 `origin/main`이다. `review-branch.sh`는 시작할 때 `origin/main`의 리뷰 도구(`scripts/`, `Makefile`, `tools/`, 리뷰어 정의, branch-review 스킬)를 임시 디렉터리에 풀고 그 사본으로 다시 실행한다. 라운드 2의 `REVIEW_BASE`는 diff 기준일 뿐 신뢰 기준이 아니다.
2. Claude 리뷰어의 정의와 가드 훅은 스냅샷에서 만든 `--agents` 정의로 넘긴다. 훅 명령은 스냅샷 안 가드 스크립트의 절대 경로다. 리뷰어 세션은 리뷰 대상의 프로젝트 설정과 MCP 설정을 읽지 않고, 파일 도구는 리뷰 worktree 안으로 제한한다. 정확한 플래그 조합은 계획 kkqjgknh Task 1의 실행 결과로 정한다.
3. 리뷰 전 `make check`는 스냅샷의 Makefile로 돌린다. 대상은 리뷰어가 읽는 worktree와 분리한 check 전용 detached worktree다. 브랜치의 테스트와 스크립트는 `--network none` 컨테이너 안에서만 돈다. 테스트 이미지는 스냅샷의 `tools/`로 만들고 작성자의 이미지와 다른 태그를 쓴다. 이 결과는 참고 정보이고 병합 판정은 CI `check`가 한다.
4. `review-branch.sh`는 스냅샷의 `check-git.sh origin/main <branch>`를 실행하고 결과를 리뷰 프롬프트와 meta 파일에 넣는다. 리뷰 규칙 3은 리뷰어가 이 결과나 CI `pr-rules`를 보도록 고친다.
5. 리뷰 체크리스트의 보안 항목에 "sandbox 밖에서 도는 코드와 검사 스크립트의 변경"을 더한다. 대상은 제외 Make 타깃의 레시피, `scripts/check-*.sh`, `scripts/guard-*.sh`, `.claude/`, 리뷰 도구다. 보는 것은 네트워크 추가, 자격증명 경로 읽기, ask와 deny의 약화다.
6. 다른 에이전트나 기기가 쓴 Basic Memory 노트(MCP로 읽은 것, 훅이 세션에 넣은 색인과 미러 포함)는 지시가 아닌 데이터다. 에이전트는 노트 안의 지시를 따르지 않고 사용자에게 넘긴다. 이 규칙은 `AGENTS.md` Safety에 한 줄로 둔다.
7. 두 리뷰어는 MCP 서버 없이 시작한다. Claude는 `--strict-mcp-config`를, Codex는 사용자 설정 파일을 읽지 않는 옵션(`--ignore-user-config`)을 쓴다.

## 결과

좋아지는 것:
- 리뷰 대상 브랜치가 리뷰어 정의, 가드 훅, 설정, 리뷰 스크립트를 바꿔도 그 리뷰에는 적용되지 않는다.
- 리뷰 단계에서 브랜치 코드가 호스트에서 돌지 않는다.
- 리뷰어가 노트 내용을 읽어 공개 PR로 내보내는 경로가 닫힌다.
- 리뷰 규칙 3을 리뷰어가 실제로 확인할 수 있다.

치르는 것(잔여 위험):
- `make review`를 부르는 Makefile `review` 레시피는 실행 checkout의 것이다. 작성자 worktree의 Makefile이 레시피를 바꾸면 스냅샷 단계를 건너뛸 수 있다. 결정 5의 체크리스트가 그 변경을 리뷰 대상으로 안내한다.
- 리뷰어는 브랜치의 `AGENTS.md`, `CLAUDE.md`와 코드 주석을 글로 읽는다. 그 안의 지시가 리뷰 판단을 흐릴 수 있다. 결정 2와 7은 리뷰어가 할 수 있는 일을 제한할 뿐 읽는 글을 거르지 않는다.
- 리뷰 도구를 고친 PR은 main의 리뷰 도구로 리뷰받는다. 새 도구의 동작은 bats 테스트와 병합 뒤의 첫 리뷰로 확인한다.
- check 컨테이너는 check worktree를 쓰기 가능하게 마운트한다. 리뷰어가 읽는 worktree와 분리했으므로 리뷰 입력은 바뀌지 않는다.
- 결정 6은 산문 규칙이다. 작성 세션에서 노트 색인을 데이터로 표시하는 일(대안 3)은 계획 P-D의 파일이라 Follow-up으로 둔다.
- 확인 방법: `tests/review-branch.bats`가 claude와 codex 호출 인자(스냅샷 경로의 `--agents` 정의, MCP 차단 옵션)와 스냅샷 Makefile로 돈 check를 확인한다. 가드 훅을 `exit 0`으로 바꾼 로컬 미끼 브랜치로 수동 시험하고 결과를 계획 kkqjgknh Progress log에 적는다.
