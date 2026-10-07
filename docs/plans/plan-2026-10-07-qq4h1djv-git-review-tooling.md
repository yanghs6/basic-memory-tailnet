# qq4h1djv Git and Review Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 에이전트 git·리뷰 정책을 도구로 뒷받침한다. `make check-git`(브랜치 이름·커밋 트레일러·worktree 설정 검사), `make review`(다른 벤더 에이전트의 읽기 전용 리뷰), Claude 리뷰어 에이전트, 작성자용·리뷰어용 스킬, `AGENTS.md`의 리뷰 규칙을 만든다.

**Architecture:**
- 정책 원문은 `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`다. 이 계획은 정책을 바꾸지 않고 검사·실행 도구만 만든다.
- `check-git.sh`는 현재 브랜치와 `main..HEAD` 커밋을 git 명령만으로 검사한다.
- `review.sh`는 리뷰 전용 detached worktree를 만들어 `codex` 또는 `claude`를 읽기 전용 모드로 실행하고, 결과 원문을 `.review-out/`에 저장한 뒤 worktree를 지운다.
- 두 스크립트 모두 테스트에서는 임시 git 저장소와 `codex`·`claude` stub으로 검증한다.

**Tech Stack:** Bash(macOS 3.2 호환), git ≥2.32(`--trailer`), GNU Make, bats-core 1.14.0 + bats-support/assert, kcov, shellcheck 0.11.0, shfmt 3.12.0, Codex CLI 0.160.1, Claude Code 2.1.292

**Spec:** `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md` (정책), `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md` (저장소 공통 규칙)

**Sequence:** 계획 2/5. 전제: [local-foundation 계획](plan-2026-10-07-sqzn0teq-local-foundation.md) 완료·병합(`make check` PASS, 테스트 40개). 다음 계획: `docs/plans/plan-2026-10-07-dry1xr43-vm-scripts.md`

## Global Constraints

- Git (`docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`):
  - 이 계획은 `plan/qq4h1djv-git-review-tooling` 브랜치의 전용 worktree에서 진행한다. `main`에 직접 커밋하지 않고, force-push·히스토리 재작성·`git gc`를 하지 않는다.
  - 커밋 형식은 `<type>: <description>`(feat, fix, refactor, docs, test, chore)이고, 메시지 끝에 트레일러 `Assisted-by: <도구> <모델>`, `Plan: qq4h1djv`, `Task: N`을 단다. 커밋 명령은 시작 단계에서 정한 `AGENT_ID` 환경변수를 쓴다.
  - `Co-authored-by`와 `Signed-off-by`는 넣지 않는다(사용자 전역 설정과 저장소 정책).
  - 매 커밋 전에 `make check`를 실행한다.
- 스크립트 작성 규칙:
  - `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`을 두고, `scripts/lib/common.sh`를 source한다.
  - **macOS bash 3.2 호환**: `mapfile`, `readarray`, `declare -A`, `${x,,}`, `inherit_errexit`, 빈 배열 확장을 쓰지 않는다.
  - die할 수 있는 함수를 `x="$(fn)"`로 호출하면 뒤에 `|| exit 1`을 붙인다.
- shfmt 스타일은 `.editorconfig`를 따른다. lint가 포맷 차이를 보고하면 `make fmt`로 고친다. trap으로만 호출되는 함수에 SC2317이 나오면 `# shellcheck disable=SC2317  # invoked via trap`을 붙인다.
- 커버리지: `scripts/` 라인 커버리지 80% 이상, `scripts/` 아래 모든 실행 스크립트가 최소 한 테스트에서 실행돼야 한다.
- 리뷰어는 읽기 전용이다. `review.sh`와 리뷰어 에이전트는 리뷰 대상 브랜치의 파일을 고치거나 커밋하지 않는다.
- 언어: 코드, 주석, 스크립트 메시지, `AGENTS.md`, `SKILL.md`, 리뷰 기록은 영어로 쓴다. 저장소 노트에는 `Verified` / `Command` / `Assumption` / `Open question` 표기를 쓴다.

## Review Focus

1. **병합 커밋 오탐:** 브랜치에 `main`을 병합한 커밋(트레일러 없음)이 있어도 `check-git`이 실패하면 안 된다. → Task 1에서 `--no-merges` 테스트를 추가한다.
2. **리뷰어가 브랜치를 바꿈:** 리뷰는 detached worktree에서만 돌고, 끝나면 worktree가 사라져야 한다. 리뷰어 실패 시에도 마찬가지다. → Task 2에서 실행 위치와 정리 테스트를 추가한다. 실제 CLI의 읽기 전용 동작은 마무리 단계에서 실제 리뷰로 확인한다.
3. **같은 벤더의 셀프 리뷰:** 작성 도구와 같은 벤더의 리뷰어를 고르면 명시적으로 허용하지 않는 한 거부해야 한다. → Task 2에서 테스트를 추가한다.
4. **2차 리뷰 범위:** 2차는 리뷰한 head 이후 커밋만 봐야 하고, 이를 위해 만든 임시 브랜치는 남지 않아야 한다. → Task 2에서 테스트를 추가한다.
5. **오래된 리뷰 worktree:** 이전 리뷰가 남긴 worktree를 덮어쓰거나 지우지 말고, 정리 방법을 알려 주고 멈춰야 한다. → Task 2에서 테스트를 추가한다.

## File Structure

```
scripts/check-git.sh tests/check_git.bats                         Task 1
scripts/review.sh tests/stubs/{codex,claude} tests/review.bats    Task 2
.claude/agents/branch-reviewer.md                                 Task 3
.agents/skills/{git-workflow,branch-review}/SKILL.md .claude/skills/* (symlinks)   Task 3
docs/reviews/README.md                                            Task 3
AGENTS.md .claude/settings.json tests/repo.bats                   Task 3에서 수정
Makefile                                                          Task 1, 2에서 타깃 추가
```

