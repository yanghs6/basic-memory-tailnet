---
status: approved
date: 2026-10-26
---

# 문서 고유 ID와 초안 보드 — 설계

- 구현 계획: [계획 26](../plans/plan-2026-10-26-26-doc-ids.md) 하나에 이력 재작성까지 담는다. 이 개편이 그 계획의 이름도 새 ID로 바꾼다.
- 근거 조사: [다중 에이전트 초안 공유 조사](../research/rsch-2026-10-23-multi-agent-draft-sharing.md)
- 결정: [ADR 0009](../decisions/adr-2026-10-23-0009-doc-ids-and-draft-board.md)
- 대체 범위: [문서 체계 설계](spec-2026-10-15-doc-system.md)의 번호 규칙(`make new-doc`의 "가장 큰 번호 + 1", 계획 `NN`·ADR `NNNN`), [Git 리뷰 정책](spec-2026-10-07-git-review-policy.md)의 브랜치 이름 `plan/<NN>-<slug>`, [GitHub PR 워크플로](spec-2026-10-13-github-pr-workflow.md)의 트레일러 `Plan: <NN|none>`. [웹 커넥터 계획](../plans/plan-2026-10-22-25-web-connector.md)에 있던 "Pending Requirements" 절은 이 스펙 §1로 옮겼다.

## 1. 목적과 범위

여러 기기(회사 Mac, 개인 Mac)와 여러 벤더(Claude Code, Codex)의 에이전트가 서로 쓰고 있는 스펙·계획 초안을 보지 못한다. 문서 번호는 각 체크아웃이 "가장 큰 번호 + 1"로 고르므로 커밋 전 초안끼리 번호가 겹친다. 이 개편은 모든 문서를 무작위 고유 ID로 구분하고, 승인 전 초안을 Basic Memory의 "초안 보드"에 두어 모든 에이전트가 찾게 하며, 기존 문서와 git 이력까지 새 규칙으로 바꾼다.

**사용자 결정 (2026-10-22~23)**
1. 공유 범위는 같은 Mac의 worktree끼리가 아니라 다른 기기와 다른 벤더의 에이전트까지다(대안: 한 Mac 안의 worktree만).
2. 승인 전 초안 본문은 Basic Memory에 두고 그것을 유일한 정본으로 한다. 사용자는 SilverBullet에서 읽고, 승인되면 저장소 문서로 옮긴다(대안: 초안도 공개 저장소에 일찍 push, 비공개 동반 저장소, 목록만 Basic Memory에 두기).
3. 순번 대신 uuid나 nanoid 같은 고유 키로 문서를 구분한다(대안: 번호를 두고 승인 때 붙이기).
4. 기존 문서의 체계와 이름에도 소급 적용한다. 기존 인용과 이력이 끊겨도 된다.
5. git 이력은 가급적 재작성한다. 재작성할 수 없으면 옛 번호와 새 ID를 잇는 대응표로 대신한다(2026-10-23, 감독 세션이 대응표 답을 전한 뒤 이 세션에서 사용자가 직접 다시 정함).
6. 초안 보드 규칙은 에이전트 기억 미러 스펙이 아니라 이 스펙에 둔다.
7. **Reported (2026-10-23, 감독 세션이 전달한 사용자 결정):** 이 개편이 모든 계획보다 먼저다.
8. 이력 재작성과 force-push는 에이전트가 직접 한다. `AGENTS.md`의 금지 규칙은 고치지 않고 이번 한 번만 허가한다(2026-10-26, 대안: 에이전트는 검증까지, push는 사용자).
9. 초안 보드에 만료 기본값을 두지 않는다(2026-10-26, 대안: `updated` + 7일).
10. 이력 재작성은 바꿀 수 있는 것을 모두 다시 쓴다(2026-10-26, 대안: HEAD 문서의 옛 경로와 커밋 트레일러만).

**범위 밖**
- 다른 저장소(회사 저장소)와 전역 지침(`~/.agents/AGENTS.md`)에 초안 보드를 적용하는 일. 이 저장소에서 쓴 뒤 따로 정한다.
- 에이전트 기억 미러의 색인 hook이 초안 보드를 함께 보여 주는 일. 계획 24를 맡은 세션과 정할 후속 항목이다(§7).
- Codex 클라우드 같은 클라우드 실행 환경이 승인 전 초안을 읽는 일. 클라우드에는 승인돼 저장소에 들어간 문서만 맡긴다.
- 초안의 동시 편집 잠금. 초안 하나는 주인 에이전트 하나만 쓴다.
- GitHub에 남은 옛 PR 제목·본문과 PR 참조(`refs/pull/*`)의 옛 커밋. 사용자가 고칠 수 없는 범위다.

