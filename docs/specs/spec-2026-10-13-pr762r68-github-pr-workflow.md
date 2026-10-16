---
status: approved
date: 2026-10-13
amended-by: docs/specs/spec-2026-10-15-sgpbx1gq-doc-system.md
---

# GitHub PR 기반 에이전트 Git 워크플로 — 설계

- 구현: [github-switch](../plans/plan-2026-10-13-k93wjt1a-github-switch.md), [review-posting](../plans/plan-2026-10-13-znbc3ase-review-posting.md) 계획
- 대체 범위: [에이전트 기반 Git·리뷰 정책](spec-2026-10-07-restd5vd-git-review-policy.md)의 3절 중 브랜치 기준점, 4절의 병합 트레일러, 5절의 리뷰 기록 위치, 6절 전체. 나머지(브랜치 이름, worktree, 커밋 트레일러, 리뷰어 배정, 심각도)는 그 문서가 계속 정본이다.
- 근거 조사: [에이전트 개발 오픈소스의 git 전략](../research/rsch-2026-10-13-djx2fzm5-agent-oss-git-strategies.md)
- 적용 시점: [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)을 병합한 때부터. 그 전에 병합하는 브랜치는 기존 정책을 따른다.

## 1. 목적과 범위

이 저장소를 공개 GitHub 저장소 `github.com/yanghs6/basic-memory-tailnet`으로 옮기고, 조사한 공개 프로젝트(스타 3만 이상, 에이전트 개발)의 관행에 맞춘다. 관행의 뼈대는 PR, 필수 CI, 사람의 승인, squash 병합이다. 기존 정책의 두 목적, 즉 동시 작업 충돌 방지와 추적·리뷰 가능성은 그대로 둔다.

**사용자 결정 (2026-10-13)**
1. GitHub 원격, PR, CI를 도입한다.
2. 에이전트는 전용 머신 계정으로 push하고 PR을 연다. 사람은 승인하고 병합한다.
3. 병합 방식은 squash 하나다.
4. PR 하나는 계획 하나(`plan/NN-slug`) 또는 work 하나(`work/slug`)다. 계획은 3~5 Task로 작게 자른다.
5. 다른 벤더 리뷰는 로컬 `make review`를 유지하고, 결과를 PR 코멘트로 게시한다.

**범위 밖**
- 외부 기여 정책(CONTRIBUTING, AI 기여 정책, 이슈 먼저 규칙): 외부 PR이 실제로 오기 시작하면 따로 정한다.
- GitHub 호스티드 AI 리뷰(Codex 클라우드 리뷰, Claude Code GitHub Action), merge queue, CODEOWNERS, 로컬 git 훅
- Dependabot: 이미지 digest 고정 불변식과 `bm-upgrade` 스킬의 업그레이드 절차와 충돌한다.

**완료 조건**
1. `main`이 GitHub에 있고 ruleset이 활성 상태다. 직접 push, force push, 삭제가 막히고, PR·승인 1개·필수 체크·squash만 허용된다.
2. 에이전트 PR은 머신 계정이 열고, 승인은 사람만 할 수 있다.
3. PR마다 CI가 `make check`, `make check-git`, `scripts/check-pr.sh`를 실행한다.
4. 리뷰 원문과 지적 기록이 PR 코멘트로 남는다([review-posting 계획](../plans/plan-2026-10-13-znbc3ase-review-posting.md)).
5. `AGENTS.md`, 스킬, 런북이 새 흐름과 일치하고 `make check`가 통과한다.

## 2. 근거가 된 사실 (2026-10-13)