---

### 시작: 브랜치와 worktree

- [ ] 이 계획을 진행할 에이전트를 기록한다: `export AGENT_ID="<도구> <모델 ID>"` (예: `claude-code claude-opus-5-5`). 도구 값은 `claude-code`, `codex`, `antigravity`, `gemini-cli` 중 하나다.
- [ ] 전용 worktree와 브랜치를 만든다. 한 계획 브랜치는 한 번에 한 worktree에서만 진행한다.
  - Claude Code: `claude --worktree plan-02-git-review-tooling`로 시작하거나 세션 안에서 worktree에 들어간 뒤 `git branch -m plan/qq4h1djv-git-review-tooling`
  - 그 밖의 도구: `git worktree add ../027_agent_share_poc-wt/plan-02-git-review-tooling -b plan/qq4h1djv-git-review-tooling main` 후 그 디렉터리에서 작업
- [ ] 첫 커밋으로 이 계획 파일을 `backlog/`에서 `active/`로 옮긴다.

```bash
git mv docs/plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md docs/plans/active/
git commit -m "docs: activate the git-review-tooling plan" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: none"
```

---

### Task 1: 정책 검사 스크립트 (`check-git.sh`)

**Files:**
- Create: `scripts/check-git.sh`
- Modify: `Makefile`(`check-git` 타깃)
- Test: `tests/check_git.bats`

**Interfaces:**
- Consumes: `common.sh`의 `log`, `die`, `require_cmd`
- Produces:
  - CLI: `scripts/check-git.sh [BASE]`(기본 `main`). 통과하면 0과 `OK: git policy (<n> commits since <base>)`, 위반이 있으면 1과 `git policy violations:` 아래 위반 목록(위반마다 고치는 방법 포함)
  - 검사 항목: `extensions.worktreeConfig`, 현재 브랜치(detached HEAD, `main`, 이름 패턴), `BASE..HEAD`의 병합이 아닌 커밋마다 `Assisted-by`·`Plan`·`Task` 존재와 형식, `Co-authored-by`·`Signed-off-by` 부재
  - Make 타깃 `check-git`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/check_git.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  cd "$WORK"
  git config user.email agent@example.com
  git config user.name agent
  git commit -q --allow-empty -m "chore: init"
  CHECK="$REPO_DIR/scripts/check-git.sh"
}

# agent_commit SUBJECT [extra git commit args...]: a policy-compliant agent commit.
agent_commit() {
  local subject="$1"
  shift
  git commit -q --allow-empty -m "$subject" \
    --trailer "Assisted-by: claude-code claude-opus-5-5" --trailer "Plan: 02" --trailer "Task: 1" "$@"
}

