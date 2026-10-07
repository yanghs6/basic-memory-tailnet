# 에이전트 기반 Git·리뷰 정책 — 설계

- 상태: 승인 대기 (브레인스토밍에서 섹션별 승인 완료, 2026-10-07)
- 관련 스펙: [Basic Memory on OCI + Tailscale](spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md)
- 적용 시점: [local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md)을 시작할 때부터. 그 전에 `main`에 직접 커밋한 설계 문서들(정책 이전)은 예외다.

## 1. 목적과 범위

여러 코딩 에이전트(Claude Code와 서브에이전트, Codex CLI·앱, Antigravity, Gemini CLI)가 한 로컬 저장소에서 일한다.

**목적**
1. **동시 작업 충돌 방지:** 에이전트끼리 작업 공간과 브랜치가 섞이지 않게 한다.
2. **추적·리뷰 가능성:** 커밋마다 어느 도구·모델·계획·Task가 만들었는지 남기고, `main`에 들어가기 전에 독립된 리뷰와 사람의 승인을 거친다.

**범위 밖**
- git 훅으로 강제하기: 규칙은 문서와 `make check-git`으로 검사한다.
- GitHub 원격, PR, CI, 브랜치 보호

**완료 조건**
1. [local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md)부터 모든 에이전트 커밋이 `plan/*` 또는 `work/*` 브랜치에 있고, 트레일러 규칙을 따른다.
2. 각 계획 브랜치는 작성자와 다른 벤더의 리뷰어가 리뷰하고, 리뷰 기록이 `docs/reviews/`에 남은 뒤 사람이 `--no-ff`로 병합한다.
3. 새 [git-review-tooling 계획](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md)이 끝나면 `make check-git`과 `make review`가 동작하고, 테스트와 커버리지 기준을 통과한다.

## 2. 근거가 된 사실 (2026-10-07)

- **Verified (code.claude.com/docs/en/worktrees):** `claude --worktree <이름>`은 `.claude/worktrees/<이름>/`에 `worktree-<이름>` 브랜치를 만든다. 서브에이전트는 `isolation: worktree`로 격리할 수 있다. 원격이 없으면 기준점은 로컬 HEAD다.
- **Verified (learn.chatgpt.com/docs/environments/git-worktrees):** Codex 앱의 worktree는 `$CODEX_HOME/worktrees`에 detached HEAD로 생기고, 브랜치를 만들 때 기본 접두어는 `codex/`다.
- **Verified (antigravity.google/docs/subagents, 사용자 버그 리포트):** Antigravity 서브에이전트는 `branch` 모드에서 자체 worktree를 쓴다. `.git/config`에 `extensions.worktreeConfig`가 있으면 Antigravity가 멈추는 버그가 보고됐다.
- **Verified (git 동작):** 같은 브랜치는 두 worktree에서 동시에 체크아웃할 수 없다. worktree들은 refs와 objects를 공유한다.
- **Verified (docs.kernel.org/process/coding-assistants.html, Fedora AI 정책):** AI 기여 표기에는 `Assisted-by:` 트레일러를 쓰고, AI는 `Signed-off-by`를 넣지 않는다. `Reviewed-by:`는 기술 리뷰를 인증하는 의미다.
- **Verified (code.claude.com/docs/en/settings-reference):** Claude Code의 `attribution.commit` 설정으로 자동 `Co-authored-by` 트레일러를 바꾸거나 끌 수 있다.
- **Verified (code.claude.com/docs/en/best-practices):** 새 컨텍스트에서 리뷰해야 작성 세션의 편향을 피할 수 있다. 리뷰어는 정확성과 요구사항에 영향을 주는 문제만 지적해야 한다.
- **Verified (로컬 codex-cli 0.160.1 `--help`, openai/codex 소스):** `codex exec review`는 `--base`, `--commit`, `--uncommitted`, 사용자 프롬프트 중 하나만 받는다. `codex exec`의 기본 샌드박스는 읽기 전용이다. Codex 리뷰 루브릭은 P0~P3 등급을 쓰고, `AGENTS.md`의 리뷰 규칙을 읽는다.
- **Verified (code.claude.com/docs/en/sub-agents, code-review):** Claude Code 서브에이전트는 `tools`, `disallowedTools`, `permissionMode: plan`(읽기 전용), `model`을 지정할 수 있다. `/code-review`는 `main...<브랜치>` 같은 범위를 받는다. `/security-review`는 `origin` 원격이 필요해 이 저장소에서는 아직 쓸 수 없다.
- **Verified (로컬):** Claude Code 2.1.292, Codex CLI 0.160.1(ChatGPT 로그인), Gemini CLI 0.40.1이 설치돼 있다. Antigravity CLI는 없다.
- **Assumption:** 작성자와 다른 벤더 모델이 리뷰하면 더 좋다는 점을 측정한 1차 자료는 없다. 편향을 피하려는 추론에 근거한 선택이다.