- **Verified (GitHub API `repos/yanghs6/basic-memory-tailnet`):** 공개 저장소이고 2026-10-13에 만들어졌다. 기본 브랜치는 `main`, 라이선스는 Apache-2.0이다. contents API는 `LICENSE` 파일 하나만 보여 준다. 로컬 `main`에는 이 커밋이 없다.
- **Verified ([Approving a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews)):** "Pull request authors cannot approve their own pull requests."
- **Verified ([GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)):** 공개 저장소에서 GitHub 호스티드 표준 러너를 쓰는 Actions는 무료다.
- **Verified ([GitHub 약관 B(3)](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service)):** 개인 계정 외에 무료 머신 계정을 하나 둘 수 있다. 사람이 직접 만들고 약관에 동의해야 하며, 자동화 작업에만 쓴다. 그 계정의 행동은 소유자가 책임진다.
- **Reported (문서 검색 요약, [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)):** ruleset은 GitHub Free에서도 공개 저장소라면 쓸 수 있다.
- **Verified ([Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)):** "Only personal access tokens (classic) have write access for public repositories that are not owned by you." fine-grained 토큰은 협업자로 참여한 저장소에 기여할 수 없는 제약이 있다.
- **Verified ([Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request)):** "By default, a workflow only runs when a `pull_request` event's activity type is `opened`, `synchronize`, or `reopened`." `edited`는 따로 지정해야 한다.
- **Assumption:** `edited`는 PR 제목, 본문, base 브랜치가 바뀔 때 발생한다. 위 문서와 webhook 문서는 그 의미를 적지 않았으므로, [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)의 첫 PR에서 본문을 고쳐 `pr-rules`가 다시 도는지 확인한다.
- **Verified ([About push protection](https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection)):** 계정 단위 push protection은 기본으로 켜져 있고, 공개 저장소로 비밀값을 push하는 것을 막는다. 저장소 단위 push protection은 기본으로 꺼져 있고 GitHub Secret Protection이 필요하다.
- **Verified (Command: `git log main -p`를 grep으로 검사, 2026-10-13, `main` a5781a4까지. 그 뒤 병합된 `a5781a4..1b333af`([test-pruning 계획](../plans/plan-2026-10-13-g57mry4b-test-pruning.md))도 같은 결과):**
  - `main` 이력 123커밋(a5781a4 기준)의 작성자는 모두 `yanghs6 <yanghs632@gmail.com>`이다.
  - `tskey-`로 시작하는 값은 모두 테스트 자리표시자다.
  - 실제 VM IP, GCP 프로젝트 ID, tailnet 이름은 없다.
- **Verified (Command: `git log -p --branches --not main`을 grep으로 검사, 2026-10-13):**
  - 아직 main에 들어가지 않은 로컬 브랜치 전체에서 VM 외부 IP와 GCP 프로젝트 ID는 어떤 커밋에도 없다.
  - VM의 Tailscale IP(`100.64.0.0/10` 대역)는 `plan/qtvzskgx-vm-rollout`의 커밋 하나(`fe73353`, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log의 ssh 출력)에만 있다.
  - `main`에는 이 대역의 주소가 없다.
- **Verified (근거 조사 보고서):** 공개 프로젝트의 공통 관행은 다음과 같다.
  - 트렁크 기반 브랜치, squash 병합, 승인 1개 이상
  - 에이전트 PR을 초안으로 열기
  - 봇이 사람 없이 병합하지 않기
  - AGENTS.md를 정본으로 두고 CLAUDE.md는 한 줄로 가져오기
- **Assumption:** 머신 계정이 Write 협업자라면 사람이 승인한 뒤 병합 버튼을 누를 수 있다. ruleset은 승인 여부만 강제하고, 누가 병합하는지는 강제하지 않는다.

## 3. 역할과 계정

| 계정 | 하는 일 | 권한 |
|---|---|---|
| `yanghs6` (사람) | PR 승인, Squash and merge, 저장소 설정과 ruleset 관리 | 소유자 |
| 머신 계정 `yanghs6-bot` | 모든 에이전트가 함께 쓴다. 브랜치 push, 초안 PR 생성, 리뷰 결과 코멘트 | 이 저장소의 Write 협업자 |