@test "passes on a plan branch whose commits carry every trailer" {
  git switch -q -c plan/02-git-review-tooling
  agent_commit "feat: add check"
  run "$CHECK"
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "accepts work branches with Plan none and Task review" {
  git switch -q -c work/fix-docs
  git commit -q --allow-empty -m "docs: record review" \
    --trailer "Assisted-by: codex gpt-5-codex" --trailer "Plan: none" --trailer "Task: review"
  run "$CHECK"
  assert_success
}

@test "fails on main because agents never commit to main" {
  run "$CHECK"
  assert_failure
  assert_output --partial "on main: agents never commit to main"
}

@test "fails in detached HEAD" {
  git checkout -q --detach
  run "$CHECK"
  assert_failure
  assert_output --partial "detached HEAD: create a branch first"
}

@test "fails on a branch name outside plan/ and work/" {
  git switch -q -c feature/x
  run "$CHECK"
  assert_failure
  assert_output --partial "branch 'feature/x' must look like plan/NN-slug or work/slug"
}

@test "lists every missing trailer with the commit" {
  git switch -q -c work/no-trailers
  git commit -q --allow-empty -m "feat: no trailers"
  run "$CHECK"
  assert_failure
  assert_output --partial '"feat: no trailers": missing trailer '"'"'Assisted-by:'
  assert_output --partial "missing trailer 'Plan:"
  assert_output --partial "missing trailer 'Task:"
}

@test "rejects malformed trailer values" {
  git switch -q -c work/bad-values
  git commit -q --allow-empty -m "feat: bad values" \
    --trailer "Assisted-by: Claude" --trailer "Plan: 1" --trailer "Task: first"
  run "$CHECK"
  assert_failure
  assert_output --partial "trailer 'Assisted-by: Claude' must be"
  assert_output --partial "trailer 'Plan: 1' must be"
  assert_output --partial "trailer 'Task: first' must be"
}

@test "rejects Co-authored-by and Signed-off-by" {
  git switch -q -c work/attribution
  agent_commit "feat: attributed" --trailer "Co-authored-by: Bot <bot@example.com>" --signoff
  run "$CHECK"
  assert_failure
  assert_output --partial "agents never add 'Co-authored-by'"
  assert_output --partial "agents never add 'Signed-off-by'"
}

@test "flags extensions.worktreeConfig because it breaks Antigravity" {
  git switch -q -c work/config
  git config extensions.worktreeConfig true
  run "$CHECK"
  assert_failure
  assert_output --partial "git config --unset extensions.worktreeConfig"
}

@test "ignores merge commits brought into the branch" {
  git switch -q -c plan/02-merge
  agent_commit "feat: on branch"
  git switch -q main
  git commit -q --allow-empty -m "chore: on main"
  git switch -q plan/02-merge
  git merge -q --no-ff main -m "Merge main"
  run "$CHECK"
  assert_success
  assert_output --partial "OK: git policy (1 commits since main)"
}

@test "fails clearly when the base branch does not exist" {
  git switch -q -c work/x
  run "$CHECK" nope
  assert_failure
  assert_output --partial "base branch 'nope' not found"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `check_git.bats` 11개가 `scripts/check-git.sh: No such file or directory`로 실패한다.

- [ ] **Step 3: `scripts/check-git.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Check the git policy for the current branch (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md):
# branch name, trailers on every non-merge commit in BASE..HEAD, forbidden trailers, worktree config.
# Usage: check-git.sh [BASE]   (default: main)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly BRANCH_PATTERN='^(plan/[0-9]{2}-[a-z0-9-]+|work/[a-z0-9-]+)$'
readonly ASSISTED_BY_PATTERN='^(claude-code|codex|antigravity|gemini-cli) [^ ]+$'
readonly PLAN_PATTERN='^([0-9]{2}|none)$'
readonly TASK_PATTERN='^([0-9]+|review|none)$'
readonly FORBIDDEN_TRAILERS="Co-authored-by Signed-off-by"
readonly POLICY_HINT="see AGENTS.md, Git; ask the human before rewriting history"

PROBLEMS=""

add_problem() {
  PROBLEMS="${PROBLEMS}  - $*
"
}

# trailer COMMIT KEY -> the trailer's values joined by commas; empty when absent.
trailer() {
  git log -1 --format="%(trailers:key=$2,valueonly,separator=%x2C)" "$1"
}

check_worktree_config() {
  if [[ "$(git config --get extensions.worktreeConfig || true)" == true ]]; then
    add_problem "extensions.worktreeConfig is enabled and breaks Antigravity: git config --unset extensions.worktreeConfig"
  fi
}

check_branch() {
  local base="$1" branch
  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  if [[ -z "$branch" ]]; then
    add_problem "detached HEAD: create a branch first (git switch -c plan/NN-slug or work/slug)"
  elif [[ "$branch" == "$base" ]]; then
    add_problem "on $base: agents never commit to $base; move the work with git switch -c work/<slug>"
  elif [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    add_problem "branch '$branch' must look like plan/NN-slug or work/slug: git branch -m <new-name>"
  fi
}

# check_trailer WHERE COMMIT KEY PATTERN FORMAT
check_trailer() {
  local where="$1" sha="$2" key="$3" pattern="$4" format="$5" value
  value="$(trailer "$sha" "$key")"
  if [[ -z "$value" ]]; then
    add_problem "$where: missing trailer '$key: $format' ($POLICY_HINT)"
  elif [[ ! "$value" =~ $pattern ]]; then
    add_problem "$where: trailer '$key: $value' must be '$key: $format'"
  fi
}

check_commit() {
  local sha="$1" where key
  where="$(git log -1 --format='%h "%s"' "$sha")"
  check_trailer "$where" "$sha" Assisted-by "$ASSISTED_BY_PATTERN" "<claude-code|codex|antigravity|gemini-cli> <model>"
  check_trailer "$where" "$sha" Plan "$PLAN_PATTERN" "<NN|none>"
  check_trailer "$where" "$sha" Task "$TASK_PATTERN" "<N|review|none>"
  for key in $FORBIDDEN_TRAILERS; do
    if [[ -n "$(trailer "$sha" "$key")" ]]; then
      add_problem "$where: agents never add '$key' ($POLICY_HINT)"
    fi
  done
}

main() {
  local base="${1:-main}" sha count=0
  require_cmd git
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base branch '$base' not found"
  check_worktree_config
  check_branch "$base"
  for sha in $(git rev-list --reverse --no-merges "$base..HEAD"); do
    check_commit "$sha"
    count=$((count + 1))
  done
  if [[ -n "$PROBLEMS" ]]; then
    printf 'git policy violations:\n%s' "$PROBLEMS" >&2
    exit 1
  fi
  log "OK: git policy ($count commits since $base)"
}

main "$@"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 51 tests).

- [ ] **Step 5: Makefile에 `check-git` 추가**

`.PHONY`에 `check-git`을 추가하고, 파일 끝에 다음을 붙인다.
```make
check-git: ## Check the git policy for the current branch (name, commit trailers, worktree config)
	scripts/check-git.sh
```

- [ ] **Step 6: 실제 브랜치로 확인**

Run: `make check-git` (이 계획의 worktree에서)
Expected: `OK: git policy (<n> commits since main)`. 이 계획의 커밋이 모두 트레일러를 달았기 때문이다.

- [ ] **Step 7: Commit**

Run: `make check` (PASS)
```bash
git add scripts/check-git.sh tests/check_git.bats Makefile
git commit -m "feat: add git policy check for branch names and commit trailers" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: 1"
```

---

### Task 2: 읽기 전용 리뷰 실행기 (`review.sh`)

**Files:**
- Create: `scripts/review.sh`, `tests/stubs/codex`, `tests/stubs/claude`
- Modify: `Makefile`(`review` 타깃, `REVIEW_BASE`·`REVIEW_ALLOW_SAME_VENDOR` export)
- Test: `tests/review.bats`

**Interfaces:**
- Consumes: `common.sh`의 `log`, `step`, `die`, `require_cmd`
- Produces:
  - CLI: `scripts/review.sh BRANCH codex|claude [ROUND]`. 환경변수:
    - `REVIEW_BASE`(기본 `main`. 2차는 리뷰한 head SHA)
    - `REVIEW_ALLOW_SAME_VENDOR=1`(같은 벤더 리뷰를 경고와 함께 허용)
    - 테스트용 `REVIEW_OUT_DIR`, `REVIEW_WORKTREE_PARENT`
  - 출력: `.review-out/<branch-slug>-r<ROUND>-<reviewer>-diff.md`(변경 리뷰), `...-plan.md`(계획 대조 리뷰). `branch-slug`는 `/`를 `-`로 바꾼 브랜치 이름이다.
  - 리뷰어 명령:
    - codex: `codex exec review --base <base>`, `codex exec --sandbox read-only -o <file> "<prompt>"`
    - claude: `claude -p --permission-mode plan --no-session-persistence "/code-review <base>...HEAD"`, `claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence "<prompt>"`
  - stub 규약:
    - `codex`: `codex <args> :: cwd=<dir>`를 기록한다. `-o FILE`이 있으면 FILE에 `codex plan review`를 쓰고, 없으면 `codex diff review`를 출력한다. `CODEX_STUB_EXIT`를 설정하면 실패한다.
    - `claude`: `claude <args> :: cwd=<dir>`를 기록하고 `claude review`를 출력한다. `CLAUDE_STUB_EXIT`를 설정하면 실패한다.

**Assumption:** 실제 `codex exec review`는 결과를 stdout으로 내고, `claude -p`는 `--permission-mode plan`에서 `/code-review`를 실행한다. 이 계획의 마무리 단계에서 실제 리뷰로 확인하고, 다르면 `work/` 브랜치로 고친다.

- [ ] **Step 1: stub 작성 (실행 권한 부여)**

`tests/stubs/codex`:
```bash
#!/usr/bin/env bash
# Test stub for codex: logs "codex <args> :: cwd=<dir>". With -o FILE it writes a plan review to FILE,
# otherwise it prints a diff review. CODEX_STUB_EXIT=<n> makes every call fail.
set -euo pipefail
printf 'codex %s :: cwd=%s\n' "$*" "$PWD" >>"$STUB_LOG"
if [[ -n "${CODEX_STUB_EXIT:-}" ]]; then
  echo "codex stub: simulated failure" >&2
  exit "$CODEX_STUB_EXIT"
fi
out=""
while (($#)); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
if [[ -n "$out" ]]; then
  echo "codex plan review" >"$out"
else
  echo "codex diff review"
fi
```

`tests/stubs/claude`:
```bash
#!/usr/bin/env bash
# Test stub for claude: logs "claude <args> :: cwd=<dir>" and prints a review.
# CLAUDE_STUB_EXIT=<n> makes every call fail.
set -euo pipefail
printf 'claude %s :: cwd=%s\n' "$*" "$PWD" >>"$STUB_LOG"
if [[ -n "${CLAUDE_STUB_EXIT:-}" ]]; then
  echo "claude stub: simulated failure" >&2
  exit "$CLAUDE_STUB_EXIT"
fi
echo "claude review"
```

- [ ] **Step 2: 실패하는 테스트 작성 (`tests/review.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs codex claude
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  cd "$WORK"
  git config user.email agent@example.com
  git config user.name agent
  git commit -q --allow-empty -m "chore: init"
  git switch -q -c plan/02-git-review-tooling
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out" REVIEW_WORKTREE_PARENT="$BATS_TEST_TMPDIR/wt"
  REVIEW="$REPO_DIR/scripts/review.sh"
  OUT="$REVIEW_OUT_DIR/plan-02-git-review-tooling"
}

# author_commit TOOL: a commit authored by TOOL (claude-code, codex, ...).
author_commit() {
  git commit -q --allow-empty -m "feat: change by $1" \
    --trailer "Assisted-by: $1 model-x" --trailer "Plan: 02" --trailer "Task: 1"
}

worktree_count() {
  git worktree list | wc -l | tr -d ' '
}

@test "codex reviews a claude-authored branch in a detached worktree and writes both reports" {
  author_commit claude-code
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_success
  run cat "$OUT-r1-codex-diff.md"
  assert_output "codex diff review"
  run cat "$OUT-r1-codex-plan.md"
  assert_output "codex plan review"
  run grep -F "codex exec review --base main :: cwd=$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1" "$STUB_LOG"
  assert_success
  run grep -F "codex exec --sandbox read-only -o $OUT-r1-codex-plan.md" "$STUB_LOG"
  assert_success
  run worktree_count
  assert_output 1
}

@test "claude reviews a codex-authored branch with the read-only reviewer agent" {
  author_commit codex
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  run grep -F "claude -p --permission-mode plan --no-session-persistence /code-review main...HEAD" "$STUB_LOG"
  assert_success
  run grep -F -- "-p --agent branch-reviewer --permission-mode plan --no-session-persistence" "$STUB_LOG"
  assert_success
  run cat "$OUT-r1-claude-plan.md"
  assert_output "claude review"
}

@test "refuses a reviewer from the same vendor as the author" {
  author_commit claude-code
  run "$REVIEW" plan/02-git-review-tooling claude
  assert_failure
  assert_output --partial "reviewer claude (claude-code) also authored commits on plan/02-git-review-tooling"
  run worktree_count
  assert_output 1
}

@test "allows a same-vendor review only when explicitly requested" {
  author_commit claude-code
  REVIEW_ALLOW_SAME_VENDOR=1 run "$REVIEW" plan/02-git-review-tooling claude
  assert_success
  assert_output --partial "WARNING: claude-code also authored commits"
}

@test "round 2 reviews only commits after the reviewed head and leaves no temporary branch" {
  author_commit codex
  local reviewed
  reviewed="$(git rev-parse HEAD)"
  author_commit codex
  REVIEW_BASE="$reviewed" run "$REVIEW" plan/02-git-review-tooling claude 2
  assert_success
  run grep -F "/code-review review-base/plan-02-git-review-tooling-r2...HEAD" "$STUB_LOG"
  assert_success
  run test -f "$OUT-r2-claude-diff.md"
  assert_success
  run git branch --list 'review-base/*'
  assert_output ""
}

@test "removes the worktree even when the reviewer fails" {
  author_commit claude-code
  CODEX_STUB_EXIT=1 run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "codex change review failed"
  run worktree_count
  assert_output 1
}

@test "refuses to reuse a stale review worktree and leaves it alone" {
  author_commit claude-code
  mkdir -p "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  run "$REVIEW" plan/02-git-review-tooling codex
  assert_failure
  assert_output --partial "a review worktree already exists"
  run test -d "$REVIEW_WORKTREE_PARENT/review-plan-02-git-review-tooling-r1"
  assert_success
}

@test "rejects an unknown reviewer" {
  run "$REVIEW" plan/02-git-review-tooling gemini
  assert_failure
  assert_output --partial "usage: make review BRANCH="
}

@test "rejects a branch that does not exist" {
  run "$REVIEW" plan/09-nope codex
  assert_failure
  assert_output --partial "branch 'plan/09-nope' not found"
}
```

- [ ] **Step 3: 실패 확인**

Run: `make test`
Expected: FAIL. `review.bats` 9개가 `scripts/review.sh: No such file or directory`로 실패한다.

- [ ] **Step 4: `scripts/review.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Run an independent, read-only agent review of a branch in a throwaway detached worktree
# (docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, section 5). Writes two reports:
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-diff.md   bugs introduced since the base
#   <out>/<branch-slug>-r<ROUND>-<reviewer>-plan.md   plan conformance per AGENTS.md Code Review Rules
# Usage: review.sh BRANCH codex|claude [ROUND]
#   REVIEW_BASE=<ref>            base for the review (default main; the reviewed head for round 2)
#   REVIEW_ALLOW_SAME_VENDOR=1   allow a reviewer from the author's vendor (prints a warning)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
readonly OUT_DIR="${REVIEW_OUT_DIR:-$MAIN_ROOT/.review-out}"
readonly WORKTREE_PARENT="${REVIEW_WORKTREE_PARENT:-$(dirname "$MAIN_ROOT")/$(basename "$MAIN_ROOT")-wt}"
readonly BASE_REF="${REVIEW_BASE:-main}"

BRANCH=""
REVIEWER=""
BASE_BRANCH=""
TEMP_BASE=""
WT=""

usage() {
  die "usage: make review BRANCH=<plan/NN-slug|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<reviewed head>]"
}

# shellcheck disable=SC2317  # invoked via trap
cleanup() {
  local exit_code=$?
  if [[ -n "$WT" ]] && ! git worktree remove --force "$WT" >/dev/null 2>&1; then
    log "WARNING: could not remove the review worktree; run: git worktree remove --force $WT"
  fi
  if [[ -n "$TEMP_BASE" ]] && ! git branch -D "$TEMP_BASE" >/dev/null 2>&1; then
    log "WARNING: could not delete the temporary branch $TEMP_BASE"
  fi
  exit "$exit_code"
}

# reviewer_tool REVIEWER -> the Assisted-by tool name of that reviewer's vendor.
reviewer_tool() {
  case "$1" in
    codex) echo codex ;;
    claude) echo claude-code ;;
    *) usage ;;
  esac
}