## 3. 브랜치와 worktree

**브랜치**
- `main`은 사람이 실행한 `--no-ff` 병합 커밋만 받는다.
- 에이전트는 다음을 하지 않는다.
  - `main`에 직접 커밋
  - force-push, 히스토리 재작성(rebase는 자기 브랜치에서 사람이 요청할 때만)
  - `git gc`
  - 다른 에이전트의 브랜치·worktree 삭제
- 이름은 작업 단위로 짓는다.
  - 계획: `plan/<NN>-<slug>` (예: `plan/sqzn0teq-local-foundation`)
  - 그 밖의 작업: `work/<slug>`
- 도구가 자동으로 만든 브랜치(`worktree-*`, `codex/*`, detached HEAD)는 리뷰 요청 전에 `git branch -m`으로 규칙에 맞게 바꾼다.

**worktree**
- 에이전트 하나당 worktree 하나. 한 worktree에 에이전트 둘을 두지 않는다. `main` 체크아웃(저장소 루트)에서는 작업하지 않는다.
- 위치는 도구 기본값을 따른다.
  - Claude Code: `.claude/worktrees/<이름>/` (gitignore 대상)
  - Codex 앱: `$CODEX_HOME/worktrees`
  - 그 밖의 경우: 형제 디렉터리 `../027_agent_share_poc-wt/<slug>`
- 한 계획 브랜치는 한 번에 한 worktree에서만 진행한다. 서브에이전트 방식에서는 컨트롤러가 브랜치의 worktree를 소유하고, Task를 순서대로 맡긴다.
- `extensions.worktreeConfig`는 켜지 않는다.
- `make local-up`은 고정 컨테이너 이름(`basic-memory-server`)과 포트(8737)를 쓰므로, 한 번에 한 worktree에서만 실행한다. `make check`는 이름 없는 일회용 컨테이너만 써서 동시에 실행해도 된다.

## 4. 커밋 트레일러

에이전트가 만드는 모든 커밋은 메시지 마지막 문단에 다음 트레일러를 둔다.

```
feat: add verify-mcp read-only mode

Assisted-by: claude-code claude-opus-5-5
Plan: sqzn0teq
Task: 3
```

| 트레일러 | 값 | 비고 |
|---|---|---|
| `Assisted-by` | `<도구> <모델 ID>` | 도구: `claude-code`, `codex`, `antigravity`, `gemini-cli` |
| `Plan` | `01`~`05` 또는 `none` | 계획 밖 작업은 `none` |
| `Task` | Task 번호, `review` 또는 `none` | 리뷰 기록 커밋은 `review` |
| `Review-Finding` | `R<회차>-F<번호>` | 리뷰 지적을 고친 커밋에만 |

- 에이전트는 `Co-authored-by`와 `Signed-off-by`를 넣지 않는다.
- 조회: `git log --format='%h %s | %(trailers:key=Assisted-by,key=Plan,key=Task,valueonly,separator=%x2C )' main..<브랜치>`
- **사용자 전역 규칙과의 관계:** 사용자 전역 규칙은 attribution(Co-authored-by)을 끈다. 이 저장소의 `Assisted-by`도 `Co-authored-by`를 쓰지 않으므로 둘은 충돌하지 않는다. Claude Code는 저장소 설정 `attribution.commit = ""`로 자동 트레일러를 끈다.
- 도구가 세션 단위로 다른 attribution 안내를 주더라도, 이 저장소에서는 이 절의 규칙이 우선한다.

## 5. 리뷰어 에이전트

**누가 리뷰하나:** 작성자와 다른 벤더가 새 세션에서 리뷰한다. 작성 세션은 자기 작업을 리뷰하지 않는다.

| 작성 도구 | 리뷰 도구 |
|---|---|
| Claude Code | Codex CLI |
| Codex, Antigravity, Gemini CLI | Claude Code `branch-reviewer` 에이전트 |