- 어느 도구와 모델이 작업했는지는 계정이 아니라 커밋과 PR의 `Assisted-by` 트레일러로 구분한다.
- 머신 계정의 토큰은 classic PAT이고, 범위는 `public_repo`와 `workflow`, 만료는 90일이다. `workflow`는 `.github/workflows/`를 바꾸는 push에 필요하다. classic PAT 자체는 저장소 단위로 제한되지 않는다. 실제 범위는 머신 계정이 가진 권한으로 정해진다. 그래서 머신 계정에는 이 저장소 말고 다른 저장소 권한을 추가하지 않고, 머신 계정으로 저장소를 만들지도 않는다.
- 토큰은 사용자가 자기 터미널에서 대화형 `gh auth login`의 토큰 붙여넣기 프롬프트로 등록하고(키체인 보관), git push 인증은 사용자가 이 저장소에만 credential helper `!gh auth git-credential`을 설정해 연결한다(`docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md` 1절). 토큰을 채팅, 파일, 명령 인자, 파이프에 넣지 않는다. Tailscale 인증 키와 같은 규칙이다.
- 커밋 작성자(`git config user.*`)도 머신 계정이다(사용자 결정 2026-10-14). 사람이 작성한 커밋을 squash 병합하면 GitHub이 `Co-authored-by`를 덧붙이기 때문이다(14절 3번). main 체크아웃의 저장소 설정에 넣어 모든 worktree가 함께 쓴다(`docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md` 1절).
- 사용자가 관리자 권한으로 `gh`를 써야 하면(ruleset 적용 등) 머신 계정과 섞이지 않도록 별도 설정 디렉터리를 쓴다(`GH_CONFIG_DIR`).

## 4. 브랜치와 worktree

- **유지:**
  - 브랜치 이름은 `plan/<NN>-<slug>`와 `work/<slug>`다.
  - 에이전트 하나가 worktree 하나를 쓰고, main 체크아웃에서는 작업하지 않는다.
  - `extensions.worktreeConfig`를 켜지 않는다.
- **변경:** 브랜치 기준점을 로컬 `main`에서 `origin/main`으로 바꾼다. 시작 전에 `git fetch origin`을 한다.
- **원격 브랜치:** 머신 계정이 push한다. 병합 뒤에는 GitHub이 자동으로 지운다.
- **main 체크아웃:** 사람이 `git pull --ff-only`로 갱신한다. squash 병합이라 `main`은 선형 이력을 유지한다.

## 5. 커밋과 PR

**브랜치 커밋:** 기존 규칙을 그대로 쓴다.
- 커밋 전에 `make check`를 통과한다.
- `Assisted-by`, `Plan`, `Task` 트레일러를 단다. 리뷰 지적을 고친 커밋에는 `Review-Finding`을 더한다.
- `Co-authored-by`와 `Signed-off-by`는 넣지 않는다.

**PR**
- 첫 커밋 뒤에 `git push -u origin <branch>`, 이어서 `gh pr create --draft`로 연다. 그 뒤로는 커밋할 때마다 push한다.
- 제목은 squash 커밋의 제목이 되므로 `<type>: <description>` 형식을 쓴다. type은 `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci` 중 하나다.
- 본문은 `.github/pull_request_template.md`를 따른다. 항목은 요약, 계획 링크, 검증 증거(명령과 결과)이고, 마지막 문단에 다음 트레일러를 둔다.

```
Assisted-by: claude-code claude-opus-5-5
Plan: k93wjt1a
```

- 작업에 참여한 도구가 여럿이면 `Assisted-by`를 도구마다 한 줄씩 쓴다.
- 저장소 설정에서 squash 커밋 메시지를 "PR 제목 + PR 본문"으로 정한다. 그러면 `main` 커밋마다 `Assisted-by`와 `Plan`이 남는다. 조회 명령: `git log --format='%h %s | %(trailers:key=Assisted-by,key=Plan,valueonly,separator=%x2C )' main`
- `Task`와 `Review-Finding`은 PR 안의 커밋에만 남는다. **Assumption:** GitHub은 브랜치를 지운 뒤에도 PR의 커밋(`refs/pull/<N>/head`)을 보존한다.

## 6. CI

워크플로는 둘로 나눈다. 둘 다 `main`을 대상으로 하는 `pull_request`에서 실행한다.

| 워크플로 | 이벤트 타입 | 잡 | 내용 |
|---|---|---|---|
| `.github/workflows/ci.yml` | 기본값(`opened`, `synchronize`, `reopened`) | `check` | `make check`: 린트, bats, 커버리지 80% 이상. 지금의 Docker 테스트 이미지를 쓴다. |
| `.github/workflows/pr-rules.yml` | `types: [opened, synchronize, reopened, edited]` | `pr-rules` | `make check-git`(base `origin/main`, PR head를 로컬 브랜치로 받음)과 `scripts/check-pr.sh` |