**완료 조건**
1. `docs/` 아래 모든 타입 문서의 이름이 `<코드>-<날짜>-<ID>-<slug>.md`이고, front matter의 `id`가 이름의 ID와 같으며, ID가 저장소 전체에서 유일하다. `make check`의 문서 검사가 이를 강제한다.
2. `make new-id`가 새 ID를 출력하고, `make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]`가 그 ID(없으면 새 ID)로 문서를 만든다. 번호를 고르는 코드는 남지 않는다.
3. `make check-git`과 `pr-rules`가 `plan/<ID>-<slug>`와 `Plan: <ID|none>`을 받는다. 옛 형식(`plan/NN-…`, `Plan: NN`)은 개편 PR이 병합된 뒤의 결과 PR(Task 5)부터 거부한다.
4. 저장소 안 문서·스킬·`AGENTS.md`·스크립트 주석·테스트의 옛 번호 인용과 옛 경로가 새 이름으로 바뀐다. 문서 링크·경로 검사가 통과하고, §3.4의 옛 번호 grep이 대응표 밖에서 0건이다.
5. 옛 번호·옛 이름과 새 ID를 잇는 대응표가 ADR 0009의 부록으로 남는다.
6. 이력 재작성을 하면(§3.5):
   - 재작성한 `main`의 어느 커밋에도 대응표의 옛 경로가 없다.
   - 파일 내용과 커밋 메시지에 옛 번호 패턴이 없다(대응표 부록 제외).
   - `main` 안의 앞선 커밋을 가리키는 SHA 인용은 새 SHA다.
   - PR #1~#20의 제목·본문과 머신 계정 코멘트도 같은 규칙으로 바뀌어 있다.
   - 재작성 전후 HEAD tree의 차이는 SHA 인용 치환뿐이다.
7. `doc-authoring` 스킬의 초안 흐름대로 한 기기에서 Basic Memory에 초안을 만들고, 다른 기기나 다른 벤더의 에이전트가 `search_notes`로 그 초안을 찾는다. 사람이 한 번 확인해 계획의 Progress log에 남긴다.

## 2. 근거가 된 사실 (2026-10-23, `main` a0493ad)

번호 체계:
- **Verified:** `scripts/lib/docs.sh:95-112`의 `next_doc_number`는 모든 로컬·원격 추적 브랜치와 작업 트리의 파일 이름에서 가장 큰 번호를 찾아 1을 더한다. 옛 이름 두 세대(`YYYY-MM-DD-NN-slug.md`, `NNNN-slug.md`)도 읽는다(`:97-99`). 다른 worktree의 커밋 전 파일과 다른 기기의 push 전 파일은 보지 못한다.
- **Verified:** `scripts/create-doc.sh:31-46`이 이름을 만들고 템플릿의 `{{date}}`·`{{number}}`·`{{slug}}`를 채운다. 타입 표(`docs/README.md:7-14`)의 `번호` 열은 `없음`·`NN`·`NNNN`이고, `scripts/lib/docs.sh:18`의 `DOC_TYPES_HEADER`가 그 열 이름을 고정한다.
- **Verified:** `tests/repo-docs.bats:9`의 `ALLOWED_KEYS`에 `id`가 없어 지금은 `id` 키를 거부한다. `:88-98`은 번호 중복을, `:120-132`는 이름 형식을, `:154-162`는 `spec`·`amended-by`·`superseded-by` 값이 실제 파일인지를 검사한다.
- **Verified:** `scripts/check-git.sh:12`의 `BRANCH_PATTERN`은 `plan/[0-9]{2}-…|work/…`이고, `scripts/lib/git.sh:19`의 `PLAN_PATTERN`은 `^([0-9]{2}|none)$`이다. `scripts/check-pr.sh:32-40`이 PR 본문의 `Plan`을 같은 패턴으로 본다. `scripts/review-branch.sh:128`은 계획을 커밋의 `Plan` 트레일러로 찾는다.
- **Reported (2026-10-22, 웹 커넥터 세션):** 에이전트 기억 미러 스펙이 커밋 전 본문에만 "계획 24"를 적어 두었고, 다른 세션의 `make new-doc`이 24를 다시 내줘서 웹 커넥터 계획을 손으로 25로 바꿨다.

