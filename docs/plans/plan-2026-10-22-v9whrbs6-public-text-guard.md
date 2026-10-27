---
status: active
id: v9whrbs6
spec: docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md
---

# v9whrbs6 Public Text Guard Implementation Plan

> 2026-10-22 에이전트 개발 시스템 평가(저장소 밖 기록)에서 나온 백로그 초안입니다. 실행하려면 먼저 사용자가 이 계획을 승인하고 배경 끝의 Open question 1~3을 정해야 합니다. 설계 범위가 작아서 새 스펙을 쓰지 않고, Task 1의 ADR로 스펙 6절과 11절을 보완합니다. 사용자가 스펙을 원하면 brainstorming → 스펙 → 계획 순서로 다시 씁니다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 저장소 밖으로 나가는 텍스트를 기계적으로 검사해서, VM IP 주소, tailnet 호스트 이름, 세션 링크, `Generated with` 줄이 있으면 막는다. 대상은 tracked 파일, 커밋 메시지, PR 제목과 본문, PR에 올리는 리뷰 보고서다.

**Architecture:**
- 새 스크립트 `scripts/check-public-text.sh` 하나가 패턴과 허용 집합을 모두 가진다. 파일이나 stdin(`-`)을 받는다. 걸린 줄은 종류와 줄 번호만 출력하고 값은 가린 뒤 exit 1로 끝낸다. 인자 없이 부르면 현재 저장소의 tracked 파일과 새 파일을 검사하고, 예외 목록은 이 모드에서만 적용한다.
- 이 스크립트를 부르는 곳은 다음과 같다. `scripts/verify-vm.sh`가 `scripts/verify-mcp.sh`를 부르는 방식과 같다.
  - `make check`: repo 테스트가 tracked 파일을 검사한다.
  - `scripts/check-git.sh`: 커밋 메시지를 검사한다.
  - `scripts/check-pr.sh`: PR 제목과 본문을 검사한다.
  - `scripts/post-review.sh`, `scripts/post-review-record.sh`: 게시 직전의 본문을 검사한다.
- 비밀값 검사는 지금처럼 GitHub push protection과 GitGuardian에 맡긴다. 이 계획은 GitGuardian 오탐을 정리하고, 전체 이력을 한 번 스캔해서 결과를 기록하는 일만 더한다.

**Spec:** `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md` (6절의 `check-pr.sh` 검사 목록, 8절 게시, 11절 공개 전 점검. 특히 234행 "자동 검사는 GitHub secret scanning과 push protection에 맡긴다")

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 사용자가 이 계획을 승인했고 Open question 1~3을 정했다.
- 다른 백로그 계획과는 독립적이다. 다만 [agent-sandbox 계획](plan-2026-10-22-k3bd8k47-agent-sandbox.md)(sandbox)과 [review-and-local-isolation 계획](plan-2026-10-22-z064dkcv-review-and-local-isolation.md)(리뷰 스크립트)이 Task 4의 게시 전 검사를 전제하므로, 이 계획을 먼저 병합한다.

## 배경

- **Reported (2026-10-22 평가):** AP3. `AGENTS.md:28`의 VM IP 규칙에 검사가 없다. 주입 실행에서 tailnet 대역 주소가 런북에서는 `make check`를, 커밋 메시지에서는 `check-git.sh`를, PR 본문에서는 `check-pr.sh`를 통과했다. 이 때문에 D4는 상한 2, D5는 상한 3이다.
- **Reported (2026-10-22 평가):** AP10 예방. 커밋 메시지 안의 `Claude-Session` 값(링크 없음), `Generated with`, IP, ts.net 이름이 모두 통과했다. 옛 공개 커밋 4개에 세션 링크가 남아 있다.
- **Verified (2026-10-22, `57993a3`):** 지금 있는 검사는 다음과 같다.
  - 세션 링크는 `scripts/check-pr.sh:13,59-60`만 PR 본문에서 찾는다.
  - 금지 트레일러는 `scripts/lib/git.sh:21`의 `Co-authored-by Signed-off-by`뿐이다.
  - `scripts/post-review.sh:61-65`는 크기만 확인하고 바로 `gh pr comment`를 실행한다.
  - `scripts/post-review-record.sh:21-43`은 파일을 그대로 `gh api` POST/PATCH로 올린다. `gh pr comment`가 아니다.
  - 가리기는 수동이다(`.agents/skills/git-workflow/references/review-and-merge.md:13`).