check_independence() {
  local tool author authors same=""
  tool="$(reviewer_tool "$REVIEWER")" || exit 1
  authors="$(git log --no-merges --format='%(trailers:key=Assisted-by,valueonly)' "$BASE_REF..$BRANCH" \
    | awk 'NF { print $1 }' | sort -u | tr '\n' ' ')"
  for author in $authors; do
    if [[ "$author" == "$tool" ]]; then
      same=1
    fi
  done
  [[ -n "$same" ]] || return 0
  if [[ "${REVIEW_ALLOW_SAME_VENDOR:-}" == 1 ]]; then
    log "WARNING: $tool also authored commits on $BRANCH; same-vendor review allowed by REVIEW_ALLOW_SAME_VENDOR=1"
    return 0
  fi
  die "reviewer $REVIEWER ($tool) also authored commits on $BRANCH (authors: $authors); use the other reviewer, or set REVIEW_ALLOW_SAME_VENDOR=1 if no other vendor is available"
}

# prepare_base SLUG ROUND: sets BASE_BRANCH; codex needs a branch name, so a SHA gets a temporary branch.
prepare_base() {
  if git show-ref --verify --quiet "refs/heads/$BASE_REF"; then
    BASE_BRANCH="$BASE_REF"
    return 0
  fi
  git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || die "REVIEW_BASE '$BASE_REF' is not a branch or commit"
  TEMP_BASE="review-base/$1-r$2"
  git branch "$TEMP_BASE" "$BASE_REF"
  BASE_BRANCH="$TEMP_BASE"
}