바뀔 범위(2026-10-23 읽기 전용 전수 조사):
- **Verified:** 타입 문서는 스펙 10, 계획 25, ADR 8(이 스펙과 함께 9), 런북 5, 조사 4, 리뷰 기록 10개다. `id` 키를 가진 문서는 없다.
- **Verified:** 저장소 안 인용은 "계획 NN" 654곳(49개 파일), "ADR NNNN" 266곳, 본문 속 `Plan: NN` 178곳, `plan/NN-…` 194곳, 문서 상대 링크 136곳, 백틱 문서 경로 333곳, front matter 경로(`spec` 21, `amended-by` 12, `superseded-by` 1)다.
- **Verified:** 번호가 아닌 숫자가 섞여 있다. "ADR 6개" 같은 개수, "계획 1/5" 같은 분수, `scripts/lib/docs.sh:94`의 "ADR 2026"(연도), "결정 N", "Task N", "R1-F1", PR "#NN"이다. 계획 02~04는 한때 03~05에서 번호가 바뀌었다(`docs/specs/spec-2026-10-07-git-review-policy.md:178`).
- **Verified:** `tests/repo-cloud-neutral.bats:6,31`이 `rbk-2026-10-12-gcp-vm.md`를 이름으로 고정하고, 스크립트 다섯 곳(`scripts/bootstrap-vm.sh:55,57`, `scripts/verify-vm.sh:111,113,134`, `scripts/lib/vm.sh:53`)이 그 경로를 메시지에 쓴다. `.github/workflows/ci.yml:2`, `pr-rules.yml:2`, `tests/repo-config.bats:5`, `Makefile`, 코드 블록 안의 경로는 문서 경로 검사(`tests/repo-docs.bats:53-67`) 범위 밖이다.

