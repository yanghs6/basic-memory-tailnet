# 08 GitHub Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이 저장소의 작업 흐름을 공개 GitHub 저장소 `yanghs6/basic-memory-tailnet`의 PR 흐름으로 바꾼다. 흐름은 머신 계정의 초안 PR, CI(`check`, `pr-rules`), 사람의 승인과 squash 병합이다. 이 계획의 PR이 GitHub의 첫 PR이고, 병합 뒤 사람이 저장소 설정과 ruleset을 적용한다.

**Architecture:**
- `scripts/check-pr.sh`(새 파일)는 PR 제목과 본문 마지막 문단의 트레일러를 검사한다. 입력은 환경변수로만 받는다.
- 워크플로는 둘이다.
  - `ci.yml`: `make check`
  - `pr-rules.yml`: `check-git.sh`와 `check-pr.sh`. `edited` 이벤트에도 다시 돈다.
- ruleset 내용은 `.github/rulesets/main.json`으로 저장소에 남긴다. `tests/github.bats`가 다음을 검사한다.
  - ruleset의 핵심 조건: 승인 1개, squash만 허용, 우회 없음
  - 필수 체크 이름과 워크플로 잡 이름의 일치
  - 워크플로의 보안 규칙: 읽기 전용 권한, SHA 고정, `run:` 줄에 식 금지
- `make check-git`과 `make review`의 base 기본값을 `origin/main`으로 바꾼다. 스크립트 기본값은 그대로 둔다.
- 문서도 새 흐름으로 바꾼다: `AGENTS.md`의 Git과 Safety, git-workflow 스킬, GitHub 런북, 계정 런북, ARCHITECTURE, README, 기존 정책 스펙의 상태 줄.

**Tech Stack:** bash 3.2 호환 셸, bats-core 1.14.0 + bats-assert, jq(테스트 이미지), GitHub Actions(`ubuntu-24.04`, `actions/checkout` v6.1.0 = `d23441a48e516b6c34aea4fa41551a30e30af803`), GitHub REST API(ruleset, 저장소 설정), `gh` CLI

**Spec:** `docs/specs/2026-10-13-github-pr-workflow-design.md` (특히 3·5·6·7·9·10·11절)

**Sequence:** 계획 8. 다음 전제를 모두 만족한 뒤 시작한다.
- 스펙과 이 계획을 담은 `work/workflow-alignment`가 `main`에 병합됐다.
- 계획 06이 병합됐다(`c10fb5c`, 충족).
- 아래 "전제: 사람 작업" 1~3이 끝났다.

## Global Constraints

- 스펙 결정: 머신 계정이 PR을 열고, 사람만 승인·병합한다. 병합 방식은 squash 하나다. PR 하나는 계획 하나다.
- AGENTS.md: 스크립트는 `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`을 두고, `scripts/lib/common.sh`를 source하고, 실패는 `die`로 알린다. macOS bash 3.2에서 돌아야 한다.
- 테스트를 먼저 쓴다(RED 확인 후 GREEN). ADR 0004를 따른다. 대표 성공 경로 1개, 조용히 넘어갈 실패 경로, 정책 검사만 쓰고, 문구만 보는 테스트는 쓰지 않는다. 입력값만 다르면 반복문 하나로 묶는다.
- "never weaken a test to make it pass." 기존 테스트의 assertion을 지우거나 약하게 바꾸지 않는다.
- 외부 Action은 전체 커밋 SHA로 고정한다. 워크플로 권한은 `contents: read`만 준다. `pull_request_target`은 쓰지 않는다. `${{ }}`는 `run:` 줄에 넣지 않고 `env:`로 넘긴다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 08`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`는 쓰지 않는다.
- PR 제목은 `<type>: <description>`이고, PR 본문 마지막 문단은 `Assisted-by`와 `Plan: 08`이다.
- VM의 외부 IP와 Tailscale IP를 커밋, PR, 코멘트, 문서 어디에도 적지 않는다.
- 사람은 GitHub의 "Update branch"를 누르지 않는다. 브랜치 갱신은 에이전트가 `git merge origin/main`으로 한다(스펙 9절).
- worktree에 `.env`나 `backups/`를 만들거나 복사하지 않는다.
- 쓰기 대상: 아래 File Structure에 있는 파일만 바꾼다.

## Review Focus

1. **GitHub이 PR 본문을 CRLF 줄끝으로 넘긴다.** `git interpret-trailers`가 트레일러를 못 찾으면 올바른 PR이 실패한다. → Task 1 Step 1의 성공 테스트에 CRLF 본문을 넣었다.
2. **트레일러 뒤에 문단이 더 붙은 PR 본문.** 예: 맺음말, 남겨 둔 템플릿 문구. squash 커밋의 마지막 문단이 트레일러가 아니게 된다. → Task 1 Step 1의 "missing or not in the last paragraph" 테스트가 실패로 잡는다.
3. **워크플로 잡 이름을 바꿔서 ruleset의 필수 체크와 어긋남.** 그러면 어떤 PR도 병합할 수 없다. → Task 2의 `tests/github.bats`가 두 목록이 같은지 검사한다.
4. **CI 러너의 `make check`가 로컬과 다르게 동작함.** Docker, kcov, git 소유권, 얕은 clone이 원인일 수 있다. → Task 4 Step 1에서 첫 PR의 `check` 결과를 확인하고 실패 로그로 고친다.
5. **머신 계정 토큰으로 같은 이름의 커밋 상태를 만들어 필수 체크를 통과시킴.** → ruleset의 `integration_id`를 GitHub Actions 앱으로 고정했다. Task 4 Step 3에서 첫 PR의 check-run으로 앱 ID를 확인한 뒤 적용한다.

## File Structure

```
scripts/check-pr.sh (새 파일)  tests/check_pr.bats (새 파일)                                   Task 1
.github/workflows/ci.yml  .github/workflows/pr-rules.yml  .github/rulesets/main.json
.github/pull_request_template.md  tests/github.bats (새 파일)  Makefile  scripts/review.sh(로그 한 줄)   Task 2
AGENTS.md  .agents/skills/git-workflow/SKILL.md  .agents/skills/git-workflow/references/review-and-merge.md
docs/runbooks/github.md (새 파일)  docs/runbooks/accounts.md  docs/ARCHITECTURE.md  README.md
docs/specs/2026-10-07-git-review-policy-design.md(상태 줄)                                       Task 3
이 계획 파일(Progress log), 필요하면 .github/rulesets/main.json                                  Task 4, 마무리
```

---

### 전제: 사람 작업 (계획 시작 전, 스펙 10절 1~2단계)

사용자가 자기 터미널에서 한다. `gh auth login`은 대화형이라 Claude Code의 `!`에서는 입력을 받지 못하므로, 별도 터미널 앱에서 실행한다. 에이전트는 명령을 안내하고 결과만 확인한다. 이 절차는 Task 3에서 `docs/runbooks/github.md`로 옮긴다.