- `pr-rules`에 `edited`를 넣는 이유는 PR 제목과 본문이 squash 커밋 메시지가 되기 때문이다. 기본 이벤트 타입만 쓰면 본문을 고쳐도 검사가 다시 돌지 않는다. 그러면 고친 뒤에도 실패가 남거나, 통과한 뒤에 트레일러를 지워도 성공 결과가 남는다.
- 둘로 나누는 이유는 본문만 고쳤을 때 무거운 `make check`를 다시 돌리지 않기 위해서다. 한 워크플로 안에서 `if:`로 잡을 건너뛰는 방식은 쓰지 않는다. 같은 head의 이전 실패를 가릴 수 있다.

- `scripts/check-pr.sh`(새 파일)는 다음을 검사한다.
  - PR 제목이 5절의 형식을 따르는가.
  - 본문 마지막 문단에 `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`이 한 줄 이상 있는가.
  - `Plan: <NN|none>`이 있는가.
  - `Co-authored-by`와 `Signed-off-by`가 없는가. GitHub이 자동으로 붙이는 줄은 예외로 할 수 있다(Open question 3).
  - Claude Code 세션 링크(`claude.ai/code/session`)가 없는가. squash 병합으로 `main`에 공개되기 때문이다.
  - 입력은 환경변수(`PR_TITLE`, `PR_BODY`)로 받는다. 워크플로는 `${{ }}`를 `run:`에 직접 넣지 않고 `env:`로 넘긴다. 스크립트 주입을 막기 위해서다.
- 권한은 `permissions: contents: read`만 준다. 비밀값은 쓰지 않는다. `pull_request_target`은 쓰지 않는다. 그래서 fork에서 온 PR도 쓰기 권한이나 비밀값에 닿지 못한다.
- 외부 Action은 전체 커밋 SHA로 고정한다. 이미지를 digest로 고정하는 불변식과 같은 원칙이다.
- `scripts/check-git.sh`의 규칙과 기본값은 그대로 둔다. `make check-git`이 base로 `origin/main`을 넘기고, CI는 `scripts/check-git.sh origin/main <PR 브랜치>`를 직접 실행한다. 스크립트 기본값을 그대로 두므로, 원격이 없는 테스트 저장소에서 도는 테스트는 영향을 받지 않는다.

## 7. 저장소 설정과 ruleset

ruleset 내용은 `.github/rulesets/main.json`으로 저장소에 남긴다. PR에서 리뷰받게 하려는 것이다. 적용은 사용자가 한다. 웹 UI를 쓰거나, 3절의 별도 설정 디렉터리로 `gh api --method POST repos/yanghs6/basic-memory-tailnet/rulesets --input .github/rulesets/main.json`을 실행한다. 절차는 `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md`(새 파일)에 둔다.

**ruleset `main`** (대상: 기본 브랜치, 상태: active, 우회 목록: 비움)
- `deletion`, `non_fast_forward`, `required_linear_history`
- `pull_request`:
  - 승인 1개가 있어야 한다.
  - 새 push가 오면 이전 승인은 무효가 된다.
  - 마지막 push를 기준으로 다시 승인을 받아야 한다.
  - 리뷰 스레드가 모두 해결돼야 한다.
  - 허용하는 병합 방식은 `squash` 하나다.
- `required_status_checks`: `check`, `pr-rules`. PR 브랜치가 최신 `main`을 포함해야 한다(strict).

**저장소 설정**
- 병합 버튼: squash만 켠다. squash 커밋 제목은 PR 제목, 메시지는 PR 본문이다. 병합된 브랜치를 자동으로 삭제하고, auto-merge는 끈다.
- Actions: 기본 `GITHUB_TOKEN`은 읽기 전용이다. 외부 협업자의 fork PR 워크플로는 실행 전에 승인을 받는다.
- 보안: 저장소 단위 secret scanning과 push protection을 켠다. 켤 수 없으면 계정 단위 push protection에 맡긴다(Open question 4).