plan_prompt() {
  cat <<EOF
Review branch $BRANCH: the changes since $BASE_BRANCH (git diff $BASE_BRANCH...HEAD, git log $BASE_BRANCH..HEAD).
Find the plan in docs/plans/ named by the commits' Plan trailer and check the changes against the
"Code Review Rules" in AGENTS.md. Read-only: do not modify, create or delete files and do not commit.
Answer with one line "Verdict: mergeable" or "Verdict: blocked (<n> P0/P1)", then one finding per line:
[P0|P1|P2|P3] path:line - failure scenario - suggested fix
Report only problems introduced by these changes.
EOF
}

run_codex() {
  local diff_out="$1" plan_out="$2"
  (cd "$WT" && codex exec review --base "$BASE_BRANCH") >"$diff_out" || die "codex change review failed; see $diff_out"
  (cd "$WT" && codex exec --sandbox read-only -o "$plan_out" "$(plan_prompt)") >/dev/null \
    || die "codex plan review failed"
}

run_claude() {
  local diff_out="$1" plan_out="$2"
  (cd "$WT" && claude -p --permission-mode plan --no-session-persistence "/code-review $BASE_BRANCH...HEAD") \
    >"$diff_out" || die "claude change review failed; see $diff_out"
  (cd "$WT" && claude -p --agent branch-reviewer --permission-mode plan --no-session-persistence "$(plan_prompt)") \
    >"$plan_out" || die "claude plan review failed; see $plan_out"
}