- [ ] **1. 머신 계정**
  1. 새 이메일로 GitHub 계정(예: `yanghs6-bot`)을 만들고 2FA를 켠다. 약관상 사람이 직접 만들어야 한다.
  2. 개인 계정으로 그 계정을 이 저장소의 협업자로 초대한다(Settings → Collaborators, 권한 Write).
  3. 머신 계정으로 로그인해 초대를 수락한다.
  4. 머신 계정에서 classic 토큰을 만든다. 경로는 Settings → Developer settings → Personal access tokens (classic)이고, 범위는 `public_repo`와 `workflow`, 만료는 90일이다.
- [ ] **2. 이 Mac에 토큰 등록 (토큰은 채팅·파일·명령 인자·파이프에 넣지 않는다)**

```bash
gh auth login            # GitHub.com → HTTPS → Paste an authentication token → 숨김 프롬프트에 토큰 붙여넣기
gh auth status           # Logged in to github.com account <머신 계정>
cd <main 체크아웃>
git config --local credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!gh auth git-credential'
```

Expected: `gh auth status`에 머신 계정이 보인다. credential 설정은 이 저장소에만 적용되므로, 다른 GitHub 저장소의 인증은 그대로다. 단, 기본 `gh` 설정은 이제 머신 계정이다. 사용자가 개인 계정으로 `gh`를 쓸 때는 `GH_CONFIG_DIR="$HOME/.config/gh-yanghs6"`를 붙인다(스펙 3절).

- [ ] **3. 공개 전 점검과 첫 push (main 체크아웃에서)**

```bash
git log -p main | grep -nE 'tskey-[A-Za-z0-9]{10,}|PRIVATE KEY|([0-9]{1,3}\.){3}[0-9]{1,3}|[a-z0-9-]+\.ts\.net|@[A-Za-z0-9.-]+\.[a-z]{2,}'
git log -p main | grep -cF '<실제 VM 외부 IP>'
git log -p main | grep -cF '<실제 VM Tailscale IP>'
git log -p main | grep -cF '<GCP 프로젝트 ID>'
```

Expected:
- 첫 명령에 걸린 줄은 모두 테스트용 자리표시자다. 예: `127.0.0.1`, `203.0.113.10`, `tail1234.ts.net`, `agent@example.com`, `tskey-auth-test123`.
- 나머지 세 명령은 모두 `0`이다.
- 하나라도 실제 값이면 push하지 않고 스펙 11절대로 사용자가 결정한다.

```bash
git remote add origin https://github.com/yanghs6/basic-memory-tailnet.git
git fetch origin
git merge --allow-unrelated-histories origin/main -m "Merge the GitHub repository's initial commit"
git push -u origin main
```

Expected: 원격 `main`에 로컬 이력 전체와 원격의 `LICENSE` 커밋이 함께 있다. force push는 쓰지 않는다. 이 시점에는 아직 ruleset이 없어서 직접 push가 된다.

### 시작: 브랜치, worktree, 초안 PR (에이전트)

- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/08-github-switch` 브랜치를 만든다. 방법은 git-workflow 스킬을 따른다.
- [ ] 첫 커밋으로 이 계획 파일을 `docs/plans/backlog/`에서 `docs/plans/active/`로 옮긴다.

```bash
git mv docs/plans/backlog/2026-10-13-08-github-switch.md docs/plans/active/2026-10-13-08-github-switch.md
git commit -m "docs: start plan 08 GitHub switch" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 08" --trailer "Task: none"
git push -u origin plan/08-github-switch
```

- [ ] 초안 PR을 연다. 이 시점에는 PR 템플릿과 CI가 아직 없으므로 본문은 직접 쓴다.

```bash
cat >"$TMPDIR/pr-08.md" <<'EOF'
Switch the repository to the GitHub pull-request workflow (plan 08).

Plan file docs/plans/active/2026-10-13-08-github-switch.md, spec docs/specs/2026-10-13-github-pr-workflow-design.md.

Assisted-by: <tool> <model>
Plan: 08
EOF
gh pr create --draft --base main --head plan/08-github-switch --title "ci: switch to the GitHub pull-request workflow" --body-file "$TMPDIR/pr-08.md"
```

Expected: `gh pr create`가 PR URL을 출력한다. PR 작성자는 머신 계정이다. 번호를 Progress log에 적는다.

---

### Task 1: PR 제목·트레일러 검사 (`check-pr.sh`)

**Files:**
- Create: `scripts/check-pr.sh`(실행 권한), `tests/check_pr.bats`

**Interfaces:**
- Produces: `scripts/check-pr.sh`
  - 입력: 환경변수 `PR_TITLE`, `PR_BODY`
  - 통과하면 exit 0, stderr에 `OK: PR title and trailers`
  - 실패하면 exit 1, stderr에 `PR rule violations:`와 문제 목록
  - Task 2의 `pr-rules.yml`이 이 스크립트를 실행한다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/check_pr.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  CHECK="$REPO_DIR/scripts/check-pr.sh"
  GOOD_BODY="Summary of the change.

Assisted-by: claude-code claude-opus-5-5
Plan: 08"
}

@test "passes a conventional title and a body ending in the trailers, also with GitHub CRLF line ends" {
  PR_TITLE="feat: add the pull request rules" PR_BODY="$GOOD_BODY" run "$CHECK"
  assert_success
  assert_output --partial "OK: PR title and trailers"
  local crlf_body
  crlf_body="$(printf 'Summary.\r\n\r\nAssisted-by: claude-code claude-opus-5-5\r\nAssisted-by: codex gpt-6.1-sol\r\nPlan: none\r\n')"
  PR_TITLE="docs: two tools worked here" PR_BODY="$crlf_body" run "$CHECK"
  assert_success
}

@test "rejects titles that are not '<type>: <description>'" {
  local title
  for title in "Add rules" "Feat: add rules" "feature: add rules" "feat:add rules" "feat(ci): add rules"; do
    PR_TITLE="$title" PR_BODY="$GOOD_BODY" run "$CHECK"
    [[ "$status" -eq 1 ]] || fail "expected title '$title' to be rejected; got $status: $output"
    assert_output --partial "title '$title' must be '<type>: <description>'"
  done
}

@test "fails when the trailers are missing or not in the last paragraph" {
  local body
  for body in "" "Summary only." "$GOOD_BODY

Thanks for reviewing."; do
    PR_TITLE="feat: x" PR_BODY="$body" run "$CHECK"
    [[ "$status" -eq 1 ]] || fail "expected the body to be rejected; got $status: $output"
    assert_output --partial "missing trailer 'Assisted-by:"
    assert_output --partial "missing trailer 'Plan:"
  done
}

@test "rejects malformed trailer values, including a second Plan line" {
  PR_TITLE="feat: x" PR_BODY="Summary.

Assisted-by: Claude
Plan: 8" run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Assisted-by: Claude' must be"
  assert_output --partial "trailer 'Plan: 8' must be"
  PR_TITLE="feat: x" PR_BODY="$GOOD_BODY
Plan: 09" run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Plan: 08,09' must be"
}

@test "rejects Co-authored-by and Signed-off-by in the body because the squash commit would carry them" {
  PR_TITLE="feat: x" PR_BODY="$GOOD_BODY
Co-authored-by: Bot <bot@example.com>
Signed-off-by: Bot <bot@example.com>" run "$CHECK"
  assert_failure
  assert_output --partial "must not carry 'Co-authored-by'"
  assert_output --partial "must not carry 'Signed-off-by'"
}

@test "fails instead of passing when CI does not pass the title" {
  PR_BODY="$GOOD_BODY" run "$CHECK"
  assert_failure
  assert_output --partial "PR_TITLE is empty"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `check_pr.bats` 6개가 `scripts/check-pr.sh: No such file or directory`로 실패한다. 다른 테스트는 PASS한다.

- [ ] **Step 3: `scripts/check-pr.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Check a pull request's title and body (docs/specs/2026-10-13-github-pr-workflow-design.md, sections 5 and 6).
# The squash merge makes the title the commit subject and the body the commit message, so the title follows
# the commit format and the body's last paragraph carries the Assisted-by and Plan trailers.
# Usage: PR_TITLE=<title> PR_BODY=<body> check-pr.sh   (the pr-rules workflow passes both from the event)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly TITLE_PATTERN='^(feat|fix|refactor|docs|test|chore|perf|ci): [^ ]'
readonly ASSISTED_BY_PATTERN='^(claude-code|codex|antigravity|gemini-cli) [^ ]+$'
readonly PLAN_PATTERN='^([0-9]{2}|none)$'
readonly FORBIDDEN_TRAILERS="Co-authored-by Signed-off-by"