**긴급 변경:** 우회 목록이 비어 있어서 사용자도 `main`에 직접 push할 수 없다. 꼭 필요하면 ruleset을 잠시 끄고, 다시 켠 뒤 `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`의 Incident log에 기록한다.

## 8. 리뷰

- **유지:**
  - 리뷰어 배정: Claude Code가 작성하면 Codex CLI가, Codex·Antigravity·Gemini CLI가 작성하면 Claude `branch-reviewer`가 리뷰한다.
  - 읽기 전용 detached worktree에서 리뷰한다.
  - 리뷰는 계획 단위로 하고 최대 2회차까지 한다.
  - 기준은 `AGENTS.md`의 `## Code Review Rules`와 P0~P3다.
  - 지적은 먼저 검증하고, 커밋 하나에 지적 하나씩 고친다.
- **변경:** `make review`의 `REVIEW_BASE` 기본값을 `origin/main`으로 바꾼다. `scripts/review.sh`의 기본값은 그대로 둔다. 원격 추적 브랜치를 base로 받으면 기존 임시 base 브랜치 로직이 처리한다.
- **게시 ([review-posting 계획](../plans/plan-2026-10-13-znbc3ase-review-posting.md)):** `scripts/post-review.sh`와 `make review-post PR=<번호>`를 만든다.
  - `.review-out/`의 diff 리포트와 plan 리포트를 회차·리뷰어마다 PR 코멘트 두 개(change review, plan review)로 올린다. 코멘트 머리에는 리뷰 도구와 모델, base와 head SHA, 회차를 적는다.
- **지적 기록:** "Review record" 코멘트 하나에 지적 표를 두고, 머신 계정이 상태가 바뀔 때마다 갱신한다.
  - 표의 열: ID(`R1-F3`), 등급, 위치, 요약, 상태
  - 상태: `open`, `fixed <sha>`, `rejected <근거>`, `deferred <사람이 적은 이유>` 중 하나
- **P0/P1 차단:** AI 리뷰는 일반 코멘트로 올라가서 "리뷰 스레드 해결" 규칙의 대상이 아니다. 그래서 사람이 승인하기 전에 Review record를 확인하는 방식으로 막는다. 줄 단위 리뷰 스레드(사람의 지적)는 ruleset이 막는다.
- **임시 절차 ([github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md) 병합부터 09 병합까지):** 작성 에이전트가 `.review-out/` 리포트를 `gh pr comment --body-file`로 직접 게시한다.
- **`docs/reviews/`:** 기존 기록은 이력으로 보존하고 새 기록은 쓰지 않는다. README에 그렇게 적는다([review-posting 계획](../plans/plan-2026-10-13-znbc3ase-review-posting.md)).

## 9. 승인, 병합, 정리

1. **작성 에이전트:** 다음 조건이 모두 맞으면 `gh pr ready`로 PR을 넘긴다.
   - CI가 통과했다.
   - Review record에 열린 P0/P1이 없다.
   - 미룬 P2에는 사람이 적은 이유가 있다.
2. **브랜치 갱신:** 다른 PR이 먼저 병합돼 PR 브랜치가 최신 `main`을 포함하지 않으면, strict 필수 체크 때문에 병합이 막힌다. 이때 작성 에이전트가 다음 순서로 갱신한다. 이력 재작성 금지를 지키기 위해 rebase나 force push는 쓰지 않는다.
   1. `git fetch origin` 후 `git merge origin/main`으로 PR 브랜치에 main을 합친다. 충돌이 나면 해결한다.
   2. `make check`를 통과시키고 push한다. 새 push로 기존 승인은 무효가 되고 CI가 다시 돈다.
   3. 충돌 해결로 코드가 바뀌었으면 PR 코멘트에 그 내용을 적는다. 다른 벤더 리뷰를 이미 마쳤다면, 새 `origin/main`을 기준으로 PR 전체의 리뷰를 다시 받는다(`REVIEW_BASE=origin/main`). `<직전 head>..HEAD` 범위로 받으면 `main`에서 들어온 커밋이 섞이기 때문이다. 충돌 없이 합쳐졌으면 CI와 사람의 재승인으로 충분하다.
   4. 사람이 다시 승인한다. 사람은 GitHub의 "Update branch"를 누르지 않는다. 누르면 마지막 push가 사람의 것이 되고, ruleset의 마지막 push 승인 규칙 때문에 그 사람은 PR을 승인할 수 없다.

   병합 커밋에는 트레일러가 없지만, `check-git.sh`는 `--no-merges`로 병합 커밋을 검사에서 뺀다.