main() {
  local round slug wt_path diff_out plan_out
  [[ $# -ge 2 ]] || usage
  BRANCH="$1"
  REVIEWER="$2"
  round="${3:-1}"
  [[ "$round" =~ ^[0-9]+$ ]] || usage
  reviewer_tool "$REVIEWER" >/dev/null
  require_cmd git "$REVIEWER"
  git show-ref --verify --quiet "refs/heads/$BRANCH" || die "branch '$BRANCH' not found"
  check_independence

  slug="${BRANCH//\//-}"
  wt_path="$WORKTREE_PARENT/review-$slug-r$round"
  [[ ! -e "$wt_path" ]] \
    || die "a review worktree already exists at $wt_path; if no review is running, remove it: git worktree remove --force $wt_path"
  mkdir -p "$OUT_DIR" "$WORKTREE_PARENT"
  trap cleanup EXIT
  prepare_base "$slug" "$round"

  step "create a read-only review worktree for $BRANCH"
  git worktree add --quiet --detach "$wt_path" "$BRANCH" || die "could not create the review worktree at $wt_path"
  WT="$wt_path"

  diff_out="$OUT_DIR/$slug-r$round-$REVIEWER-diff.md"
  plan_out="$OUT_DIR/$slug-r$round-$REVIEWER-plan.md"
  step "$REVIEWER review of $BRANCH against $BASE_BRANCH (round $round)"
  if [[ "$REVIEWER" == codex ]]; then
    run_codex "$diff_out" "$plan_out"
  else
    run_claude "$diff_out" "$plan_out"
  fi
  log "reviews written: $diff_out and $plan_out"
  log "Next: verify each finding, then record them in docs/reviews/$slug.md (format: docs/reviews/README.md)"
}

main "$@"
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 60 tests).

- [ ] **Step 6: Makefile에 `review` 추가**

`.PHONY`에 `review`를 추가하고, `export BM_VM_HOST ...` 줄 아래에 다음 줄을 추가한다.
```make
export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR
```
파일 끝에 다음을 붙인다.
```make
review: ## Read-only review by another vendor: BRANCH=<branch> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<sha>]
	scripts/review.sh "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"
```

- [ ] **Step 7: Commit**

Run: `make check` (PASS)
```bash
git add scripts/review.sh tests/stubs/codex tests/stubs/claude tests/review.bats Makefile
git commit -m "feat: add read-only cross-vendor review runner" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: 2"
```

---

### Task 3: 리뷰어 에이전트, 스킬, 리뷰 규칙

**Files:**
- Create: `.claude/agents/branch-reviewer.md`
- Create: `.agents/skills/git-workflow/SKILL.md`, `.agents/skills/branch-review/SKILL.md`
- Create (symlink): `.claude/skills/git-workflow`, `.claude/skills/branch-review`
- Create: `docs/reviews/README.md`
- Modify: `AGENTS.md`(`Code Review Rules`, `Skills`, `Map`), `.claude/settings.json`(`make check-git` 허용)
- Test: `tests/repo.bats`(스킬 구조 테스트, 리뷰 규칙·리뷰어 테스트 추가)

**Interfaces:**
- Consumes: Task 1·2의 `make check-git`, `make review`
- Produces:
  - 스킬 이름 `git-workflow`, `branch-review`와 Claude 서브에이전트 `branch-reviewer`(`review.sh`의 `--agent branch-reviewer`가 사용)
  - 스킬 구조 테스트 5개. [docs-skills 계획](plan-2026-10-07-hydaxf15-docs-skills.md)의 `bm-*` 스킬도 이 테스트를 그대로 받는다.
  - `AGENTS.md`의 `## Code Review Rules`(Codex 리뷰가 자동으로 읽음)와 `## Skills` 섹션. [docs-skills 계획](plan-2026-10-07-hydaxf15-docs-skills.md)이 `bm-*` 줄을 추가한다.

- [ ] **Step 1: 실패하는 테스트 추가 (`tests/repo.bats` 끝에 append)**

```bash
skill_dirs() {
  find "$REPO_DIR/.agents/skills" -mindepth 1 -maxdepth 1 -type d | sort
}

frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1"
}

@test "at least one repository skill exists" {
  run skill_dirs
  assert_success
  refute_output ""
}

@test "skills use only Agent Skills standard frontmatter keys" {
  local dir key bad=""
  for dir in $(skill_dirs); do
    for key in $(frontmatter "$dir/SKILL.md" | grep -oE '^[a-z-]+:' | tr -d ':'); do
      case "$key" in
        name | description | license | compatibility | metadata | allowed-tools) ;;
        *) bad="$bad $(basename "$dir"):$key" ;;
      esac
    done
  done
  [[ -z "$bad" ]] || fail "non-standard frontmatter keys (Codex/Antigravity may reject them):$bad"
}

@test "skill names match their directories and have descriptions" {
  local dir name
  for dir in $(skill_dirs); do
    name="$(frontmatter "$dir/SKILL.md" | sed -n 's/^name: *//p')"
    [[ "$name" == "$(basename "$dir")" ]] || fail "$dir/SKILL.md: name '$name' must equal the directory name"
    frontmatter "$dir/SKILL.md" | grep -qE '^description: .+' || fail "$dir/SKILL.md: add a description"
  done
}

@test "every skill is linked for Claude Code under .claude/skills" {
  local dir name link
  for dir in $(skill_dirs); do
    name="$(basename "$dir")"
    link="$REPO_DIR/.claude/skills/$name"
    [[ -L "$link" ]] || fail "missing link; run: ln -s ../../.agents/skills/$name .claude/skills/$name"
    [[ "$(readlink "$link")" == "../../.agents/skills/$name" ]] || fail "$link must point to ../../.agents/skills/$name"
  done
}

@test "every SKILL.md is at most 500 lines" {
  local dir lines
  for dir in $(skill_dirs); do
    lines="$(wc -l <"$dir/SKILL.md")"
    ((lines <= 500)) || fail "$dir/SKILL.md has $lines lines; move reference material into separate files"
  done
}

@test "AGENTS.md defines the Code Review Rules that Codex reads" {
  run grep -x '## Code Review Rules' "$REPO_DIR/AGENTS.md"
  assert_success
  run grep -E 'P0.*P1.*block the merge' "$REPO_DIR/AGENTS.md"
  assert_success
}

@test "the Claude reviewer agent cannot edit files" {
  local agent="$REPO_DIR/.claude/agents/branch-reviewer.md"
  run frontmatter "$agent"
  assert_line "permissionMode: plan"
  assert_line --regexp '^disallowedTools: .*Write.*Edit'
  refute_line --regexp '^tools: .*(Write|Edit)'
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `at least one repository skill exists`, `AGENTS.md defines the Code Review Rules…`, `the Claude reviewer agent cannot edit files` 3개가 실패한다. 나머지 스킬 테스트 4개는 스킬이 아직 없어 검사할 대상이 없으므로 통과한다.

- [ ] **Step 3: Claude 리뷰어 에이전트 작성 (`.claude/agents/branch-reviewer.md`)**

```markdown
---
name: branch-reviewer
description: Independent read-only reviewer for plan/ and work/ branches in this repo. Use for plan-conformance reviews of branches written by Codex, Antigravity or Gemini, never for branches you wrote.
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, NotebookEdit
permissionMode: plan
---

Follow the `branch-review` skill (.agents/skills/branch-review/SKILL.md) and the Code Review Rules in AGENTS.md.
Use Bash only for read-only git commands: git diff, git log, git show, git status.
Never edit, create or delete files, never commit, never switch branches.
```

- [ ] **Step 4: 스킬 작성**

`.agents/skills/git-workflow/SKILL.md`:
````markdown
---
name: git-workflow
description: Start, commit, hand off for review and prepare the merge of agent work in this repo (plan/NN-slug or work/slug branches in their own worktree, commit trailers, review fixes). Use whenever you are about to change files or commit here.
---

# Agent git workflow

Policy: docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md. Never commit to `main`, force-push, rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.

## Start

1. Set your identity once: `export AGENT_ID="<claude-code|codex|antigravity|gemini-cli> <model id>"`.
2. Work in your own worktree on your own branch: one agent per worktree, one worktree per branch, never the main checkout.
   - Claude Code: start with `claude --worktree <slug>` (or enter a worktree in the session), then `git branch -m plan/NN-slug` or `git branch -m work/slug`.
   - Other tools: `git worktree add ../027_agent_share_poc-wt/<slug> -b plan/NN-slug main`, then work in that directory.
3. For a plan, make the first commit move the plan file from `docs/plans/backlog/` to `docs/plans/active/`.

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: <NN|none>" --trailer "Task: <N|review|none>"`
3. Never add `Co-authored-by` or `Signed-off-by`.
4. Before asking for review, `make check-git` must pass.

## Hand off for review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`).
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex`
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
3. Copy the findings from `.review-out/` into `docs/reviews/<branch-slug>.md` using `docs/reviews/README.md`, and commit with `Task: review`.

## Fix findings

1. Verify each finding before acting: reproduce it or cite the code. Mark unfounded ones `rejected <evidence>`.
2. Fix accepted findings one commit each, with `--trailer "Review-Finding: R<round>-F<n>"`, and set their status to `fixed <sha>`.
3. If anything changed, run round 2 on the new commits only: `make review BRANCH=<branch> REVIEWER=<same> ROUND=2 REVIEW_BASE=<reviewed head sha>`. After round 2, leave any remaining disagreement to the human.

## Prepare the merge (only the human merges)

1. Check: no open P0/P1, every deferred P2 carries the human's reason, `make check` and `make check-git` pass.
2. Write the merge message to `.review-out/merge-<branch-slug>.txt` in your worktree:

   ```
   Merge <branch>

   Reviewed-by: <human>
   Review-Agent: <reviewer tool> <model>
   Review-Record: docs/reviews/<branch-slug>.md
   Reviewed-Head: <reviewed head sha>
   ```

3. Ask the human to run, from the main checkout: `git merge --no-ff <branch> -F <absolute path of that file>`, then `git worktree remove <your worktree>` and `git branch -d <branch>`.
````

`.agents/skills/branch-review/SKILL.md`:
```markdown
---
name: branch-review
description: Review another agent's plan/ or work/ branch in this repo as an independent, read-only reviewer (plan conformance, bugs, security, trailers) and report P0-P3 findings. Use when asked to review a branch or when make review runs you.
---

# Review a branch (read-only)

You review; you never fix. Do not edit, create or delete files, commit, or switch branches. If your vendor also authored commits on the branch (see their `Assisted-by` trailers), stop and say so.

## Scope

- Changes: `git diff <base>...HEAD`; commits: `git log <base>..HEAD`.
- The plan: the file in `docs/plans/` named by the commits' `Plan` trailer.
- Round 2: only commits after the previously reviewed head. Confirm earlier findings are closed and report only new P0/P1.

## Checklist (AGENTS.md, Code Review Rules)

1. Every task of the plan is implemented and its verification passed with evidence (command and result).
2. No changes outside the plan's scope.
3. `make check` and `make check-git` pass.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by AGENTS.md are updated.
6. Every commit carries `Assisted-by`, `Plan` and `Task` trailers.

## Severity

| Level | Meaning | Merge |
|---|---|---|
| P0 | data loss, security, outage | blocks |
| P1 | bug or unmet requirement | blocks |
| P2 | maintainability | fix or human-deferred |
| P3 | minor | optional |

## Output

First line: `Verdict: mergeable` or `Verdict: blocked (<n> P0/P1)`.
Then one finding per line: `[P1] scripts/restore.sh:42 - <failure scenario> - <suggested fix>`.
Report only problems these changes introduce. No style nits, no speculation without a concrete scenario, always cite path:line.
```

- [ ] **Step 5: 링크와 리뷰 기록 템플릿 작성**

Run:
```bash
mkdir -p .claude/skills
ln -s ../../.agents/skills/git-workflow .claude/skills/git-workflow
ln -s ../../.agents/skills/branch-review .claude/skills/branch-review
```

`docs/reviews/README.md`:
`````markdown
# Review records

One file per reviewed branch: `docs/reviews/<branch-slug>.md`, for example `rev-2026-10-08-tscgvpsz-git-review-tooling.md`. The author agent writes it from the raw reviewer output in `.review-out/` and commits it with `Task: review`. Policy: `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5.

## Template

````markdown
# Review: plan/NN-slug

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex <model> | <base sha> | <head sha> | blocked (1 P1) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/example.sh:42 | <failure scenario> | fixed <sha> |
````

Status values: `open`, `fixed <sha>`, `rejected <evidence>`, `deferred <human's reason>`.
`````

- [ ] **Step 6: `AGENTS.md`와 `.claude/settings.json` 갱신**

`## Map`의 마지막 줄 뒤에 다음을 추가한다.
```markdown
- `.agents/skills/` skills for Codex and Antigravity; `.claude/skills/<name>` symlinks and `.claude/agents/branch-reviewer.md` for Claude Code.
- `docs/reviews/` review records (template in its README).
```

파일 끝에 다음 두 섹션을 추가한다.
```markdown
## Code Review Rules
Reviewers check only the changes since the base (Codex reads this section; Claude uses the `branch-review` skill):
1. Every task of the plan is implemented and its verification passed with evidence.
2. No changes outside the plan's scope.
3. `make check` and `make check-git` pass.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by this file are updated.
6. Every commit carries the Git trailers.
Severity: P0 data loss, security or outage and P1 bug or unmet requirement block the merge; P2 maintainability is fixed or deferred by the human with a reason; P3 is optional.
Each finding: `[Pn] path:line - failure scenario - suggested fix`. Report only problems these changes introduce; no style nits.

## Skills
- `git-workflow`: start, commit, request review and prepare the merge of agent work.
- `branch-review`: review another agent's branch read-only.
```

`.claude/settings.json`의 `allow` 목록에 `"Bash(make check-git)"`를 추가한다.

- [ ] **Step 7: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 67 tests).