**읽기 전용 실행**
- 리뷰는 detached worktree(`../027_agent_share_poc-wt/review-<slug>`)에서 한다. 리뷰어는 파일을 고치거나 커밋하지 않는다. 결과 원문은 스크립트가 `.review-out/`(git ignore)에 저장한다.
- **변경 리뷰(버그):**
  - Codex: `codex exec review --base main`
  - Claude: `/code-review main...HEAD`
- **계획 대조 리뷰(스펙·범위·증거):** Codex는 `--base`와 사용자 프롬프트를 함께 쓸 수 없으므로 따로 실행한다.
  - Codex: `codex exec -o <파일> "<체크리스트 프롬프트>"`
  - Claude: `claude -p --agent branch-reviewer`
- `.claude/agents/branch-reviewer.md`: `tools: Read, Grep, Glob, Bash`, `disallowedTools: Write, Edit, NotebookEdit`, `permissionMode: plan`. Bash는 `git diff`·`git log`·`git show`만 허용한다.
- [git-review-tooling 계획](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md) 이후에는 `make review BRANCH=<브랜치> REVIEWER=codex|claude`로 실행한다. [local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md)은 위 명령을 손으로 실행한다.

**체크리스트** (`AGENTS.md`의 `## Code Review Rules`. Codex는 이 섹션을 자동으로 읽고, Claude는 `@AGENTS.md`로 읽는다)
1. 계획의 Task가 모두 구현됐고, 각 검증 단계가 증거(명령과 결과)와 함께 통과했는가
2. 계획 밖 변경(범위 확장)이 없는가
3. `make check`가 통과하는가
4. 보안: 비밀값, `.env`, 공개 노출, 인증 없는 엔드포인트
5. `AGENTS.md`가 요구하는 문서가 갱신됐는가
6. 모든 커밋에 트레일러가 있는가([git-review-tooling 계획](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md) 이후 `make check-git`)

이 변경이 새로 만든 문제만 지적하고, 추측성 지적과 취향 문제는 줄인다.

**심각도와 병합 기준**

| 등급 | 의미 | 병합 |
|---|---|---|
| P0 | 데이터 손실, 보안, 운영 차단 | 차단 |
| P1 | 버그, 요구사항 불충족 | 차단 |
| P2 | 유지보수 문제 | 고치거나, 사람이 이유를 적고 미룸 |
| P3 | 사소함 | 선택 |

지적마다 `file:line`, 실패 시나리오, 수정 제안을 단다.

**리뷰 기록:** `docs/reviews/plan-NN-<slug>.md` (작성 에이전트가 브랜치에 커밋, `Task: review`)
- 리뷰 도구와 모델, base SHA, 리뷰한 head SHA, 회차별 판정
- 지적 표: ID(`R1-F3`), 등급, 위치, 요약, 상태
- 상태는 `open`, `fixed <sha>`, `rejected <근거>`, `deferred <사람이 적은 이유>` 중 하나다.

**수정과 재리뷰**
1. 작성 에이전트는 지적마다 먼저 검증한다(재현하거나 근거를 인용). 근거 없이 받아들이거나 거절하지 않는다.
2. 지적 하나당 커밋 하나이고, `Review-Finding` 트레일러를 단다.
3. 2차 리뷰는 `<리뷰한 head>..HEAD`만 보고, 1차 지적이 닫혔는지와 새 P0·P1만 확인한다.
4. 2회차 뒤에도 남는 이견이나, 반박 한 번으로 합의하지 못한 지적은 사람이 결정한다.

## 6. 사람의 승인과 병합

1. 리뷰 기록을 읽고, 열린 P0·P1이 없는지, 미룬 P2에 사람의 이유가 적혀 있는지 확인한다.
2. 현재 HEAD가 "리뷰한 head + 기록된 수정 커밋"인지 확인한다: `git log --oneline <리뷰한 head>..<브랜치>`
3. 사람이 직접 병합한다. 에이전트는 메시지 초안만 쓴다.

```
git merge --no-ff plan/sqzn0teq-local-foundation

Merge plan/sqzn0teq-local-foundation

Reviewed-by: yanghs6
Review-Agent: codex <모델 ID>
Review-Record: docs/reviews/rev-2026-10-07-bwvfm8bx-local-foundation.md
Reviewed-Head: <sha>
```

4. 병합 후 worktree를 정리한다(`git worktree remove`, `git branch -d`).