3. **사람:** GitHub에서 Approve한 뒤 Squash and merge를 누른다. 에이전트는 병합하지 않는다. ruleset은 승인만 강제하므로, 이 규칙은 `AGENTS.md`로 지킨다.
4. **폐지하는 것:** 병합 트레일러 `Reviewed-by`, `Review-Agent`, `Review-Record`, `Reviewed-Head`와 `.review-out/merge-*.txt`를 쓰지 않는다. 같은 정보는 GitHub 승인 기록, Review record 코멘트, PR head SHA가 담는다.
5. **정리:** `gh pr view <번호> --json state`가 `MERGED`이면 다음을 한다.
   1. worktree의 `backups/`를 확인한다.
   2. `git worktree remove`로 worktree를 지운다.
   3. `git branch -D <branch>`로 로컬 브랜치를 지운다. squash로 병합한 브랜치는 `-d`가 거부한다.
6. **계획 파일 이동:** 기존 규칙과 같다. `completed/`로 옮기는 커밋은 병합 전에 PR 안에서 하고, `active/`로 옮기는 커밋은 다음 계획의 첫 커밋으로 한다.

## 10. 이행 순서

| 단계 | 누가 | 내용 |
|---|---|---|
| 0 | 에이전트, 사람 | 이 스펙과 근거 조사를 담은 `work/workflow-alignment`를 기존 정책(로컬 교차 리뷰, 사람의 `--no-ff`)으로 병합한다 |
| 1 | 사람 | 머신 계정을 만들고 이 저장소에 Write 협업자로 초대한다. classic PAT를 발급해 3절대로 등록한다 |
| 2 | 사람 | 공개 전 점검(11절) 뒤 main 체크아웃에서 `git remote add origin https://github.com/yanghs6/basic-memory-tailnet.git`, `git fetch origin`, `git merge --allow-unrelated-histories origin/main`, `git push -u origin main`을 실행한다. force push를 쓰지 않으므로 원격의 `LICENSE` 커밋이 보존된다 |
| 3 | 에이전트 | [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)을 GitHub의 첫 PR로 진행한다. 이때 ruleset은 아직 적용하지 않는다 |
| 4 | 사람 | [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)을 병합하기 전에 7절의 저장소 설정을, 병합한 뒤에 ruleset을 적용한다. 저장소 설정 전의 squash 메시지 기본값은 커밋 메시지 목록이라, 먼저 병합하면 브랜치 커밋 메시지가 `main`에 남는다. 필수 체크는 워크플로가 `main`에 들어간 뒤에 걸어야 한다. 그 전에 걸면 어떤 PR도 병합할 수 없다 |
| 5 | 에이전트 | [review-posting 계획](../plans/plan-2026-10-13-znbc3ase-review-posting.md)을 새 흐름으로 진행한다 |

[github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)은 `plan/g57mry4b-test-pruning`이 병합된 뒤에 시작한다. [test-pruning 계획](../plans/plan-2026-10-13-g57mry4b-test-pruning.md)이 `tests/`를 정리하고 있어서 테스트 파일이 충돌할 수 있었기 때문이다. test-pruning 계획은 2026-10-13에 `1b333af`로 병합됐으므로, 이 조건은 이미 충족됐다.

## 11. 진행 중인 브랜치와 공개 전 점검