- [ ] **Step 8: Commit**

Run: `make check` (PASS)
```bash
git add .claude/agents .claude/skills .claude/settings.json .agents docs/reviews AGENTS.md tests/repo.bats
git commit -m "docs: add reviewer agent, git and review skills, and code review rules" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: 3"
```

---

### 마무리: 리뷰, 기록, 병합

이 계획부터는 방금 만든 도구로 리뷰한다. 실제 리뷰가 Task 2의 Assumption(실제 CLI 출력과 읽기 전용 동작)을 함께 확인한다.

- [ ] `make check`와 `make check-git`이 PASS하는지 확인한다.
- [ ] Progress log에 결과(테스트 수, 커버리지 %, 특이사항)를 `Verified`로 기록하고, 이 계획 파일을 `completed/`로 옮긴다.

```bash
git mv docs/plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md docs/plans/completed/
git commit -m "docs: complete the git-review-tooling plan" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: none"
```

- [ ] 1차 리뷰(작성자와 다른 벤더): 작성 도구가 Claude Code면 `make review BRANCH=plan/qq4h1djv-git-review-tooling REVIEWER=codex`, 그 밖이면 `REVIEWER=claude`. 사용량이 드는 작업이므로 실행 전에 사용자에게 알린다.
  **Assumption 확인:** 두 원문 파일이 실제 리뷰 내용을 담았는지, 리뷰 뒤 `git status`가 깨끗하고 `git worktree list`에 리뷰 worktree가 남지 않았는지 확인한다. 어긋나면 그 내용을 리뷰 기록에 P1로 적고 고친다.