PROBLEMS=""

add_problem() {
  PROBLEMS="${PROBLEMS}  - $*
"
}

# trailer_values KEY TRAILERS -> the values of KEY (matched case-insensitively, like git), one per line.
trailer_values() {
  awk -v key="$1" 'BEGIN { key = tolower(key) }
    { i = index($0, ":"); if (i && tolower(substr($0, 1, i - 1)) == key) { v = substr($0, i + 1); sub(/^ +/, "", v); print v } }' <<<"$2"
}

check_assisted_by() {
  local value count=0
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    count=$((count + 1))
    [[ "$value" =~ $ASSISTED_BY_PATTERN ]] \
      || add_problem "trailer 'Assisted-by: $value' must be 'Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>'"
  done <<<"$(trailer_values Assisted-by "$1")"
  ((count > 0)) || add_problem "missing trailer 'Assisted-by: <tool> <model>' in the last paragraph of the PR body"
}

check_plan() {
  local value
  value="$(trailer_values Plan "$1" | tr '\n' ',' | sed 's/,$//')"
  if [[ -z "$value" ]]; then
    add_problem "missing trailer 'Plan: <NN|none>' in the last paragraph of the PR body"
  elif [[ ! "$value" =~ $PLAN_PATTERN ]]; then
    add_problem "trailer 'Plan: $value' must be 'Plan: <NN|none>'"
  fi
}

main() {
  local title="${PR_TITLE:-}" trailers key
  require_cmd git
  [[ -n "$title" ]] || die "PR_TITLE is empty: pass the pull request title and body in PR_TITLE and PR_BODY"
  # GitHub sends PR bodies with CRLF line ends, which git interpret-trailers does not parse.
  trailers="$(printf '%s\n' "${PR_BODY:-}" | tr -d '\r' | git interpret-trailers --parse)" \
    || die "git interpret-trailers could not parse the PR body"
  [[ "$title" =~ $TITLE_PATTERN ]] \
    || add_problem "title '$title' must be '<type>: <description>' with type feat, fix, refactor, docs, test, chore, perf or ci"
  check_assisted_by "$trailers"
  check_plan "$trailers"
  for key in $FORBIDDEN_TRAILERS; do
    [[ -z "$(trailer_values "$key" "$trailers")" ]] \
      || add_problem "the PR body must not carry '$key': the squash commit would carry it"
  done
  if [[ -n "$PROBLEMS" ]]; then
    printf 'PR rule violations:\n%s' "$PROBLEMS" >&2
    exit 1
  fi
  log "OK: PR title and trailers"
}

main "$@"
```

- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0. `check_pr.bats` 6개가 모두 ok이고, 커버리지 목록에 `/repo/scripts/check-pr.sh`가 나온다. 전체 라인 커버리지는 80% 이상이다. shfmt가 형식을 지적하면 `make fmt` 후 다시 실행한다.

- [ ] **Step 5: 커밋과 push**

```bash
git add scripts/check-pr.sh tests/check_pr.bats
git commit -m "feat: check pull request titles and trailers" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 08" --trailer "Task: 1"
git push
```

### Task 2: CI 워크플로, ruleset, PR 템플릿, Make base

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/pr-rules.yml`, `.github/rulesets/main.json`, `.github/pull_request_template.md`, `tests/github.bats`
- Modify: `Makefile:14,63-64`, `scripts/review.sh:187`

**Interfaces:**
- Consumes: Task 1의 `scripts/check-pr.sh`(`PR_TITLE`, `PR_BODY`)와 기존 `scripts/check-git.sh BASE BRANCH`
- Produces:
  - 상태 체크 이름 `check`(ci.yml의 잡 ID)와 `pr-rules`(pr-rules.yml의 잡 ID)
  - ruleset 파일 `.github/rulesets/main.json`. 마무리 단계에서 사람이 적용한다.
  - Make 기본값: `make check-git`은 `scripts/check-git.sh origin/main`, `make review`는 `REVIEW_BASE` 기본 `origin/main`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/github.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  WORKFLOWS="$REPO_DIR/.github/workflows"
  RULESET="$REPO_DIR/.github/rulesets/main.json"
}