- **진행 중인 브랜치(`plan/qtvzskgx-vm-rollout`, `plan/g57mry4b-test-pruning` 등):**
  - 10절 2단계 전에 끝나면 기존 정책으로 병합한다. 그 내용은 `main` 이력과 함께 공개된다.
  - 그 뒤에 끝나면 `origin/main` 위로 push하고 PR을 연다.
  - **예외: `plan/qtvzskgx-vm-rollout`** (사용자 결정 2026-10-13: VM IP를 감춘다)
    - 커밋 `fe73353`에 VM의 Tailscale IP가 있으므로 이 브랜치는 `--no-ff`로 병합하지도, push하지도 않는다. 원래 브랜치는 로컬에만 둔다. 기존 ref를 고치지 않으므로 이력 재작성도 아니다.
    - [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)이 끝나면 그 결과를 공개용 새 브랜치로 옮긴다.
      1. 10절 2단계 뒤에 `origin/main`에서 `plan/qtvzskgx-vm-rollout-public`을 만든다.
      2. `git merge --squash plan/qtvzskgx-vm-rollout`으로 결과만 가져온다.
      3. IP를 자리표시자(`<agent-hub tailnet IP>`)로 바꾸고 커밋 하나로 만든다. 트레일러는 `Assisted-by`(참여한 도구 전부), `Plan: qtvzskgx`, `Task: none`이다.
      4. 위의 점검 명령으로 그 브랜치를 다시 검사한 뒤 push하고 PR을 연다.
    - PR 본문에 원본 브랜치 이름과 squash로 옮겼다는 사실을 적는다.
- **앞으로의 기록 규칙:** Progress log, 런북, 리뷰 기록에는 VM의 외부 IP와 Tailscale IP를 적지 않는다. 호스트 이름(`agent-hub`)이나 자리표시자를 쓴다. 명령 출력을 옮길 때도 IP를 가린다. [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)에서 `AGENTS.md`의 Safety에 추가한다.
- **공개 전 점검:** 처음 공개되는 이력(2단계의 `main`, 진행 중인 브랜치의 첫 push)마다 다음을 찾는다.
  - 비밀값: `tskey-` 실제 값, 개인키
  - 인프라 식별자: VM 외부 IP, GCP 프로젝트 ID, tailnet 이름, `100.x` Tailscale IP
  - **Assumption:** [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)의 Progress log에는 VM 외부 IP가 기록돼 있을 수 있다.
- 2단계는 [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)의 런북보다 먼저 오므로, 점검 명령을 여기에 둔다. github-switch 계획이 이 명령을 런북으로 옮긴다. `<ref>`는 공개할 브랜치다. 걸린 줄은 사람이 하나씩 보고 테스트용 자리표시자인지 확인한다.

```
git log -p <ref> | grep -nE 'tskey-[A-Za-z0-9]{10,}|PRIVATE KEY|([0-9]{1,3}\.){3}[0-9]{1,3}|[a-z0-9-]+\.ts\.net|@[A-Za-z0-9.-]+\.[a-z]{2,}'
git log -p <ref> | grep -cF '<실제 VM IP 또는 GCP 프로젝트 ID>'
```

- 두 번째 명령은 사용자가 자기 터미널에서 실제 값을 넣어 실행한다.
- **걸리면 공개(push)를 멈춘다.** 현재 파일만 자리표시자로 바꿔도 과거 커밋에는 값이 남고, push하면 그 커밋이 함께 공개된다. 사용자가 다음 둘 중 하나를 정한 뒤에만 진행한다.
  - (a) 그 값의 공개를 허용한다.
  - (b) 공개 전 이력 정리를 명시적으로 승인한다. 이력 재작성은 정책상 금지이므로 사용자의 승인이 있어야 한다. 정리한 뒤에는 공개할 이력 전체를 위 명령으로 다시 검사한다.