- [ ] 원문을 `docs/reviews/rev-2026-10-08-tscgvpsz-git-review-tooling.md`로 옮겨 적고(`docs/reviews/README.md` 형식) 커밋한다.

```bash
git add docs/reviews/rev-2026-10-08-tscgvpsz-git-review-tooling.md
git commit -m "docs: record review of the git-review-tooling plan" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: qq4h1djv" --trailer "Task: review"
```

- [ ] 지적마다 재현하거나 근거를 인용해 검증하고, 받아들인 지적은 하나당 커밋 하나로 고친다(`--trailer "Review-Finding: R1-F<n>"`). 거절은 근거와 함께 기록한다.
- [ ] 고친 것이 있으면 2차 리뷰: `make review BRANCH=plan/qq4h1djv-git-review-tooling REVIEWER=<같은 리뷰어> ROUND=2 REVIEW_BASE=<리뷰한 head>`. 2회차 뒤 남은 이견은 사람이 결정한다.
- [ ] `git-workflow` 스킬의 "Prepare the merge"대로 `.review-out/merge-plan-02-git-review-tooling.txt`를 쓰고, 사람에게 병합을 요청한다. 사람은 `main` 체크아웃에서 `git merge --no-ff plan/qq4h1djv-git-review-tooling -F <그 파일의 절대 경로>`를 실행한다.
- [ ] 병합 뒤 worktree와 브랜치를 정리한다: `git worktree remove <경로>` → `git branch -d plan/qq4h1djv-git-review-tooling`

---

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-07 | Verified | 로컬 codex-cli 0.160.1: `codex exec review`에 `--base`/`--commit`/`--uncommitted`/PROMPT, `codex exec`에 `-s/--sandbox`, `-o/--output-last-message` 옵션이 있음 (`--help`) |
| 2026-10-07 | Verified | 로컬 Claude Code 2.1.292: `--agent`, `--permission-mode`, `--no-session-persistence`, `--disallowedTools` 옵션이 있음 (`--help`) |
| 2026-10-07 | Verified | Claude Code `attribution.commit`은 `""` 또는 `false`면 트레일러를 넣지 않음 (code.claude.com/docs/en/settings-reference) |