@test "workflows run read-only on pull_request, pin actions by commit SHA and keep expressions out of run lines" {
  local file files bad=""
  files="$(find "$WORKFLOWS" -name '*.yml' 2>/dev/null | sort)"
  [[ -n "$files" ]] || fail "no workflows under .github/workflows"
  while IFS= read -r file; do
    grep -qx 'permissions:' "$file" && grep -qx '  contents: read' "$file" || bad="$bad $(basename "$file")(permissions)"
    ! grep -q 'pull_request_target' "$file" || bad="$bad $(basename "$file")(pull_request_target)"
    ! grep -E 'uses: ' "$file" | grep -vqE 'uses: [^@ ]+@[0-9a-f]{40}( |$)' || bad="$bad $(basename "$file")(action not pinned by SHA)"
    ! grep -qE '^ *(- )?run: *[|>]' "$file" || bad="$bad $(basename "$file")(multi-line run)"
    ! grep -qE '^ *(- )?run:.*\$\{\{' "$file" || bad="$bad $(basename "$file")(expression in run; pass it through env)"
  done <<<"$files"
  [[ -z "$bad" ]] || fail "fix these workflows:$bad"
}

@test "the main ruleset keeps one human approval, squash only and no bypass, and requires the jobs the workflows define" {
  run jq -e '
    .enforcement == "active" and .bypass_actors == []
    and .conditions.ref_name.include == ["~DEFAULT_BRANCH"]
    and ((["deletion", "non_fast_forward", "required_linear_history", "pull_request", "required_status_checks"] - [.rules[].type]) == [])
    and (.rules[] | select(.type == "pull_request") | .parameters
      | .required_approving_review_count >= 1 and .dismiss_stale_reviews_on_push and .require_last_push_approval
        and .allowed_merge_methods == ["squash"])
    and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy)
  ' "$RULESET"
  assert_success
  local required jobs
  required="$(jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' "$RULESET" | sort)"
  jobs="$(awk '/^jobs:/ { inside = 1; next } /^[a-z]/ { inside = 0 } inside && /^  [a-z0-9-]+:$/ { sub(/^ +/, ""); sub(/:$/, ""); print }' "$WORKFLOWS"/*.yml | sort)"
  [[ -n "$required" ]] || fail "the ruleset requires no status checks"
  [[ "$required" == "$jobs" ]] || fail "required checks ($required) must equal the workflow job ids ($jobs)"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `github.bats` 2개가 실패한다. 하나는 `no workflows under .github/workflows`, 다른 하나는 jq가 파일을 열지 못해서다.

- [ ] **Step 3: `.github/workflows/ci.yml`**

```yaml
# Lint, all tests and the coverage gate for every pull request into main
# (docs/specs/2026-10-13-github-pr-workflow-design.md, section 6).
name: ci

on:
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  check:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
        with:
          persist-credentials: false
      - run: make check
```

- [ ] **Step 4: `.github/workflows/pr-rules.yml`**

```yaml
# Branch name, commit trailers, and the PR title and body that become the squash commit
# (docs/specs/2026-10-13-github-pr-workflow-design.md, section 6). Runs again when the title or body is edited.
name: pr-rules

on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, edited]

permissions:
  contents: read

jobs:
  pr-rules:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0
          persist-credentials: false
      - name: Branch name and commit trailers
        env:
          HEAD_REF: ${{ github.head_ref }}
        run: git switch --quiet -c "$HEAD_REF" && scripts/check-git.sh origin/main "$HEAD_REF"
      - name: PR title and trailers
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
          PR_BODY: ${{ github.event.pull_request.body }}
        run: scripts/check-pr.sh
```

- [ ] **Step 5: `.github/rulesets/main.json`**

`integration_id` 15368은 GitHub Actions 앱의 ID다. **Verified** (2026-10-13, 공개 API): 공개 저장소 `cli/cli`의 PR #14650에서 head SHA에는 check-run 19개가 붙어 있었고, 그 앱이 `github-actions`(ID 15368)였다. 같은 PR의 merge SHA에는 check-run이 0개였다. 그래서 `pull_request` 워크플로의 check-run은 PR head SHA에서 조회한다. Task 4 Step 3에서 이 저장소의 첫 PR로 다시 확인한다.

```json
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "check", "integration_id": 15368 },
          { "context": "pr-rules", "integration_id": 15368 }
        ]
      }
    }
  ]
}
```

- [ ] **Step 6: `.github/pull_request_template.md`**

squash 병합은 본문을 그대로 커밋 메시지로 쓴다. 그래서 템플릿에는 HTML 주석을 넣지 않고, 마지막 문단을 트레일러로 둔다.

```markdown
## Summary

What changes and why.

## Plan

docs/plans/active/... or none

## Verification

Commands and results (for example `make check`: N ok, 0 not ok, coverage X%).

Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>
Plan: <NN|none>
```

- [ ] **Step 7: Makefile과 `review.sh` 안내 줄**

`Makefile:14`의 `export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR` 바로 위에 한 줄을 넣는다. 명령줄의 `REVIEW_BASE=<sha>`(2회차)와 환경변수는 그대로 우선한다.

```make
REVIEW_BASE := $(or $(REVIEW_BASE),origin/main)
```

`Makefile:63-64`의 `check-git` 타깃을 다음으로 바꾼다.

```make
check-git: ## Check the git policy for the current branch against origin/main (name, commit trailers, worktree config)
	scripts/check-git.sh origin/main
```

`scripts/review.sh:187`의 안내 줄을 다음으로 바꾼다. 리뷰 기록 파일(`docs/reviews/`)은 더 쓰지 않는다.

```bash
  log "Next: verify each finding, then post both reports and the Review record to the PR (git-workflow skill, Review)"
```

- [ ] **Step 8: 통과 확인**

Run: `make check`, then `make check-git`
Expected:
- `make check`는 exit 0이고 `github.bats` 2개가 ok다.
- `make check-git`은 `OK: git policy (<n> commits since origin/main)`이다.

- [ ] **Step 9: 커밋과 push, CI 첫 실행 확인**

```bash
git add .github tests/github.bats Makefile scripts/review.sh
git commit -m "ci: add the check and pr-rules workflows, the main ruleset and the PR template" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 08" --trailer "Task: 2"
git push
gh pr checks --watch
```

Expected: PR에 `check`와 `pr-rules`가 생기고 둘 다 pass다. 실패하면 Task 4 Step 1의 절차로 원인을 고친다.

### Task 3: 문서와 스킬

**Files:**
- Create: `docs/runbooks/github.md`
- Modify: `AGENTS.md:29-33`(Git), `AGENTS.md`의 Safety 끝과 Map, `.agents/skills/git-workflow/SKILL.md`(전체), `.agents/skills/git-workflow/references/review-and-merge.md`(전체), `docs/runbooks/accounts.md`(끝에 절 추가), `docs/ARCHITECTURE.md:30` 다음 줄, `README.md:15` 다음 줄, `docs/specs/2026-10-07-git-review-policy-design.md:3` 다음 줄

**Interfaces:**
- Consumes: Task 2의 체크 이름(`check`, `pr-rules`)과 Make 기본값, `.github/rulesets/main.json`
- Produces: 런북 `docs/runbooks/github.md`의 절 이름. 계획 09와 스킬이 이 런북을 링크한다.
  - `## 1. 머신 계정과 토큰`
  - `## 2. 공개 전 점검`
  - `## 3. 처음 push`
  - `## 4. 저장소 설정과 ruleset`
  - `## 5. 토큰 교체`
  - `## 6. 긴급 변경`