git 이력:
- **Verified:** `main`은 커밋 158개이고, 139개에 `Plan` 트레일러가 있으며 그중 109개가 숫자다. 제목 40개가 계획·ADR 번호나 `Merge plan/0N-…`를 쓰고, 본문 123줄이 문서 경로나 번호를 쓴다. 문서 이름은 `eda0d92`(#13)에서 지금 형식으로 한 번 바뀌었으므로 이력에는 세 세대의 이름이 있다.
- **Verified:** `main` 룰셋에 `non_fast_forward`, `required_linear_history`, `deletion`, `pull_request`, `required_status_checks`가 있고 `bypass_actors`는 비어 있다(`.github/rulesets/main.json`). 그래서 규칙 하나만 꺼서는 `main`에 직접 push할 수 없고, [GitHub 런북](../runbooks/rbk-2026-10-14-github.md)의 "긴급 변경" 절대로 Enforcement 전체를 잠시 꺼야 한다. 이 Mac의 push는 머신 계정으로 나간다.
- **Verified:** HEAD에 없는 옛 문서도 이력에 있다. 지워진 OCI 시절 ADR과 런북, `docs/plans/{active,backlog,completed}/` 하위 폴더의 계획, 이름 끝이 `-design`인 스펙, 코드 접두어 없는 런북·리뷰·조사 이름이 있고, 서로 다른 두 문서가 ADR 번호 0001을 썼다.
- **Verified:** 문서가 증거로 인용한 7자리 16진 문자열은 213종이다.
- **Verified (2026-10-26, Command: `git rev-list --merges --count origin/main`, `gh api .../issues/comments`):** `main` 커밋 158개 가운데 merge 커밋이 12개다(룰셋이 생기기 전의 `Merge plan/0N-…`). PR은 #1~#20이고, PR 코멘트는 머신 계정 87개와 GitGuardian 봇 3개다.
- **Verified (2026-10-23, Command: `git filter-repo --version`):** 이 Mac에 `git filter-repo`가 없다. 이 설계는 그 도구를 쓰지 않는다(§3.5).
- **Verified ([조사 노트](../research/rsch-2026-10-23-multi-agent-draft-sharing.md) §4):** 공개 저장소에서 push한 커밋은 force-push나 삭제 뒤에도 PR 참조와 저장소 네트워크로 접근할 수 있다.

Basic Memory:
- **Verified ([에이전트 기억 미러 설계](spec-2026-10-22-agent-memory-mirror.md) §2):** `write_note`는 `title`·`content`·`directory`가 필수이고 `metadata`·`overwrite`를 받으며, 같은 경로에 노트가 있으면 `overwrite` 없이 오류를 낸다. `search_notes`에는 폴더 인자가 없고 `metadata_filters`로 frontmatter를 거른다. 터널이 꺼져 있으면 `ECONNREFUSED`다.
- **Verified (2026-10-22, `~/.codex/config.toml:115-116`):** 이 Mac의 Codex CLI는 `make tunnel`의 `http://127.0.0.1:18737/mcp`로 Basic Memory에 닿는다. Claude Code도 같은 주소를 쓴다.
- **Assumption:** SilverBullet이 마운트하는 노트 폴더(`compose.yaml`의 `${BM_KNOWLEDGE_DIR}/basic-memory`)가 Basic Memory `main` 프로젝트의 루트라서, `agent-drafts/` 노트가 SilverBullet에 보인다. Task에서 확인한다.

## 3. 설계

### 3.1 ID

- **형식:** 소문자와 숫자 8자, 알파벳은 Crockford base32의 소문자 `0123456789abcdefghjkmnpqrstvwxyz`(i·l·o·u 제외)다. 예: `k7m2x9qa`.
  - **내 결정:** uuid(36자)는 파일 이름, 브랜치 이름, 트레일러에 쓰기에 길다. 대소문자를 섞지 않는 것은 macOS 파일 시스템이 대소문자를 구분하지 않기 때문이다. 32^8은 약 1.1조라서 문서가 1만 개여도 충돌 확률은 약 0.005%다.
- **생성:** `scripts/lib/docs.sh`의 `new_doc_id`가 `/dev/urandom`에서 만든다. 만든 ID가 모든 로컬·원격 추적 브랜치와 작업 트리의 문서 이름(`doc_paths`)에 이미 있으면 다시 만든다.
- **위치:**
  - 파일 이름: `<코드>-<날짜>-<ID>-<slug>.md`. 모든 타입이 같은 형식이다. 날짜는 폴더를 시간순으로 보이게 하려고 남긴다.
  - front matter: 모든 타입에 `id` 키를 필수로 둔다. 이름과 front matter가 다르면 검사가 실패한다. 파일 이름만 보다 실제 충돌을 놓친 사례(조사 노트 §2) 때문이다.
  - 브랜치: `plan/<ID>-<slug>`. `work/<slug>`는 그대로다.
  - 트레일러: `Plan: <ID|none>`.
- **사람이 부르는 이름:** 본문에서는 slug로 부르고 링크를 건다. 예를 들어 "web-connector 계획"이라고 쓰고 그 계획 파일로 상대 링크를 단다. ID는 기계가 구분할 때 쓴다. 번호처럼 순서를 뜻하지 않으므로, 순서가 필요한 곳(계획의 Sequence, 스펙의 계획 분할)은 링크와 조건으로 적는다.
- **타입 표:** `docs/README.md`의 `번호` 열을 없애고, 모든 타입이 ID를 갖는다고 적는다. `DOC_TYPES_HEADER`와 파서도 함께 바꾼다.

### 3.2 도구와 검사

- `make new-id`: 새 ID 하나를 출력한다. 초안을 Basic Memory에 만들 때 쓴다.
- `make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]`: `ID`가 있으면 그 ID로, 없으면 새 ID로 저장소 문서를 만든다. 템플릿의 `{{number}}`는 `{{id}}`로 바꾼다. `ID`가 형식에 맞지 않거나 이미 쓰인 ID면 실패한다. `next_doc_number`는 지운다.
- `tests/repo-docs.bats`: 번호 중복 검사를 "모든 문서의 `id`가 이름의 ID와 같고 저장소 안에서 유일하다"로 바꾼다. `ALLOWED_KEYS`에 `id`를 더한다.
- `scripts/check-git.sh`, `scripts/lib/git.sh`, `scripts/check-pr.sh`: 브랜치와 `Plan` 트레일러가 ID를 받게 한다.
  - **내 결정:** 이 개편의 브랜치와 커밋은 옛 형식(`plan/26-…`, `Plan: 26`)으로 시작하므로, 개편 PR 안에서는 두 형식을 모두 받는다. `check-git`은 `BASE..BRANCH`의 커밋만 보므로, 옛 형식 거부는 이력 재작성 여부와 상관없이 개편 PR이 병합된 뒤의 결과 PR(Task 5)에서 넣는다.
- **내 결정:** 열린 PR까지 보는 CI 중복 검사는 두지 않는다. 무작위 ID는 할당을 직렬화할 필요가 없고, 충돌 확률이 낮으며, 병합 뒤에는 `make check`의 유일성 검사가 잡는다.

### 3.3 초안 보드 (Basic Memory)

- **경로:** `agent-drafts/<프로젝트 키>/<코드>-<ID>-<slug>`이고 노트 제목도 같다. 프로젝트 키는 [에이전트 기억 미러 설계](spec-2026-10-22-agent-memory-mirror.md) §3.2와 같은 규칙(`origin` 주소에서 만든 `<owner>-<repo>`, 이 저장소는 `yanghs6-basic-memory-tailnet`)이다. 프로젝트는 `main`이다.
  - **내 결정:** 이 개편은 기억 미러(계획 24)보다 먼저라서 그 계획의 helper(`scripts/lib/agent-memory.sh`)와 `BM_MEMORY_DEVICE`를 쓸 수 없다. `doc-authoring` 스킬이 두 값을 얻는 명령을 적는다. 프로젝트 키는 `git remote get-url origin`을 그 규칙대로 정규화한 값이다. 기기 이름은 `BM_MEMORY_DEVICE`가 있으면 그 값, 없으면 `hostname -s`를 소문자로 바꾼 값이다. 계획 24가 helper를 만들면 스킬이 그것을 쓰게 바꾼다.
- **frontmatter(`write_note`의 `metadata`):**

| 키 | 값 |
|---|---|
| `draft` | `true` (목록 조회용) |
| `project` | 프로젝트 키 |
| `id`, `type`, `slug` | 저장소 문서가 받을 값과 같다 |
| `status` | `drafting`, `review`, `approved`, `dropped` |
| `owner` | `<기기>/<에이전트>` (예: `mac-work/claude-code`). 기기 이름은 기억 미러의 기기 이름을 쓴다 |
| `branch` | 연결된 브랜치. 없으면 빈 값 |
| `areas` | 건드릴 저장소 경로나 디렉터리 목록 |
| `updated` | ISO 날짜. 고칠 때마다 바꾼다 |
| `repo_path`, `pr` | 승인 뒤 저장소 경로와 PR 번호 |

- **흐름:**
  1. 스펙·계획·ADR을 쓰거나 기존 문서를 크게 바꾸기 전에, `search_notes(metadata_filters={"project": <키>, "draft": true})`로 보드를 보고 `areas`와 slug가 겹치는 초안이 있으면 사용자에게 알린다.
  2. `make new-id`로 ID를 받고, `write_note`(overwrite 없이)로 초안 노트를 만든다. 본문은 그 타입의 템플릿에서 시작한다.
  3. 사용자는 SilverBullet에서 읽는다. 승인은 지금처럼 대화로 한다.
  4. 승인되면 `make new-doc TYPE=… SLUG=… ID=<같은 ID>`로 저장소 문서를 만들고 본문을 옮긴 뒤 `make check`, 커밋, push, draft PR을 연다. 노트에 `status: approved`, `repo_path`, `pr`을 적는다. 이후의 정본은 저장소 문서다.
  5. 진행 중인 기존 문서 변경(계획 실행 브랜치 밖에서 하는 수정)은 `type: change`, `areas`, 바꿀 내용 요약을 담은 노트로 올린다.
- **쓰기 규칙:**
  - 초안 하나는 주인(`owner`)만 쓴다. 다른 에이전트는 읽기만 하고, 겹침은 사용자에게 알린다.
  - 주인은 고치기 전에 `read_note`로 다시 읽는다. 사용자가 SilverBullet에서 고쳤을 수 있으므로, 그 내용을 합친 뒤 `overwrite`로 쓴다.
  - 만료 기본값은 두지 않는다(사용자 결정 9). 오래 손대지 않은 초안은 `updated`를 보고 사용자에게 알린다. 노트를 지우는 것은 사용자 승인 뒤에만 한다.
- **터널이 꺼져 있을 때:** 사용자에게 `make tunnel`을 요청하고 기다린다. 로컬 파일로 초안을 대신 쓰지 않는다. 정본을 둘로 만들지 않기 위해서다.
- **번호와의 관계:** 초안 보드는 발견만 맡는다. ID의 유일성은 §3.1과 §3.2가 지키므로, 터널이 끊겨도 문서 이름은 꼬이지 않는다.

### 3.4 기존 문서 소급 적용 (이름 변경)

- 기존 타입 문서 62개 전부에 ID를 하나씩 정한다. 이 스펙과 ADR 0009도 포함한다. `git mv`로 새 이름으로 바꾸고, front matter에 `id`를 더한다.
  - 리뷰 기록(`docs/reviews/`)도 바꾼다. slug의 `plan-NN-` 접두어는 뺀다.
- **바꿀 인용:**
  - 문서 상대 링크, 백틱 경로, front matter 경로(`spec`, `amended-by`, `superseded-by`)
  - 본문의 "계획 NN"·"ADR NNNN"·`Plan: NN`·`plan/NN-…`
  - 계획 제목의 `# NN …`, ADR 제목의 `# ADR NNNN:`, Sequence 줄
  - 스킬·`AGENTS.md`·스크립트 메시지·테스트·워크플로 주석의 경로와 번호
  - 사람이 읽는 인용은 "<slug> 계획", "<slug> ADR" 형태로 바꾸고, 같은 문장에 링크가 없으면 링크를 단다.
- **바꾸지 않는 것:** §2의 번호 아닌 숫자(개수, 분수, 연도, 결정 N, Task N, 리뷰 ID, PR 번호)
  - **내 결정:** 자동 치환은 대응표에 있는 정확한 패턴만 바꾼다. 남은 후보는 grep 목록으로 사람이 확인한다. 옛 번호가 바뀌었던 계획 02~05는 이름을 바꾸기 전에 당시 번호를 확인한다.
- **증거 문장:** 완료된 계획의 Progress log와 리뷰 기록에 든 브랜치 이름·트레일러·경로도 바꾼다. 증거를 고쳐 쓰지 않는다는 규칙(`doc-authoring`)의 일회성 예외로, ADR 0009에 근거를 남긴다. SHA는 §3.5에서 따로 다룬다.
- **대응표:** ADR 0009 부록에 옛 이름, 옛 번호, 새 ID, 새 이름을 적는다.
  - **내 결정:** 옛 이름은 이력 재작성의 텍스트 치환(§3.5)에 걸리지 않는 형태로 적는다. 예: 확장자와 경로를 빼고 날짜·번호·slug를 띄어 쓴다. 그래야 재작성 뒤에도 대응표가 남는다.
- **에이전트 메모리(저장소 밖):** 사용자 메모리의 색인에 대응표 위치를 한 줄 더한다. 메모리 본문의 옛 번호는 고치지 않는다(사용자 결정 4).

### 3.5 git 이력 재작성

- **조건(모두 만족할 때만):**
  - §3.1~§3.4가 `main`에 병합됐다.
  - 열린 PR이 없다.
  - 다른 세션의 병합 안 된 브랜치와 worktree가 없다(감독 세션이 확인).
  - 사용자가 `main` 룰셋의 Enforcement를 잠시 끈다(GitHub 런북 "긴급 변경").
  - 하나라도 안 되면 재작성하지 않고 대응표로 끝낸다(사용자 결정 5).
- **범위(사용자 결정 10, 바꿀 수 있는 것은 모두):**
  - 경로: HEAD 문서의 모든 옛 경로(세 세대, 하위 폴더 시절)와 HEAD에서 지워진 문서의 경로. 지워진 문서도 ID를 받고 대응표에 "삭제됨"으로 들어간다. ADR 번호 0001을 함께 쓴 두 문서는 서로 다른 ID를 받는다.
  - 파일 내용: 모든 커밋의 문서·스킬·스크립트·테스트에 §3.4와 같은 치환을 한다(경로, 링크, "계획 NN"·"ADR NNNN"·`Plan: NN`·`plan/NN-…`, 제목).
  - 커밋 메시지: 제목, 본문, 트레일러에 같은 치환을 한다.
  - SHA 인용: 파일 내용과 커밋 메시지에 든 `main` 안의 앞선 커밋 SHA(7자리 이상)를 새 SHA로 바꾼다. 인용은 앞선 커밋만 가리키므로, 커밋을 순서대로 다시 만들면 바꿀 때 새 SHA를 이미 안다.
  - GitHub: PR #1~#20의 제목과 본문, 머신 계정이 쓴 코멘트 87개에 같은 치환을 한다(`gh pr edit`, `gh api`).
- **시대별 대응:** 계획 02~05는 이력 중간에 번호가 바뀌었다(§2). 번호 치환은 그 커밋 시점의 번호를 기준으로 하고, 번호를 바꾼 커밋 전후로 대응을 나눈다.
- **바꿀 수 없어 남는 것:** PR 참조(`refs/pull/*`)와 그 커밋, `main`에 없는 커밋(PR 브랜치의 중간 커밋)을 가리키는 SHA 인용, GitGuardian 봇 코멘트 3개, GitHub 밖의 사본(대화, 에이전트 메모리, 캐시).
- **도구:** 일회용 재작성 스크립트가 `main`을 첫 커밋부터 위상 순서대로 다시 만든다.
  - 커밋마다 원래 tree를 읽고, 경로와 내용을 바꾼 새 tree를 만든다(`git mktree`, `git hash-object -w`).
  - 원래 저자·커미터·날짜를 그대로 둔 채 `git commit-tree`로 새 커밋을 만들고, 옛 SHA → 새 SHA 대응을 쌓는다. merge 커밋 12개는 두 부모를 모두 새 SHA로 바꿔 유지한다.
  - 같은 blob은 한 번만 변환한다.
  - **내 결정:** `git filter-repo`는 fast-import가 끝나야 새 SHA가 정해지므로 재작성 도중에 SHA 인용을 바꿀 수 없다. 그래서 쓰지 않는다.
  - **내 결정:** 스크립트는 한 번 쓰고 버리므로 저장소에 넣지 않는다. 대신 계획의 Progress log에 실행 명령, 대응표 생성 방법, 검증 결과를 남긴다.
- **누가 하는가:** `AGENTS.md`는 에이전트의 force-push와 이력 재작성을 금지한다. 사용자는 2026-10-26에 이 개편의 재작성과 force-push를 에이전트가 직접 하도록 이번 한 번만 허가했고, `AGENTS.md`는 고치지 않는다(사용자 결정 8).
  - 에이전트는 저장소 clone이 아닌 별도 `--mirror` clone에서 재작성과 검증을 하고, 그 clone에서 push한다.
  - Enforcement 끄기와 켜기는 Task 4에서 단계마다 사용자 OK를 받고 한다. 머신 계정에 룰셋을 바꿀 권한이 없으면 사용자가 GitHub 설정에서 바꾼다.
  - 이 허가는 이 재작성 한 번에만 쓴다. 다른 작업의 force-push 근거가 되지 않는다.
- **절차:**
  1. 새 `--mirror` clone을 두 개 만든다. 하나는 되돌리기용으로 손대지 않고 보관한다.
  2. 작업용 clone에서 재작성 스크립트를 실행한다. 치환 규칙은 §3.4에서 HEAD에 쓴 규칙과 ADR 0009 대응표를 그대로 쓰고, 시대별 대응을 더한다.
  3. 검증:
     - 커밋 수, 각 커밋의 저자·커미터·날짜, merge 구조가 원래와 같다.
     - 어느 커밋의 tree에도 대응표의 옛 경로가 없다.
     - 커밋 메시지와 파일 내용에서 옛 번호 패턴 grep이 대응표 부록 밖에서 0건이다. 남은 후보 목록은 사람이 확인한다.
     - 재작성 전후 HEAD tree의 차이가 SHA 인용 치환뿐이다. 스크립트가 바뀐 줄마다 다른 부분이 대응표의 SHA 쌍뿐인지 확인한다.
     - 임의로 고른 옛 커밋 몇 개에서, 새 커밋 diff가 경로·번호·SHA 치환 말고는 원래 diff와 같다.
  4. 검증 결과를 사용자에게 보이고 OK를 받는다. Enforcement를 끄고, 재작성한 clone에서 `main`에 force-push하고, Enforcement를 다시 켠다. 런북 4절의 확인 명령으로 규칙 5개가 다시 보이는지 확인한다.
  5. 다른 clone을 맞춘다.
     - main checkout에서 `git fetch origin && git reset --hard origin/main`을 실행한다. `.env`와 `backups/`는 git이 무시하는 파일이라 남는다.
     - 다른 Mac도 같은 명령을 실행한다.
     - worktree는 그 전에 모두 지운다.
  6. force-push 뒤 PR #1~#20의 제목·본문과 머신 계정 코멘트를 같은 치환 규칙으로 고친다. 코멘트의 base·head SHA는 `main`에 있는 커밋일 때만 새 SHA로 바꾼다.
- **비밀값 제거가 아니다:** 공개 저장소라 옛 커밋은 PR 참조로 계속 접근할 수 있다.
- **옛 형식 거부:** Task 5의 결과 PR에서 §3.2의 전환용 옛 형식 허용을 지운다. 재작성을 하지 않아도 이 단계는 한다.

### 3.6 규칙과 스킬

- `AGENTS.md`의 Git 절(`plan/<NN>-<slug>`, `Plan: <NN|none>`)과 Notes 절(`make new-doc`)을 바꾸고, 초안 보드 한 줄을 더한다: "Pre-approval drafts of specs, plans and ADRs live on the Basic Memory draft board (`doc-authoring`), not in the repo." (영어, 사용자 승인 대상)
- `doc-authoring` 스킬: 초안 흐름(§3.3), `make new-id`, `ID=`, 번호 관련 Gotcha를 ID 기준으로 바꾼다.
- `git-workflow` 스킬과 `references/review-and-merge.md`, `branch-review` 스킬, `.claude/agents/branch-reviewer.md`, PR 템플릿, `scripts/review-branch.sh`의 프롬프트와 사용법 줄을 ID로 바꾼다.
- 템플릿: `plan.md`(`# {{id}} …`, `Plan: {{id}}`, `plan/{{id}}-{{slug}}`), `adr.md`(`# ADR {{id}}: …`), `spec.md`(구현 계획 줄), 나머지 템플릿에 front matter `id: {{id}}`를 더한다.

## 4. 보안

- 승인 전 초안은 공개 저장소에 들어가지 않고 Basic Memory에만 있다. Basic Memory에는 앱 인증이 없어서 보호막은 네트워크 경계다(ssh 터널, tailnet, 웹 커넥터를 켜면 GitHub 한 명 OAuth). 초안에 비밀값을 쓰지 않는다는 규칙은 지금과 같다.
- 승인된 문서는 지금처럼 공개된다. 공개 텍스트 검사(계획 18)는 저장소에 들어오는 문서에만 적용된다.
- 이력 재작성은 force-push다.
  - 되돌리기용 `--mirror` clone을 보관하고, 사용자 OK 뒤에만 push한다.
  - 공개 저장소라 옛 커밋은 PR 참조로 계속 접근할 수 있다. 그래서 이 재작성으로 공개된 내용을 회수할 수는 없다.
  - 룰셋을 끄는 동안 다른 push가 없도록 다른 세션을 멈춘다.
- ID 생성은 보안 용도가 아니다. 추측돼도 위험하지 않다.

## 5. 테스트와 검증

- bats(먼저 쓴다):
  - `tests/lib-docs.bats`: `new_doc_id`가 형식에 맞는 ID를 내고, 이미 쓰인 ID를 피한다(스텁으로 첫 값을 충돌시킴).
  - `tests/create-doc.bats`: `ID=` 재사용, 잘못된 형식·중복 ID 거부, 템플릿의 `{{id}}` 채움. 번호 테스트(`:48-83`)는 이 동작으로 바꾼다. 인터페이스가 바뀌는 경우라 커밋 본문에 이유를 적는다.
  - `tests/repo-docs.bats`: 이름의 ID와 front matter `id`가 같고 유일하다. 둘이 다르거나 같은 ID가 두 파일에 있으면 실패한다.
  - `tests/check-git.bats`, `tests/check-pr.bats`, `tests/lib-git.bats`, `tests/review-branch.bats`, `tests/post-review.bats`, `tests/helpers.bash`: ID 형식을 받는다. 전환 기간에는 옛 형식도 받고, §3.5 뒤의 커밋에서는 옛 형식을 거부한다.
  - `tests/repo-cloud-neutral.bats`: 새 런북 이름.
- 이름 변경 검증: `make check`. 대응표의 옛 번호 패턴을 grep해 대응표 밖에서 0건임을 계획의 Progress log에 남긴다. 범위 밖 경로(워크플로 주석, `Makefile`, 코드 블록)도 같은 grep으로 확인한다.
- 이력 재작성 검증: §3.5 3단계의 검증 다섯 가지와 6단계의 PR 수정 결과를 명령과 결과로 Progress log에 남긴다.
- 초안 보드: 완료 조건 7을 사람이 한 번 확인한다(다른 기기나 Codex에서 `search_notes`).

## 6. 위험과 대응

| 위험 | 대응 |
|---|---|
| 자동 치환이 번호 아닌 숫자를 바꿈 | 대응표의 정확한 패턴만 바꾸고, 남은 후보는 사람이 확인한다(§3.4). 리뷰에서 diff를 본다 |
| 이름 변경 PR이 열려 있는 동안 다른 브랜치가 옛 경로를 고쳐 충돌 | 감독 세션이 이름 변경 PR의 병합 시점을 다른 세션에 알리고, 그 전에 병합할 PR을 정리한다. 나중 브랜치는 `git merge origin/main` 뒤 옛 경로를 새 경로로 바꾼다 |
| 재작성 중 다른 push가 들어옴 | 룰셋을 끄기 전에 다른 세션을 멈추고, push 직전 `git ls-remote`로 `main`이 재작성 기준 SHA와 같은지 본다 |
| 재작성 결과가 틀림 | push 전 검증 다섯 가지. push 뒤 문제가 나면 보관한 `--mirror` clone을 사용자 OK 뒤 다시 force-push한다 |
| 과거 커밋의 번호를 지금 번호로 잘못 바꿈(번호가 바뀐 계획 02~05) | 시대별 대응(§3.5). 번호를 바꾼 커밋 전후의 커밋을 골라 diff를 사람이 확인한다 |
| 재작성 스크립트의 결함(merge 부모, 실행 권한, 심볼릭 링크, 빈 커밋) | 원래 tree의 파일 모드와 링크를 그대로 옮기고, 검증 단계에서 커밋 수와 merge 구조를 비교한다. 먼저 보관용이 아닌 시험 clone에서 한 번 돌려 본다 |
| PR 코멘트 수정이 리뷰 기록의 뜻을 바꿈 | 치환 규칙(경로, 번호, `main`의 SHA)만 적용한다. 코멘트마다 치환 건수를 Progress log에 남긴다 |
| 다른 Mac의 clone이 옛 이력 위에서 작업 | 재작성 공지를 Basic Memory 초안 보드와 사용자에게 남기고, 그 Mac에서 `fetch` + `reset --hard` 전에는 작업하지 않는다 |
| 터널이 자주 꺼져 초안 보드를 못 씀 | 사용자에게 `make tunnel`을 요청한다. 잦으면 비공개 동반 저장소(조사 노트의 E)로 다시 정한다 |
| Basic Memory 동시 쓰기 동작 미확인 | 초안 하나에 주인 하나, 고치기 전 다시 읽기(§3.3) |

## 7. 계획 분할

| 계획 | 범위 | 시작 조건 |
|---|---|---|
| doc-ids (지금 체계로 26) | Task 1: ID 도구와 검사(§3.1, §3.2). Task 2: 기존 문서 이름 변경과 인용 갱신, 대응표, ADR 0009 accepted(§3.4). Task 3: 규칙·스킬·템플릿과 초안 보드 흐름(§3.3, §3.6), 완료 조건 7 확인. Task 4: 이력 재작성과 PR #1~#20 수정(§3.5, 사용자와 함께, 단계마다 OK). Task 5: 옛 형식 거부와 결과 기록(결과 PR) | 이 스펙의 승인. Task 2는 감독 세션이 다른 세션의 병합 순서를 정한 뒤. Task 4는 §3.5의 조건 |

- Task 1~3은 하나의 PR이다. Task 4는 그 PR이 병합된 뒤 하고, Task 5는 재작성 뒤 첫 PR이다.
- 계획 24를 맡은 세션과 정할 일:
  - 그 계획의 문서 이름과 브랜치도 이 개편으로 바뀐다.
  - 색인 hook이 초안 보드를 보여 줄지는 범위 밖 후속이다.
  - `agent-drafts/` 폴더는 이 스펙이 쓴다.

## 8. Open questions

1. 이력 재작성 날짜. 그날 다른 세션을 멈춘다. Task 4 직전에 정한다.