계획 파일 이동 규칙:
- 끝난 계획을 `docs/plans/completed/`로 옮기는 커밋은, 리뷰 기록과 함께 그 계획 브랜치에서 병합 전에 한다.
- 다음 계획을 `backlog/`에서 `active/`로 옮기는 커밋은 다음 계획 브랜치의 첫 커밋으로 한다.

`Reviewed-by`는 사람이 리뷰를 확인했다는 뜻으로만 쓴다. 에이전트 리뷰는 `Review-Agent`에 적는다.

## 7. 구현 배치

| 시점 | 내용 |
|---|---|
| 지금 (writing-plans) | 계획 01~05의 Global Constraints에 3·4절 규칙을 넣고, 계획 끝 "마무리"를 5·6절 절차로 바꾼다. [local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md)은 `plan/sqzn0teq-local-foundation` 브랜치에서 시작하고, 리뷰는 수동 명령으로 한다. |
| [local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md) Task 4 | `AGENTS.md` 기본판에 짧은 `## Git` 섹션을 넣는다(브랜치, worktree, 트레일러, 금지 사항). |
| **새 [git-review-tooling 계획](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md): Git & Review Tooling** | 아래 산출물. 기존 계획 02·03·04는 03·04·05로 번호를 바꾼다. |

**새 [git-review-tooling 계획](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md) 산출물**
- `scripts/check-git.sh` + `make check-git`
  - `main..HEAD` 커밋마다 `Assisted-by`·`Plan`·`Task`가 있는지
  - `Co-authored-by`·`Signed-off-by`가 없는지
  - 브랜치 이름이 `^(plan/[0-9]{2}-[a-z0-9-]+|work/[a-z0-9-]+)$`를 따르는지
  - `extensions.worktreeConfig`가 꺼져 있는지
  - 위반마다 고치는 방법을 출력한다.
- `scripts/review.sh` + `make review BRANCH=… REVIEWER=codex|claude`
  - 리뷰용 detached worktree를 만들고, 변경 리뷰와 계획 대조 리뷰를 실행해 원문을 `.review-out/<브랜치>-r<회차>-<도구>.md`에 저장한 뒤 worktree를 지운다.
  - 테스트는 `codex`·`claude`·`git worktree` 호출을 stub으로 검증한다.
- `.claude/agents/branch-reviewer.md`
- 스킬(`.agents/skills/` 정본 + `.claude/skills/` 링크, 표준 frontmatter만)
  - `git-workflow` (작성자용): 브랜치·worktree 시작, 트레일러 커밋, 리뷰 요청, 지적 검증·수정, 병합 메시지 초안
  - `branch-review` (리뷰어용): 체크리스트, 심각도, 기록 형식, 읽기 전용 규칙
- `AGENTS.md`: `## Code Review Rules`와 스킬 목록 추가
- `docs/reviews/README.md`: 리뷰 기록 템플릿
- `.claude/settings.json`: `"attribution": {"commit": ""}`
- `.gitignore`: `.review-out/`

**함께 조정할 문서**
- Basic Memory 스펙 머리말의 계획 목록을 다섯 개로 갱신한다.
- 계획 문서 안의 커밋 예시에 트레일러를 넣는다.

## 8. 위험과 대응

| 위험 | 대응 |
|---|---|
| 에이전트가 정책을 모르고 `main`에서 작업 | `AGENTS.md`의 `## Git`([local-foundation 계획](../plans/plan-2026-10-07-sqzn0teq-local-foundation.md)부터), 리뷰 체크리스트, `make check-git` |
| 리뷰어가 파일을 수정 | detached worktree, Codex 읽기 전용 샌드박스, Claude `permissionMode: plan`과 쓰기 도구 차단 |
| 리뷰 루프가 끝나지 않음 | 2회차 제한, 2차는 새 P0·P1만, 남은 이견은 사람이 결정 |
| 리뷰어가 사소한 지적을 쏟아냄 | 변경이 만든 문제만, 등급별 병합 기준, P3는 선택 |
| 같은 브랜치를 두 에이전트가 동시에 씀 | 브랜치 하나에 worktree 하나(git이 막음), 컨트롤러가 Task를 순서대로 진행 |
| Antigravity worktree 버그 | `extensions.worktreeConfig` 금지, `check-git`이 검사 |
| 리뷰 도구의 사용량·비용 | 계획 단위로만 리뷰(Task 단위 아님), 2회차 제한 |