- [ ] **Step 1: `AGENTS.md`**

`## Git` 절(`AGENTS.md:29-33`)을 다음으로 바꾼다.

```markdown
## Git (policy: docs/specs/2026-10-13-github-pr-workflow-design.md on top of docs/specs/2026-10-07-git-review-policy-design.md)
- Work only in your own git worktree on `plan/<NN>-<slug>` or `work/<slug>`, branched from `origin/main` after `git fetch origin`; one agent per worktree, never in the main checkout. Rename tool default branches (`worktree-*`, `codex/*`) with `git branch -m` before you push; on a detached HEAD (Codex app) run `git switch -c <branch> origin/main` first. Per-tool steps: the `git-workflow` skill.
- Never commit or push to `main`, force-push, rebase or rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.
- End every commit message with the trailers `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`, `Plan: <NN|none>` and `Task: <N|review|none>`; add `Review-Finding: R<n>-F<m>` (cross-vendor review) or `SDD-T<task>-F<n>` (in-plan task review) to review fixes. Never add `Co-authored-by` or `Signed-off-by`.
- `gh` and `git push` on this Mac run as the machine account. Push your branch and open one draft PR per plan or work branch; the title is `<type>: <description>` and the body ends with the `Assisted-by` and `Plan` trailers, because the squash merge turns them into the commit on `main`. CI (`check`, `pr-rules`) must pass.
- A reviewer from another vendor reviews each PR read-only and the reports go to PR comments. Only the human approves and squash-merges; agents never approve, merge or press Update branch (keep a branch current with `git merge origin/main`).
```

Safety 절 끝(`- The user types the Tailscale auth key ...` 다음)에 한 줄을 넣는다.

```markdown
- Never write the VM's external or tailnet IP addresses in commits, PRs, PR comments or repo files; use `agent-hub` or a placeholder.
```

Map 절의 `- \`docs/research/\` ...` 다음에 한 줄을 넣는다.

```markdown
- `.github/` CI workflows, the `main` ruleset (`rulesets/main.json`) and the PR template; GitHub setup and token rotation: `docs/runbooks/github.md`.
```

- [ ] **Step 2: `.agents/skills/git-workflow/SKILL.md` (전체 교체)**

````markdown
---
name: git-workflow
description: Git workflow for agent work in this repo, from the first file change to the human's squash merge (own worktree from origin/main, plan/NN-slug or work/slug branch, commit trailers, draft pull request as the machine account, cross-vendor review, review fixes, hand-off). Use whenever you are about to change files, commit or push here, open a pull request, ask for a review, fix review findings or hand a pull request to the human.
---

# Agent git workflow

Policy: docs/specs/2026-10-13-github-pr-workflow-design.md (pull requests, review, merge) on top of docs/specs/2026-10-07-git-review-policy-design.md (branches, worktrees, trailers). Never commit or push to `main`, force-push, rebase or rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree. Never approve or merge a pull request.

## Start

1. Your identity is the literal trailer value `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model id>`, for example `Assisted-by: codex gpt-6.1-sol`. Write it out in every commit command: your shell may not keep exported variables between commands, and an empty trailer can only be repaired by rewriting history.
2. Run `git fetch origin`, then work in your own worktree on your own branch from `origin/main`: one agent per worktree, one worktree per branch, never the main checkout.
   - Claude Code: start with `claude --worktree <slug>` (it creates `.claude/worktrees/<slug>` from `origin/main`), then `git branch -m plan/NN-slug` or `git branch -m work/slug`.
   - Codex app: the app already runs you in a detached worktree under `$CODEX_HOME/worktrees`; run `git switch -c plan/NN-slug origin/main` (or `work/slug`) there.
   - Codex CLI, Gemini CLI, Antigravity: they can write only inside the directory they were started in. From any directory of this repo, create the worktree next to the main checkout:
     `git -C "$(git rev-parse --path-format=absolute --git-common-dir)/.." worktree add ../027_agent_share_poc-wt/<slug> -b plan/NN-slug origin/main`
     Then end this session and start the tool again inside that directory (`codex -C <dir>`, `cd <dir> && gemini`, or open the folder in Antigravity); `git worktree list` shows its absolute path.
3. For a plan, make the first commit move the plan file from `docs/plans/backlog/` to `docs/plans/active/`.
4. For work that belongs to no plan (an upgrade, a fix, a doc change), use a `work/<slug>` branch and write `Plan: none` and `Task: none` in every commit.

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: <tool> <model id>" --trailer "Plan: <NN|none>" --trailer "Task: <N|review|none>"`, with your identity written out. If you keep it in a variable, set it in the same command and write `${AGENT_ID:?set AGENT_ID}`, so an unset value stops the commit instead of writing an empty trailer.
3. Never add `Co-authored-by` or `Signed-off-by`.
4. `make check-git` (it checks against `origin/main`) must pass before you push.

## Publish

1. After the first commit run `git push -u origin <branch>`, then open one draft pull request for the whole branch: `gh pr create --draft --base main --title "<type>: <description>" --body-file <file>`. The body follows `.github/pull_request_template.md`: summary, plan file, verification evidence, and as the last paragraph `Assisted-by: <tool> <model id>` (one line per tool that worked on the branch) and `Plan: <NN|none>`. Replace the template's example text; the squash merge turns the title and body into the commit on `main`.
2. Push after every commit. CI runs `check` (`make check`) and `pr-rules` (branch name, commit trailers, PR title and trailers). Fix every failure; editing the title or body re-runs `pr-rules`.
3. `gh` and `git push` run as the machine account. If your sandbox blocks the network, ask the human to run the push or `gh` command.
4. Never write the VM's external or tailnet IP addresses in commits, the pull request or comments.

## Review and merge

When the plan's tasks are done, read [references/review-and-merge.md](references/review-and-merge.md) and follow it in order: review, fix findings, keep the branch current, hand the pull request to the human, clean up. Read it again before each of those phases; never review your own branch.
````

- [ ] **Step 3: `.agents/skills/git-workflow/references/review-and-merge.md` (전체 교체)**

`tests/skills.bats`에 따라 이 파일은 같은 스킬의 다른 파일을 링크하지 않는다(`references/` 문자열도 쓰지 않는다).

```markdown
# Review and merge

The phases after the last task commit, in order. Policy: docs/specs/2026-10-13-github-pr-workflow-design.md, sections 8 and 9.

## Review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`) and push.
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex` (runs `codex exec review` with `-c 'sandbox_mode="read-only"'`; never use a writable sandbox)
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
   The base is `origin/main`.
3. `make review` starts `codex` or `claude`, which need network access: run it where they can reach the network, outside the sandbox of the agent that calls it. If your sandbox blocks the network, ask the human to run the command.
4. Post both raw reports to the pull request, one comment each: `gh pr comment <PR> --body-file <report>` for the `-diff.md` and `-plan.md` files that `make review` logs (in the main checkout's `.review-out/`). Put a first line above each report: `Agent review R<round>: <reviewer tool> <model>, base <sha>, reviewed head <sha>`.
5. Keep one "Review record" comment on the pull request: a table with the columns ID (`R1-F3`), Sev, Location, Summary and Status, where Status is `open`, `fixed <sha>`, `rejected <evidence>` or `deferred <human's reason>`. Create it with `gh pr comment <PR> --body-file <file>` and edit that comment on GitHub when a status changes.

## Fix findings

1. Verify each finding before acting: reproduce it or cite the code. Mark unfounded ones `rejected <evidence>`.
2. Fix accepted findings one commit each, with `--trailer "Review-Finding: R<round>-F<n>"`, push, and set their status to `fixed <sha>`.
3. If anything changed, run round 2 on the new commits only: `make review BRANCH=<branch> REVIEWER=<same> ROUND=2 REVIEW_BASE=<reviewed head sha>`, and post it like round 1. After round 2, leave any remaining disagreement to the human.

## Keep the branch current

When GitHub says the branch is out of date with `main` (the required checks are strict):

1. `git fetch origin`, then `git merge origin/main` and resolve any conflicts. Never rebase or force-push.
2. `make check`, then push. The push dismisses the approval and re-runs CI.
3. If resolving conflicts changed code after the review, say what changed in a pull request comment and have the other vendor review only the new commits (`REVIEW_BASE=<previous head>`).
4. The human never presses Update branch: the last push must come from the machine account, or the human cannot approve it (last-push approval in the ruleset).

## Hand the pull request to the human

1. Check: CI passes; the Review record has no open P0/P1; every deferred P2 carries the human's reason.
2. Run `gh pr ready <PR>` and tell the human the pull request number. The human approves and squash-merges; never merge yourself.

## Clean up

After `gh pr view <PR> --json state` shows `MERGED`:

1. `git worktree remove` deletes ignored files such as `backups/` and `.env` without any warning, so first run `ls <your worktree>/backups <your worktree>/.env` and move any archive into the main checkout's `backups/` (never overwrite a file there).
2. Run `git worktree remove <your worktree>` and `git branch -D <branch>` (`-d` refuses a squash-merged branch). GitHub deletes the remote branch.
3. The human updates the main checkout with `git pull --ff-only`.
```

- [ ] **Step 4: `docs/runbooks/github.md` (새 파일, 한국어)**

````markdown
# GitHub 운영: 머신 계정, 첫 push, 저장소 설정

정책: [GitHub PR 워크플로 스펙](../specs/2026-10-13-github-pr-workflow-design.md). 저장소: `https://github.com/yanghs6/basic-memory-tailnet` (공개). 이 런북의 명령은 사용자가 자기 터미널에서 실행합니다. `gh auth login`은 대화형이라 별도 터미널 앱에서 실행합니다.

## 1. 머신 계정과 토큰

1. 새 이메일로 GitHub 계정(예: `yanghs6-bot`)을 만들고 2FA를 켭니다. 약관상 사람이 직접 만들고, 자동화 작업에만 씁니다(**Verified**, GitHub 약관 B(3)).
2. 개인 계정으로 머신 계정을 이 저장소의 협업자(권한 Write)로 초대하고, 머신 계정으로 수락합니다. 머신 계정에는 다른 저장소 권한을 주지 않고, 머신 계정으로 저장소를 만들지 않습니다. classic 토큰의 실제 범위는 계정 권한으로 정해지기 때문입니다.
3. 머신 계정에서 classic 토큰을 만듭니다. Settings → Developer settings → Personal access tokens (classic)에서 범위는 `public_repo`와 `workflow`, 만료는 90일로 둡니다. 남의 공개 저장소에 쓰려면 classic 토큰이어야 합니다(**Verified**, GitHub 토큰 문서).
4. 이 Mac에 등록합니다. 토큰은 숨김 프롬프트에만 붙여 넣고, 채팅·파일·명령 인자·파이프에 넣지 않습니다.

```bash
gh auth login            # GitHub.com → HTTPS → Paste an authentication token
gh auth status           # 머신 계정이 보여야 합니다
cd <main 체크아웃>
git config --local credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!gh auth git-credential'
```

- credential 설정은 이 저장소에만 적용됩니다. 모든 worktree가 main 체크아웃의 설정을 공유합니다.
- 기본 `gh`는 머신 계정입니다. 사용자가 관리자 작업을 할 때는 개인 계정용 설정 디렉터리를 따로 씁니다. 처음 한 번 `GH_CONFIG_DIR="$HOME/.config/gh-yanghs6" gh auth login`으로 로그인합니다.

## 2. 공개 전 점검

처음 공개하는 이력(첫 push의 `main`, 처음 push하는 브랜치)마다 실행합니다. `<ref>`는 공개할 브랜치입니다.

```bash
git log -p <ref> | grep -nE 'tskey-[A-Za-z0-9]{10,}|PRIVATE KEY|([0-9]{1,3}\.){3}[0-9]{1,3}|[a-z0-9-]+\.ts\.net|@[A-Za-z0-9.-]+\.[a-z]{2,}'
git log -p <ref> | grep -cF '<실제 VM 외부 IP>'
git log -p <ref> | grep -cF '<실제 VM Tailscale IP>'
git log -p <ref> | grep -cF '<GCP 프로젝트 ID>'
```

- 첫 명령에 걸린 줄이 테스트용 자리표시자인지 하나씩 확인합니다. 예: `127.0.0.1`, `203.0.113.10`, `tail1234.ts.net`, `agent@example.com`, `tskey-auth-test123`.
- 나머지 명령은 모두 `0`이어야 합니다.
- **실제 값이 걸리면 push하지 않습니다.** 현재 파일만 고쳐도 과거 커밋에는 값이 남습니다. 공개를 허용할지, 이력을 정리할지를 사용자가 정합니다(스펙 11절). 실제 자격증명이면 공개 여부와 관계없이 폐기하고 교체합니다.
- `plan/05-vm-rollout`은 push하지 않습니다. 커밋 하나에 VM Tailscale IP가 있습니다. 계획 05는 스펙 11절의 `plan/05-vm-rollout-public` 절차로 공개합니다.

## 3. 처음 push

원격 `main`에는 `LICENSE` 커밋 하나가 있고, 로컬 이력과 공통 조상이 없습니다. main 체크아웃에서 한 번만 실행합니다. force push는 쓰지 않습니다.

```bash
git remote add origin https://github.com/yanghs6/basic-memory-tailnet.git
git fetch origin
git merge --allow-unrelated-histories origin/main -m "Merge the GitHub repository's initial commit"
git push -u origin main
```

## 4. 저장소 설정과 ruleset

계획 08의 PR이 병합된 **뒤에** 적용합니다. 필수 체크는 워크플로가 `main`에 들어간 뒤에 걸어야 합니다. 그 전에 걸면 어떤 PR도 병합할 수 없습니다.

```bash
export GH_CONFIG_DIR="$HOME/.config/gh-yanghs6"
R=repos/yanghs6/basic-memory-tailnet
gh api -X PATCH "$R" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F allow_auto_merge=false -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
gh api -X PUT "$R/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
gh api -X PUT "$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
gh api -X PATCH "$R" -f 'security_and_analysis[secret_scanning][status]=enabled' -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
gh api "$R/commits/<계획 08 PR의 head SHA>/check-runs" --jq '.check_runs[] | "\(.name) \(.app.id) \(.app.slug)"'
gh api -X POST "$R/rulesets" --input .github/rulesets/main.json
unset GH_CONFIG_DIR
```

- check-run 명령의 출력은 `check 15368 github-actions`, `pr-rules 15368 github-actions` 형태여야 합니다. 앱 ID가 15368이 아니면 `main.json`의 `integration_id`를 고치는 PR을 먼저 병합합니다.
- secret scanning 명령이 실패하면(플랜이 지원하지 않음) 그 사실을 Progress log에 적습니다. 이때는 계정 단위 push protection(기본 켜짐)에 맡깁니다.
- 확인은 로그인 없이 공개 API로 합니다.

```bash
curl -sS https://api.github.com/repos/yanghs6/basic-memory-tailnet/rules/branches/main | jq -r '.[].type'
```

Expected: `deletion`, `non_fast_forward`, `required_linear_history`, `pull_request`, `required_status_checks`

## 5. 토큰 교체

90일 만료 전에, 또는 유출이 의심되면 바로 합니다.

1. 머신 계정에서 새 classic 토큰을 만듭니다(범위와 만료는 1절과 같음).
2. `gh auth login`으로 다시 등록하고 `gh auth status`로 확인합니다.
3. 이전 토큰을 머신 계정 설정에서 삭제합니다.

## 6. 긴급 변경

ruleset의 우회 목록은 비어 있어서, 사용자도 `main`에 직접 push할 수 없습니다. 꼭 필요할 때만 다음 순서로 합니다.

1. Settings → Rules → Rulesets → `main` → Enforcement를 Disabled로 바꿉니다.
2. 필요한 변경을 합니다.
3. Enforcement를 Active로 되돌리고, 4절의 확인 명령으로 규칙 5개가 다시 보이는지 확인합니다.
4. 무엇을 왜 했는지 [운영 런북](operations.md)의 Incident log에 적습니다.
````

- [ ] **Step 5: `docs/runbooks/accounts.md` 끝에 절 추가**

```markdown
## 6. GitHub

저장소는 개인 계정 `yanghs6`의 공개 저장소 `basic-memory-tailnet`입니다. 에이전트는 따로 만든 머신 계정으로 push하고 PR을 엽니다. 승인과 병합은 개인 계정으로만 합니다. 머신 계정 만들기, 토큰 등록, 저장소 설정은 [GitHub 런북](github.md)에 있습니다.
```

- [ ] **Step 6: `docs/ARCHITECTURE.md`, `README.md`, 기존 정책 스펙**

`docs/ARCHITECTURE.md:30`(리뷰·스킬 도구 행) 다음에 한 행을 넣는다.

```markdown
| GitHub `yanghs6/basic-memory-tailnet` | 원격 (공개) | PR과 squash 병합, CI `check`·`pr-rules`(`.github/workflows/`), ruleset `main`(`.github/rulesets/main.json`). 에이전트는 머신 계정으로 PR을 열고 사람만 승인·병합. [GitHub 런북](runbooks/github.md) |
```

`README.md:15`(`- 교차 리뷰(...)` 줄) 다음에 한 줄을 넣는다.

```markdown
- 에이전트 작업을 PR로 올릴 때: GitHub CLI `gh`(머신 계정으로 로그인, [GitHub 런북](docs/runbooks/github.md))
```

`docs/specs/2026-10-07-git-review-policy-design.md:3`(상태 줄) 다음에 한 줄을 넣는다.

```markdown
- 부분 대체 (2026-10-13): 3절의 브랜치 기준점, 4절의 병합 트레일러, 5절의 리뷰 기록 위치, 6절 전체는 [GitHub PR 워크플로 스펙](2026-10-13-github-pr-workflow-design.md)이 대체한다.
```

- [ ] **Step 7: 확인**

Run: `make check`
Expected:
- exit 0
- `skills.bats`가 통과한다: description에 `Use when`이 있고 `': '`·꺾쇠가 없으며, 참조 파일이 다른 파일을 링크하지 않는다.
- `repo.bats`의 상대 링크 검사와 docs 경로 검사가 통과한다.

Run: `grep -rnE 'no-ff|Review-Record|merge-<branch' AGENTS.md .agents/skills docs/runbooks README.md docs/ARCHITECTURE.md`
Expected: 출력 없음(exit 1). 옛 병합 절차가 남아 있지 않다.

- [ ] **Step 8: 커밋과 push**

```bash
git add AGENTS.md .agents/skills/git-workflow docs/runbooks/github.md docs/runbooks/accounts.md docs/ARCHITECTURE.md README.md docs/specs/2026-10-07-git-review-policy-design.md
git commit -m "docs: describe the GitHub pull-request workflow for agents and humans" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 08" --trailer "Task: 3"
git push
```

### Task 4: GitHub에서 확인 (컨트롤러와 사람)

**Files:**
- Modify: 이 계획 파일(Progress log). 필요하면 `.github/rulesets/main.json`의 `integration_id`

- [ ] **Step 1: CI 결과 확인**

Run: `gh pr checks <PR>`
Expected: `check`와 `pr-rules`가 pass다. `check`가 실패하면 `gh run view <run-id> --log-failed`로 원인을 찾는다. 로컬과 다른 원인(Docker 권한, kcov, git 소유권, 얕은 clone)이면 그 원인을 고치는 커밋을 만든다(`Task: 4`). 테스트를 약하게 바꾸지는 않는다.

- [ ] **Step 2: `edited` 재실행 확인 (스펙 2절의 Assumption)**

```bash
gh pr view <PR> --json body --jq .body >"$TMPDIR/pr-08-body.md"
cp "$TMPDIR/pr-08-body.md" "$TMPDIR/pr-08-body.orig.md"
printf '\nThanks for reviewing.\n' >>"$TMPDIR/pr-08-body.md"
gh pr edit <PR> --body-file "$TMPDIR/pr-08-body.md"
gh run list --workflow pr-rules.yml --limit 2
gh pr edit <PR> --body-file "$TMPDIR/pr-08-body.orig.md"
gh run list --workflow pr-rules.yml --limit 2
```

Expected:
- 첫 `gh pr edit` 직후 `pr-rules`가 `edited` 이벤트로 다시 돌고 실패한다. 마지막 문단이 트레일러가 아니게 됐기 때문이다(`missing trailer`).
- 원래 본문으로 되돌리면 `pr-rules`가 다시 돌고 pass한다.
- 두 결과를 Progress log에 `Verified`로 적는다. `edited`가 발생하지 않으면 스펙 6절의 대응을 사용자와 정한다.

- [ ] **Step 3: check-run 앱 ID 확인 (Review Focus 5)**

Run: `curl -sS https://api.github.com/repos/yanghs6/basic-memory-tailnet/commits/$(git rev-parse HEAD)/check-runs | jq -r '.check_runs[] | "\(.name) \(.app.id) \(.app.slug)"'`
Expected: `check 15368 github-actions`, `pr-rules 15368 github-actions`. 다르면 `main.json`의 두 `integration_id`를 실제 값으로 고치고, `make check` 후 커밋한다(`Task: 4`).

- [ ] **Step 4: Progress log 기록과 커밋**

```bash
git add docs/plans/active/2026-10-13-08-github-switch.md
git commit -m "docs: record the first CI runs of plan 08" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 08" --trailer "Task: 4"
git push
```

### 마무리: 리뷰, 넘기기, 병합 후 설정

- [ ] `make check`와 `make check-git`이 통과하는지 확인한다.
- [ ] 계획 파일을 `docs/plans/completed/`로 옮겨 커밋하고(`Task: none`) push한다.
- [ ] git-workflow 스킬의 Review 절을 따른다.
  - `make review BRANCH=plan/08-github-switch REVIEWER=<다른 벤더>`를 실행한다. Codex 리뷰는 사용량 비용이 들므로 사용자의 승인을 받은 뒤 실행한다.
  - 두 리포트를 PR 코멘트로 게시하고 Review record 코멘트를 만든다.
- [ ] 지적을 검증하고 고친다. 2회차까지만 돈다.
- [ ] CI가 통과하고 Review record에 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고, 사용자에게 PR 번호를 알린다.
- [ ] **사람:** 병합 전에 `docs/runbooks/github.md` 4-1절의 저장소 설정을 적용하고, 확인 명령에서 `PR_TITLE`, `PR_BODY`, `true`, `false`, `false`를 본다.
- [ ] **사람:** Approve 후 Squash and merge를 누른다.
- [ ] **사람:** 병합 뒤에 `docs/runbooks/github.md` 4-2절을 따른다. main 체크아웃을 갱신하고, check-run 출력을 확인하고, ruleset을 적용한 뒤 공개 API로 규칙 5개를 확인한다. 스펙 Open question 4(secret scanning)의 결과는 계획 09의 첫 커밋에서 Progress log에 적는다.
- [ ] 에이전트는 git-workflow 스킬의 Clean up 절로 worktree를 정리한다.
- [ ] squash 커밋의 작성자와 `Co-authored-by` 자동 추가 여부(스펙 Open question 3)를 확인한다. 명령은 `git log -1 --format='%an <%ae>%n%b' origin/main`이고, 결과는 계획 09의 첫 커밋에서 기록한다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-14 | Verified | 전제 1~3 확인. `origin`이 `https://github.com/yanghs6/basic-memory-tailnet.git`이고 로컬 `main` = `origin/main` = `de91861`(원격 `LICENSE` 커밋 `c3f0943`을 병합)이다. GitHub의 브랜치는 `main` 하나다. `gh api user`는 머신 계정 `yangtestdev`이고 이 저장소에 `push: true`, `admin: false`다. credential helper는 이 저장소에만 `!gh auth git-credential`이다. 머신 계정 이름이 정해졌다(스펙 Open question 5). |
| 2026-10-14 | Verified | 브랜치 이름은 `plan/08-github-switch` 대신 `plan/08-gh-switch`로 했다. 이 세션의 worktree 가드는 한 명령에 `git`이 두 번 나오면 거부한다. 첫 커밋 `21fbb8e`, 초안 PR #1(작성자 `yangtestdev`). |
| 2026-10-14 | Command | Task 1 (`5cf968f`): `make test`에서 `check_pr.bats` 6개가 먼저 실패했다(exit 127). 스크립트를 넣은 뒤 `make check`는 exit 0이고, `check-pr.sh` 97.30%, 전체 96.97%다. 이 커밋에는 하네스 안내를 따른 `Claude-Session` 트레일러가 더 붙었다. 이력 재작성 금지라서 그대로 둔다. |
| 2026-10-14 | Command | Task 2 (`254b0fc`): `make test`에서 `github.bats` 2개가 먼저 실패했다. 파일을 넣은 뒤 `make check`는 exit 0이고, 156 ok, 전체 96.97%다. `make check-git`은 `OK: git policy (3 commits since origin/main)`이다. |
| 2026-10-14 | Command | Task 3 (`a71b574`): `make check`는 exit 0이고 156 ok다. Step 7의 `grep -rnE 'no-ff\|Review-Record\|merge-<branch' ...`는 출력이 없다. `tests/main_checkout.bats:76-79`가 `ls <your worktree>/backups`와 `git worktree remove <your worktree>`를 한 줄에서 찾으므로, review-and-merge.md의 Clean up 1·2항목을 한 항목으로 합쳤다. |
| 2026-10-14 | Verified | Task 4 Step 1: PR #1의 `check`와 `pr-rules`가 `254b0fc`(1m10s, 4s)와 `a71b574`(58s, 4s)에서 모두 pass다. 외부 앱 GitGuardian의 check도 붙지만 필수 체크는 아니다. |
| 2026-10-14 | Verified | Task 4 Step 2 (스펙 2절 Assumption 해소): 본문 끝에 `Thanks for reviewing.` 문단을 붙이자 같은 head `a71b574`에서 `pr-rules`가 다시 돌고 실패했다(run 38500200654, `missing trailer` 2건). 원래 본문으로 되돌리자 다시 돌고 pass했다(run 38500240664). `edited`는 본문 수정으로 발생한다. |
| 2026-10-14 | Verified | Task 4 Step 3: `curl -sS https://api.github.com/repos/yanghs6/basic-memory-tailnet/commits/a71b574.../check-runs`의 결과는 `check 15368 github-actions`, `pr-rules 15368 github-actions`다. `main.json`의 `integration_id`는 그대로 둔다. |