- **Verified (2026-10-22, `gh pr checks 16`):** PR #16에서 GitGuardian이 fail이었다. 원인은 `tests/bootstrap-vm.bats:54`의 가짜 키이고, PR 본문도 오탐이라고 적었다. 필수 체크는 `check`와 `pr-rules`뿐이다(`.github/rulesets/main.json:32-35`).
- **Verified (2026-10-22):** 스펙 11절이 자동 검사를 GitHub에 맡긴 이유는 "실제 값을 넣으면 공개된다"는 것이다. 이 계획의 검사는 실제 값을 넣지 않고 패턴만 쓰므로 그 근거와 충돌하지 않는다. 하지만 6절 목록과 11절 문장의 범위를 넓히므로 ADR로 남긴다.
- **Verified (https://tailscale.com/kb/1033/ip-and-dns-addresses):** tailnet IPv6는 Tailscale이 공개한 ULA 접두사에서 받는다. `AGENTS.md:28`은 tailnet IP 전체를 금지하므로 이 접두사도 검사한다. 저장소에는 0곳이다.
- **Verified (2026-10-22):** `git ls-files`는 `.claude/skills/<이름>` 심볼릭 링크(디렉터리)도 나열하므로, 일반 파일만 읽어야 한다.

**지금 문서에서 생길 오탐.** **Verified (2026-10-22, `57993a3`):** 읽기 전용 grep으로 조사했다. 값은 출력하지 않고 종류별 개수만 셌다.

| 후보 패턴 | 걸리는 곳 | 계획의 처리 |
|---|---|---|
| IPv4, 허용 집합은 브리프 안(loopback, `0.0.0.0`, 문서용 대역, IAP 대역)만 | RFC 1918 대역 CIDR 26곳(문서 10개, GCP VPC 내부 대역). `tests/verify-vm.bats:64-66`에 일부러 넣은 사설·link-local·범위 밖 입력 6개. `docs/plans/plan-2026-10-13-g57mry4b-test-pruning.md:56,183`의 옥텟 범위 밖 숫자 2개. 스펙 54행의 tailnet 대역 표기 1개. [ipv6-egress 계획](plan-2026-10-13-gaewewkf-ipv6-egress.md)의 메타데이터 서버 주소 1개 | 허용 집합에 RFC 1918, link-local, 대역 표기(네트워크 주소/접두사)를 더한다. 옥텟이 0~255인 것만 주소로 본다. 그러면 0곳 |
| 같은 조건 | 공개 주소 8개. `docs/plans/plan-2026-10-07-qtvzskgx-vm-rollout.md:285,287,308`(제3자 서버 주소와 공개 DNS 리졸버), `docs/plans/plan-2026-10-13-gaewewkf-ipv6-egress.md:21-22`(공개 DNS 리졸버) | 완료된 기록이므로 고치지 않고 예외 목록에 넣는다(Open question 1) |
| 자리표시자가 아닌 `*.ts.net` | 84곳 모두 자리표시자다. `example` 31곳, `<…>`·`*`·`{…}` 36곳, `tail1234` 15곳(파일 9개), `host.tailnet` 2곳 | 자리표시자 규칙: `example`, `<`, `*`, `{`가 들어 있거나, 라벨이 `tail1234`·`tailnet`인 이름 |
| 문자열 `claude.ai/code/session` | 규칙을 설명하는 문장 3곳(스펙 125행, `scripts/check-pr.sh:13`, `tests/check-pr.bats:90`) | id가 붙은 링크(`session_` 뒤에 영숫자)와 줄 첫머리의 `Claude-Session:`로 좁힌다. 걸리는 곳은 `tests/check-pr.bats:90`의 가짜 id 1곳뿐 |
| 문자열 `Generated with` | 규칙과 인용 문장이 있는 파일 7개 | `Generated with`로 시작하는 줄로 좁힌다(앞에는 공백, 목록·인용 기호, 이모지만 올 수 있다). 0곳 |

**Open question 1:** 완료된 기록 안의 공개 주소와 must-fail fixture를 어떻게 예외로 둘 것인가?
- A. tracked 모드 전용 예외 파일을 둔다. 한 줄에 `<경로> <종류>`를 적고, 값은 적지 않는다. 항목은 [vm-rollout](plan-2026-10-07-qtvzskgx-vm-rollout.md)·[ipv6-egress](plan-2026-10-13-gaewewkf-ipv6-egress.md) 계획의 IPv4, `tests/check-pr.bats`의 세션 링크, `tests/fixtures/check-public-text/`의 전 종류다. 장점: 기록을 고치지 않고, 예외 파일 자체가 깨끗하다. 단점: 그 파일에서 같은 종류의 새 값은 놓친다. 완료된 기록은 바뀌지 않으므로 위험은 작다.
- B. [vm-rollout](plan-2026-10-07-qtvzskgx-vm-rollout.md)·[ipv6-egress](plan-2026-10-13-gaewewkf-ipv6-egress.md) 계획의 주소 8개를 자리표시자로 바꾼다. 장점: 예외가 fixture만 남는다. 단점: 기록의 증거를 고치는 일이라 doc-authoring 규칙에 어긋나므로 사용자 승인이 필요하다.
- C. `origin/main` 이후 바뀐 줄만 검사한다. 단점: `.github/workflows/ci.yml:21-23`이 `fetch-depth`를 정하지 않아 CI `check` job에는 base가 없다.
- 추천: A. 증거를 건드리지 않고, 예외 범위를 한 파일에서 한눈에 리뷰할 수 있다.

**Open question 2:** 전체 이력 스캔을 어떻게 실행할 것인가? 사용자는 테스트용으로 `.git`을 마운트하는 raw `docker run`을 한 번 거절했다.
- A. `make secret-scan` 타깃을 만든다. `make test`와 같은 `DOCKER_RUN` 마운트(git common dir은 `:ro`)를 쓰고, 이미지는 digest로 고정한다. 새 Make 타깃이므로 사용자 OK가 필요하다. 장점: 다시 실행할 수 있고, 스펙 11절의 공개 전 점검에도 쓸 수 있다.
- B. 사용자가 자기 터미널에서 설치한 gitleaks로 실행하고 건수만 알려 준다. 장점: 저장소 변경이 없다. 단점: 다시 실행할 명령과 버전이 고정되지 않는다.
- C. `workflow_dispatch` 워크플로를 만든다. `tests/repo-github.bats:9` 규칙은 만족시킬 수 있다. 단점: 로컬에만 있는 브랜치는 볼 수 없다. gitleaks-action의 라이선스 조건은 확인하지 않았다(**Assumption**).
- 추천: A.

**Open question 3:** GitGuardian 오탐을 어떻게 정리할 것인가?
- A. 사용자가 대시보드에서 incident를 test credential이나 false positive로 닫는다. 범위를 넓히려면 `tests/**` filepath exclusion을 이 저장소에 연결한다. 문서로 확인된 방법이다(Task 5).
- B. 저장소에 `.gitguardian.yaml`을 둔다. 하지만 GitHub App이 이 파일을 읽는지는 문서로 확인되지 않는다(**Assumption**).
- C. fixture 값을 탐지기가 잡지 않는 모양으로 바꾼다. 하지만 탐지 규칙을 모르므로 효과를 확인할 수 없다.
- 추천: A, 그리고 런북에 기록한다.

## Global Constraints

- 검사는 패턴으로만 한다. 실제 VM IP, tailnet 이름, 세션 id를 테스트나 스크립트에 넣지 않는다(스펙 11절). must-fail 입력은 문서용 대역, `example`, 가짜 id로 만든다. tailnet 대역처럼 문서용 대체값이 없는 경우에는 누가 봐도 가짜인 값을 쓴다.
- 걸린 값은 출력하지 않는다. 종류, 위치, `mask` 결과만 출력한다(`AGENTS.md:17`).
- 스크립트 규칙은 `AGENTS.md:15-18`을 따른다. 새 스크립트는 `make new-script`로 만들고, 테스트는 `make test`·`make check`로만 돌린다(script-authoring 스킬).
- 새 컨테이너 이미지는 digest로 고정한다(`AGENTS.md:14`).
- 워크플로를 고치면 스펙 6절을 지킨다. `permissions: contents: read`, 식은 `env:`로 넘기고, Action은 SHA로 고정한다(`tests/repo-github.bats:9`).
- GitGuardian 대시보드와 ruleset은 사용자만 바꾼다. `AGENTS.md`를 고칠 때는 사용자 OK를 받는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: v9whrbs6`, `Task: <N|review|none>`.

## Review Focus

1. `scripts/check-pr.sh:46-48`의 주석에 따르면 GitHub은 PR 본문을 CRLF로 보낸다. 줄 끝이 CRLF여도 걸리고, PR 제목에 있어도 걸려야 한다. Task 3의 `tests/check-pr.bats` 사례가 고정한다.
2. 예외 목록은 인자 없는 tracked 모드에만 적용된다. stdin이나 명시한 파일에는 적용되지 않는다. Task 1의 테스트가 고정한다.
3. 주소처럼 보이지만 주소가 아닌 것은 통과해야 한다. 예: 숫자 다섯 개를 점으로 이은 버전 문자열, 옥텟이 255를 넘는 값, `v8.30.1`. Task 1의 통과 사례가 고정한다.
4. 검사 스크립트 자신과 must-fail fixture 때문에 `make check`가 실패하면 안 된다(자기 자신에 걸리는 문제). Task 2의 repo 테스트가 고정한다.
5. 커밋 메시지는 제목만이 아니라 본문과 트레일러까지 전부 검사한다. Task 3의 `tests/check-git.bats` 사례가 고정한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `scripts/check-public-text.sh` | 패턴, 허용 집합, 자리표시자 규칙, 예외 목록 적용, 가린 출력 | 1 |
| `tests/check-public-text.bats`, `tests/fixtures/check-public-text/` | 짝 테스트와 must-fail·통과 fixture | 1 |
| `make new-doc TYPE=adr SLUG=public-text-guard`가 만드는 ADR | 패턴, 허용 집합, 예외 방식, 검사 위치를 결정으로 남기고 스펙 6절·11절을 보완 | 1 |
| 예외 목록 파일(이름은 ADR에서 정함), `tests/repo-public-text.bats` | `make check`의 tracked 파일 검사 | 2 |
| `scripts/lib/git.sh`, `scripts/check-git.sh`, `scripts/check-pr.sh` | `pr-rules`의 커밋 메시지·PR 검사, `Claude-Session` 금지 | 3 |
| `scripts/post-review.sh`, `scripts/post-review-record.sh` | 게시 전 검사 | 4 |
| `Makefile`, `tests/repo-make.bats`, `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md` | 전체 이력 스캔과 GitGuardian 오탐 정리 | 5 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/v9whrbs6-public-text-guard` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Public text checker and ADR

**Files:**
- Create: `scripts/check-public-text.sh`, `tests/check-public-text.bats` (`make new-script NAME=check-public-text`. `check`는 동사 표에 있다)
- Create: `tests/fixtures/check-public-text/` (종류별 must-fail 파일 하나씩과 통과 파일 하나)
- Create: ADR (`make new-doc TYPE=adr SLUG=public-text-guard`)
- Modify: `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md:5` (`amended-by`를 목록으로 바꾸고 새 ADR을 더한다)

**Interfaces:**
- Produces: `scripts/check-public-text.sh [--label NAME] [FILE|-]...`.
  - 걸린 곳이 없으면 exit 0이다.
  - 걸리면 `<NAME 또는 경로>:<줄>: <종류>`를 한 줄씩 stderr로 출력하고, 가리는 방법을 한 줄 안내한 뒤 exit 1로 끝난다. 종류는 `IPv4 address`, `tailnet IPv6 address`, `ts.net host name`, `session link`, `Generated with line`이다.
  - 인자가 없으면 현재 디렉터리의 저장소(`git rev-parse --show-toplevel`)에서 tracked 파일과 새 파일 가운데 일반 텍스트 파일만 검사하고, 예외 목록을 적용한다.

- [ ] **Step 1: 실패하는 테스트 작성.** `tests/check-public-text.bats`에 테스트 세 개를 둔다.
  - "flags every kind and prints no matched value": must-fail 파일마다 실패하는지, 종류와 줄 번호가 나오는지, `refute_output --partial`로 값 전체가 출력되지 않는지 확인한다. 각 사례는 서브셸 반복으로 돌린다.
  - "passes the allowed forms": 통과 파일이 통과해야 한다. 이 파일에는 다음을 넣는다.
    - 허용 주소: loopback, `0.0.0.0`, 문서용 대역(`203.0.113.10`), IAP 대역(`docs/specs/spec-2026-10-15-jr59pvyf-access-modes.md:70`가 인용한 대역), RFC 1918, link-local, 대역 표기
    - 주소가 아닌 숫자: Review Focus 3의 값
    - 자리표시자 ts.net 이름
    - 규칙을 설명하는 문장: 줄 중간의 `Generated with`, id 없는 `claude.ai/code/session`
    - CRLF 줄
  - "applies the exemption list only without arguments": `init_git_repo`로 만든 임시 저장소에서 예외 목록에 있는 파일은 인자 없는 모드로 통과하고, 같은 파일을 인자로 주거나 `-`로 넘기면 실패해야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 위 세 테스트만 템플릿의 `not implemented: write tests/check-public-text.bats first`로 실패한다.
- [ ] **Step 3: 최소 구현.**
  - 허용 대역과 자리표시자 라벨은 이름 있는 상수로 둔다.
  - 패턴이 이 파일 자신에 걸리지 않게 `[.]`이나 `[ ]`처럼 쓴다.
  - 대역 판정은 `scripts/verify-vm.sh:130-143`(`validate_public_ip`)처럼 옥텟을 `10#`으로 읽는다.
  - ADR에는 Open question 1의 결정, 검토한 대안(문자열 그대로 검사, 바뀐 줄만 검사, 비밀값 스캐너에 맡기기), 확인 방법(Task 2의 repo 테스트)을 적는다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋** `feat: add a public text checker for IPs, tailnet names and session links` (`Plan: v9whrbs6`, `Task: 1`).

### Task 2: Scan tracked files in make check

**Files:**
- Create: `tests/repo-public-text.bats`, 예외 목록 파일
- Modify: `docs/ARCHITECTURE.md:53` (구성 요소 표에 `scripts/check-public-text.sh`)
- Modify: `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md:34-48` (2절 공개 전 점검. IP·ts.net은 `git log -p <ref> | scripts/check-public-text.sh -`로 본다. 기존 grep은 `tskey-`·개인키·메일 주소용으로 남긴다)

- [ ] **Step 1: 실패하는 테스트 작성.** 빈 예외 목록 파일을 만들고, `tests/repo-public-text.bats`에 테스트 하나를 둔다. 이름은 "tracked and new files carry no public text outside the exemption list, and every exemption names an existing file"이다. 인자 없이 `scripts/check-public-text.sh`를 실행해 exit 0인지 확인하고, 예외 목록의 경로가 모두 실제 파일인지 확인한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 실패한다. 걸리는 곳은 오탐 조사 표에 있는 [vm-rollout](plan-2026-10-07-qtvzskgx-vm-rollout.md)·[ipv6-egress](plan-2026-10-13-gaewewkf-ipv6-egress.md) 계획의 IPv4, `tests/check-pr.bats:90`의 세션 링크, `tests/fixtures/check-public-text/`이다. 값은 가려져서 출력된다.
- [ ] **Step 3: 최소 구현.** Open question 1에서 정한 방식으로 예외를 넣는다. 다른 파일이 걸리면 자리표시자로 고친다. 기록 파일이라면 고치지 말고 사용자에게 묻는다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋** `test: scan tracked files for public text in make check` (`Plan: v9whrbs6`, `Task: 2`).

### Task 3: Check commit messages and the PR text in pr-rules

**Files:**
- Modify: `scripts/lib/git.sh:21` (`FORBIDDEN_TRAILERS`에 `Claude-Session`을 더한다)
- Modify: `scripts/check-git.sh:53-64` (`check_commit`에서 `git log -1 --format=%B`로 메시지 전체를 `--label "<짧은 SHA>"`와 함께 검사한다. 제목은 라벨에 넣지 않는다. 메시지에 걸린 곳이 있는 커밋은 `where`(지금 `:55`의 `%h "%s"`)도 SHA만 쓰고, `:49`의 트레일러 값도 출력하지 않는다)
- Modify: `scripts/check-pr.sh:13,59-60` (세션 링크만 찾던 검사를 제목과 본문 전체 검사로 바꾼다. 제목이나 본문에 걸린 곳이 있으면 `:27`, `:38`, `:52`의 메시지에서 제목과 트레일러 값을 빼고 출력한다)
- Modify: `.agents/skills/git-workflow/SKILL.md:31,34-35` (`gh pr create`·`gh pr edit` 전에 본문 파일을 `scripts/check-public-text.sh`로 검사한다), `AGENTS.md:28,35` (검사가 있는 곳 한 구절. 사용자 OK)
- Test: `tests/check-git.bats:75`, `tests/check-pr.bats:49`
- **Verified (2026-10-22):** `.github/workflows/pr-rules.yml:26,31`이 이미 두 스크립트를 실행하므로 워크플로는 바꾸지 않는다. push 전에 돌리는 `make check-git`도 같은 검사를 하게 된다(`.agents/skills/git-workflow/SKILL.md:27`).

- [ ] **Step 1: 실패하는 테스트 작성.**
  - `tests/check-git.bats:75`의 반복에 "public" 사례를 더한다. 커밋 제목과 본문에 fixture의 tailnet 대역 주소를 넣고 트레일러 `Claude-Session: x`(링크 없음)를 단다. 그러면 그 커밋의 짧은 SHA 뒤에 `agents never add 'Claude-Session'`과 IPv4 hit이 함께 나와야 하고, `refute_output --partial`로 주소가 출력에 없음을 확인한다.
  - `tests/check-pr.bats:49`에 사례를 더한다. 본문에 IP, ts.net 이름, `Generated with` 줄을 각각 넣고, CRLF 본문과 제목에 IP가 있는 경우도 넣는다. 제목에 IP가 있는 사례는 제목 형식도 어기게 해서, 제목 형식 위반 메시지에도 주소가 없음을 `refute_output --partial`로 확인한다. 세션 링크 사례는 실패를 그대로 확인하고, 기대 메시지만 새 검사의 것으로 바꾼다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 사례만 실패한다. 지금 `check-git.sh`는 메시지를 보지 않고, `check-pr.sh`는 세션 링크만 본다.
- [ ] **Step 3: 최소 구현.** 걸린 곳은 `add_problem`으로 모아서, 다른 위반과 함께 한 번에 보고한다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. 이어서 Run: `make check-git`. Expected: 둘 다 exit 0. PR의 `pr-rules`도 pass.
- [ ] **Step 5: 커밋** `feat: check commit messages and PR text for public text and forbid Claude-Session` (`Plan: v9whrbs6`, `Task: 3`).

### Task 4: Refuse to post review text with a hit

**Files:**
- Modify: `scripts/post-review.sh:61-65` (두 본문을 크기와 공개 텍스트 모두 검사한 뒤에 첫 `gh` 호출을 한다)
- Modify: `scripts/post-review-record.sh:21-24` (`gh api user`보다 먼저 findings 파일을 검사한다. 게시하는 곳은 `gh api` POST/PATCH인 `:38,43`이다)
- Modify: `.agents/skills/git-workflow/references/review-and-merge.md:13` (수동 가리기 문장을 "`make review-post`는 걸리면 게시를 거부한다. 보고서 파일을 고친 뒤 다시 실행한다"로 바꾼다)
- Test: `tests/post-review.bats:36`, `tests/post-review-record.bats:33`

- [ ] **Step 1: 실패하는 테스트 작성.**
  - `tests/post-review.bats:36`의 반복에 "public text" 사례를 더한다. plan 보고서에 fixture hit을 넣으면 실패해야 하고, 메시지에 그 보고서 경로가 나와야 하며, `refute_stub_called '^gh '`여야 한다.
  - `tests/post-review-record.bats:33`의 반복에도 같은 사례를 더한다. 이 사례는 `gh api user`도 부르지 않아야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 두 사례가 실패한다. 지금은 게시되기 때문이다.
- [ ] **Step 3: 최소 구현.** `die` 메시지에는 어느 보고서인지 적는다. 그리고 값을 `agent-hub`나 `<agent-hub tailnet IP>`로 바꾸거나 세션 링크와 `Generated with` 줄을 지운 뒤, 같은 `make review-post`·`make review-record` 명령을 다시 실행하라고 안내한다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋** `feat: refuse to post review text that carries public text` (`Plan: v9whrbs6`, `Task: 4`).

### Task 5: Secret-scanning hygiene

**Files:** (Open question 2·3에서 A안을 고른 경우)
- Modify: `Makefile:25-26` (`GITLEAKS_IMAGE`를 `zricethezav/gitleaks:v8.30.1@sha256:<digest>`로 둔다. digest는 실행할 때 릴리스 노트를 읽고 확인한다)
- Modify: `Makefile:32` (`.PHONY`), 새 `secret-scan` 타깃 (`$(DOCKER_RUN)`, 이미지 인자 `git --redact --log-opts=--all /repo`)
- Modify: `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md:34-48` (스캔 절차와 GitGuardian 오탐 처리 절차)
- Test: `tests/repo-make.bats`
- **Verified (2026-10-22, `gh api repos/gitleaks/gitleaks/releases`, Docker Hub 태그 API):** 최신 stable은 `v8.30.1`(2026-03-21)이고, Docker Hub 태그에 amd64와 arm64 이미지가 있다. README에 따르면 이력 스캔은 `gitleaks git`이다. `--log-opts`, `--redact`, `--report-path` 옵션이 있고, 오탐은 `.gitleaksignore`에 fingerprint로 적는다.
- **Verified (https://docs.gitguardian.com/ggshield-docs/configuration):** `.gitguardian.yaml`(`version: 2`, `secret.ignored_paths`, `secret.ignored_matches`)은 ggshield CLI의 설정 파일이다. 이 페이지는 GitHub App이 이 파일을 읽는다고 말하지 않는다.
- **Verified (https://docs.gitguardian.com/internal-monitoring/prevent/detect-secrets-in-real-time-in-github, https://docs.gitguardian.com/secrets-detection/customize-detection/exclusion-rules):** GitHub App 쪽에서 문서로 확인되는 방법은 세 가지다.
  - 대시보드에서 incident를 닫으면 check run이 다시 올리지 않는다.
  - check run의 "Skip: false positive"나 "Skip: test credential"을 쓸 수 있다.
  - workspace 설정의 filepath exclusion은 저장소별로 연결할 수 있다.

- [ ] **Step 1: 실패하는 테스트 작성(A안).** `tests/repo-make.bats`에 테스트를 더한다. docker stub을 두고 `make_in`으로 `make secret-scan`을 실행한다. stub 로그에 `@sha256:`으로 고정된 gitleaks 이미지, git common dir의 `:ro` 마운트, `git --redact`가 있어야 한다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 타깃이 없어서 새 테스트만 실패한다.
- [ ] **Step 3: 구현과 1회 스캔.**
  - 타깃을 더한다.
  - 사용자에게 OK를 받고 `git fetch origin` 뒤 `make secret-scan`을 실행한다. PR에만 남은 커밋(`refs/pull/<N>/head`, 스펙 5절의 Assumption)까지 보려면 그 ref를 받을지도 사용자에게 묻는다.
  - 이어서 `git log -p origin/main | scripts/check-public-text.sh -`로 이력의 공개 텍스트 hit을 종류별 개수로만 센다. 옛 세션 링크 커밋 4개는 이미 알려진 AP10이다.
  - 가짜 키 fixture가 걸리면 `.gitleaksignore`에 fingerprint를 적는다.
- [ ] **Step 4: 통과 확인.** Run: `make check`, `make secret-scan`. Expected: 둘 다 exit 0. 스캔 결과는 Progress log에 `Verified`로 남긴다. 스캐너 버전, digest, 범위, 커밋 수, 규칙별 건수를 적고 값은 적지 않는다.
- [ ] **Step 5: GitGuardian(사용자).** Open question 3에서 정한 방법으로 `tests/bootstrap-vm.bats:54`의 incident를 정리한다. 그 결과를 런북과 Progress log에 적는다.
- [ ] **Step 6: 커밋** `chore: add a pinned full-history secret scan and record the result` (`Plan: v9whrbs6`, `Task: 5`).

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge). 이때부터 Task 4의 검사가 게시를 막을 수 있다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- GitGuardian을 필수 체크로 올리는 일. ruleset 변경이므로 사용자가 적용하고, 오탐을 정리한 뒤에 한다.
- 옛 공개 커밋 4개에 남은 세션 링크(AP10). 이력 재작성은 `AGENTS.md:32`가 금지한다. 평가 보고서의 대안(루브릭 문구 수정)과 함께 사용자가 정한다.
- 에이전트가 `gh pr comment`·`gh pr create`를 직접 실행하는 경로. 이 계획에서는 스킬 지침만 고친다. 명령 단위로 막는 일은 [agent-sandbox 계획](plan-2026-10-22-k3bd8k47-agent-sandbox.md)(sandbox, hook)으로 넘긴다.
- GCP 프로젝트 ID와 VM 외부 IPv6. 패턴만으로는 구별할 수 없거나 아직 없다([ipv6-egress 계획](plan-2026-10-13-gaewewkf-ipv6-egress.md)). 스펙 11절의 사용자 터미널 점검을 그대로 쓴다.
- `validate_public_ip`와 대역 판정을 공유할지는 이 계획에서 정하지 않는다. 중복이 문제가 되면 따로 정리한다.
- 테스트 무결성 검사, raw `ssh -L` 검사, 이미지 digest 검사는 [invariant-enforcement 계획](plan-2026-10-22-m97w7hqe-invariant-enforcement.md)에서 한다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-26 | Verified | 사용자가 계획을 승인하고 Open question 1~3을 모두 A로 정했다(예외 파일, `make secret-scan`, GitGuardian 대시보드). Task 1에 더할 규칙: 대역 표기는 네트워크 주소일 때만 허용하고, CGNAT 낱개 주소는 파일에 쓰지 않는다(테스트는 실행 중에 만든다). 이 규칙으로 [web-connector 계획](plan-2026-10-22-d3dpb00s-web-connector.md):106과 맞춘다. |
| 2026-10-26 | Verified | Task 1: 먼저 `make test`에서 새 테스트만 템플릿의 `not implemented`로 실패하는 것을 확인했다. 구현 뒤 `make check`는 exit 0, 테스트 153개 ok(읽을 수 없는 파일 사례 1개는 테스트 컨테이너가 root라 skip), 줄 커버리지 87.70%(최소 80%)였다. `scripts/check-public-text.sh`의 파일 커버리지는 37.50%다. kcov가 작은따옴표 안의 awk 프로그램 줄을 bash 줄로 세기 때문이다. 인자 없는 실행에서 걸린 곳은 fixture, vm-rollout·ipv6-egress 계획의 IPv4 4줄, `tests/check-pr.bats:109`의 세션 링크다. vm-rollout 287행은 네트워크 주소 대역 표기라서 통과한다. 독립 리뷰(P0·P1 없음)의 P2 두 건, 즉 읽을 수 없는 파일이 통과하는 문제와 대역 표기 접두사 상한이 없는 문제(/24로 정함)를 고쳤다. P3 세 건(`example` 라벨 규칙, 세션 링크 대소문자, CRLF·예외 줄 테스트)도 고쳤다. |
| 2026-10-26 | Verified | Task 2: 빈 예외 목록에서 `make test`를 돌리자 새 repo 테스트 1개만 실패했다(값은 가려지고 경로·줄·종류만 출력). 예외 8줄을 넣은 뒤 `make check`는 exit 0, 154개 ok, 줄 커버리지 87.70%였다. 읽기 전용 이력 스캔 `git log -p origin/main \| scripts/check-public-text.sh -`(`67401d2`)는 IPv4 7건, 세션 링크 6건이었고 tailnet IPv6·ts.net·Generated with는 0건이었다. 값은 보지 않았다. |
| 2026-10-26 | Verified | Task 3: 코드보다 먼저 쓴 `make test`에서 새 사례 3개(13, 19, 20)만 실패했다. 구현 뒤 `make check`는 exit 0, 156개 ok, 줄 커버리지 87.95%(`check-git.sh`·`lib/git.sh` 100%, `check-pr.sh` 97.87%)였고 `make check-git`도 OK였다. 트레일러에만 값이 있는 사례는 `check_commit`을 일부러 제목만 읽도록 바꿔 돌렸을 때 그 사례만 실패하는 것을 확인했다. 독립 리뷰에서 P0·P1은 없었다. P2(`add_public_text_problems`의 lib 테스트와 검사기가 실패할 때 막는 경로)와 P3(Review Focus 5를 따로 고정)을 반영했다. 계획 Step 1과 다른 점: check-pr 테스트의 ts.net·`Generated with` 본문 사례는 `tests/check-public-text.bats`와 겹쳐서 넣지 않았다(테스트 범위 ADR 결정 2). AGENTS.md 28·35행 수정은 사용자 OK를 받았다(2026-10-26). |
| 2026-10-26 | Verified | Task 4: 코드보다 먼저 쓴 `make test`에서 새 사례 2개(post-review, post-review-record)만 "expected to fail"로 실패했다. hit이 있는데도 게시했기 때문이다. 구현 뒤 `make check`는 exit 0, 156개 ok, 줄 커버리지 88.00%였고 `make check-git`도 OK였다. `post-review.sh`는 게시하는 텍스트의 출처인 헤더와 보고서 두 개를 첫 `gh` 호출 전에 검사한다. 이렇게 하면 걸린 줄 번호가 사용자가 고칠 보고서 파일을 기준으로 나온다. |
| 2026-10-27 | Verified | Task 5 이미지: gitleaks 최신 stable은 `v8.30.1`(2026-03-21, `gh api repos/gitleaks/gitleaks/releases`)이다. v8.30.0·v8.30.1 릴리스 노트에 `gitleaks git`, `--redact`, `--log-opts`, `.gitleaksignore`의 breaking change는 없다. Docker Hub 태그 API의 index digest는 `sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f`이고 amd64와 arm64가 있다. Dockerfile의 entrypoint는 `gitleaks`이고 `safe.directory '*'`가 설정돼 있다. `make test`에서 새 repo-make 테스트 1개만 실패하는 것을 확인한 뒤 타깃을 더했고, `make check`는 exit 0, 157개 ok, 88.00%였다. 결과에 fingerprint가 나오도록 타깃에 `--verbose`를 더했다(값은 `--redact`가 가린다). |
| 2026-10-27 | Verified | Task 5 스캔(사용자 OK, 범위는 로컬 ref와 PR ref): `git fetch origin '+refs/pull/*/head:refs/pr-scan/*'`(PR ref 27개) 뒤 `make secret-scan`을 돌렸다. gitleaks v8.30.1로 커밋 504개를 봤고 exit 1(make exit 2), `generic-api-key` 2건이었다. 둘 다 web-connector 브랜치 커밋 `15da288`의 `tests/helpers.bash:35`, `tests/lib-vm.bats:191`에 있는 가짜 테스트 값(이름 그대로 test 문자열, 반복 hex)이다. 이 브랜치와 `main`에는 걸린 곳이 없다. squash 병합 뒤 커밋 SHA가 바뀌므로 `.gitleaksignore`에 적지 않고, 그 브랜치에서 `gitleaks:allow`로 처리하도록 감독 세션에 넘겼다. `refs/pr-scan/*`는 스캔 뒤 지웠다. 처음에 `refs/remotes/origin/pr/*`로 받은 ref는 다른 worktree의 `fetch --prune`이 지워서 두 번째 실행은 163개만 봤다. 그래서 런북에 별도 namespace 절차를 적었다. |
| 2026-10-27 | Verified | Task 5 공개 텍스트 이력 집계: `git log -p origin/main \| scripts/check-public-text.sh -`(`67401d2`, 커밋 162개)는 IPv4 7건, 세션 링크 6건이었다. 값은 보지 않았다. 세션 링크는 이미 알려진 AP10(Follow-ups)이다. IPv4는 예외 목록에 오른 기록 계획들의 증거 줄이 이력에 남은 것으로 추정한다(**Assumption**, stdin에는 예외 목록이 적용되지 않는다). |
| 2026-10-27 | Verified | Task 5 GitGuardian(사용자): 사용자가 대시보드에 열린 incident가 없다고 확인했다. 이 PR의 GitGuardian check도 pass다. |