- 걸린 값이 실제 자격증명(토큰, 키)이면 공개 여부와 관계없이 폐기하고 교체한다. 이력 정리는 이미 공개된 사본(fork, 캐시)까지 지우지 못한다([GitHub 안내](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
- 실제 값을 테스트나 스크립트에 넣어 검사하면 그 값이 공개된다. 그래서 자동 검사는 GitHub secret scanning과 push protection에 맡긴다.

## 12. 계획 분할

계획 번호 06은 `plan/g57mry4b-test-pruning`이 쓰고 있다. 07은 `plan/qtvzskgx-vm-rollout`에 있는 backlog 계획 `plan-2026-10-13-gaewewkf-ipv6-egress.md`가 쓰고 있다. 그래서 이 스펙의 계획은 08과 09다.

| 계획 | 범위 |
|---|---|
| 08 GitHub 전환 | `.github/workflows/ci.yml`·`pr-rules.yml`, `scripts/check-pr.sh`와 테스트, `make check-git`·`make review`의 base 기본값 변경, `.github/pull_request_template.md`, `.github/rulesets/main.json`, `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md`(부트스트랩, 공개 전 점검, 설정 적용, 토큰 교체), `docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md`의 머신 계정 항목, `AGENTS.md`의 `## Git`과 Safety(VM IP 기록 금지), git-workflow 스킬, 기존 정책 스펙의 상태 표시 |
| 09 리뷰 게시 | `scripts/post-review.sh`와 테스트, `make review-post`, git-workflow 스킬의 리뷰 절, branch-review 스킬, `docs/reviews/README.md`, `AGENTS.md`의 `## Code Review Rules` 3·6번("CI 통과"로 바꿈) |

## 13. 위험과 대응

| 위험 | 대응 |
|---|---|
| 머신 계정 토큰 유출 | 범위를 `public_repo`·`workflow`로 줄이고 90일 만료로 둔다. 키체인에 보관한다. 유출되면 즉시 폐기하고 런북 절차로 재발급한다 |
| 머신 계정이 승인 뒤에 병합 | `AGENTS.md` 규칙으로 막는다. 승인 없이는 병합이 불가능하다. PR의 `merged_by`로 사후 확인한다 |
| 에이전트가 CI를 약하게 수정 | 워크플로 변경도 PR과 사람의 승인을 거친다. PR 워크플로는 읽기 전용이고 비밀값이 없다 |
| 필수 체크가 생기기 전에 ruleset을 켬 | 10절 순서대로, [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md) 병합 뒤에 적용한다 |
| 민감한 값 공개 | 11절의 공개 전 점검과 push protection으로 막는다 |
| 외부 PR·스팸 | 승인 1개가 필수다. 외부 협업자의 워크플로는 실행 전에 승인을 받는다 |
| 샌드박스가 네트워크를 막는 도구(Codex CLI 등) | push와 `gh` 호출을 사람에게 부탁한다. 지금 `make review`의 규칙과 같다 |
| ruleset 비활성화를 잊음 | 긴급 변경은 Incident log에 기록하고, 다시 켰는지 확인한다 |

## 14. Open questions

1. (결정됨, 2026-10-13) 기존 커밋의 작성자 이메일(`yanghs632@gmail.com`)은 그대로 공개한다.
2. (결정됨, 2026-10-13) VM IP는 감춘다. VM 외부 IP는 어떤 커밋에도 없다. Tailscale IP가 있는 `plan/qtvzskgx-vm-rollout`은 11절의 예외 절차로 공개한다.
3. (확인됨, 2026-10-14) [github-switch 계획](../plans/plan-2026-10-13-k93wjt1a-github-switch.md)의 squash 커밋 47ed954의 작성자는 PR 작성자인 머신 계정이고 커미터는 `GitHub`이다. 브랜치 커밋의 작성자가 사람이었으므로 GitHub이 본문 끝에 `Co-authored-by: yanghs6 <...>`를 덧붙였다. 이 줄은 사람이 아니라 GitHub이 붙인 것이므로 정책 위반이 아니다. `check-pr.sh`는 PR 본문만 읽으므로 허용 범위를 바꾸지 않는다. 2026-10-14 사용자 결정으로 커밋 작성자도 머신 계정으로 바꿨다(3절).
4. (확인됨, 2026-10-14) 이 공개 저장소에서 `secret_scanning`과 `secret_scanning_push_protection`은 enabled이고, `secret_scanning_non_provider_patterns`, `secret_scanning_validity_checks`, `dependabot_security_updates`는 disabled다. 머신 계정 토큰에는 이 필드가 보이지 않아 소유자 계정의 설정 디렉터리(`GH_CONFIG_DIR`)로 읽었다.
5. (결정됨, 2026-10-14) 머신 계정은 `yanghs6-bot`이다.
