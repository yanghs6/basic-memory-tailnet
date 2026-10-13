# znbc3ase Review Posting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 다른 벤더 리뷰의 원문과 지적 기록을 PR 코멘트로 올리는 일을 Make 타깃으로 만든다. [github-switch 계획](plan-2026-10-13-k93wjt1a-github-switch.md)의 임시 절차(`gh pr comment`를 손으로 실행)를 대체하고, 리뷰 관련 문서(스킬, AGENTS.md, `docs/reviews/README.md`)를 PR 기준으로 맞춘다.

**Architecture:**
- `scripts/review.sh`는 리뷰한 시점의 base와 head SHA를 `<slug>-r<round>-<reviewer>-meta.txt`에 남긴다.
- `scripts/post-review.sh`(새 파일)는 그 회차의 diff 리포트와 plan 리포트를 PR 코멘트 두 개로 올린다. 코멘트 머리에는 회차, 리뷰어, 모델, SHA를 적는다.
- `scripts/review-record.sh`(새 파일)는 표식(`<!-- review-record -->`)으로 PR의 "Review record" 코멘트 하나를 찾는다. 없으면 만들고, 하나면 고치고, 여럿이면 멈춘다.
- 두 스크립트는 `gh`만 쓰고, 테스트는 `tests/stubs/gh`로 검증한다.

**Tech Stack:** bash 3.2 호환 셸, bats-core 1.14.0 + bats-assert, `gh` CLI(`gh pr comment`, `gh api --paginate --jq`)

**Spec:** `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md` (8절)

**Sequence:** 전제:
- [github-switch 계획](plan-2026-10-13-k93wjt1a-github-switch.md)이 병합됐다.
- 사람이 `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md` 4절의 저장소 설정과 ruleset을 적용했다.
- 이 계획은 새 흐름(머신 계정의 초안 PR, CI, 사람의 squash 병합)으로 진행하는 첫 계획이다.

## Global Constraints

- AGENTS.md 스크립트 규칙을 따른다: `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`, `scripts/lib/common.sh` source, `die`. macOS bash 3.2에서 돌아야 하고, `x="$(fn)"` 뒤에는 `|| exit 1`을 붙인다.
- 테스트를 먼저 쓴다. [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md)을 따라 대표 성공 경로, 조용히 넘어가거나 반쪽으로 끝날 실패 경로만 쓴다. 문구만 보는 테스트와 usage 테스트는 쓰지 않는다.
- "never weaken a test to make it pass." `tests/review.bats`는 assertion을 더하거나, 바뀐 동작(리포트 파일 목록)에 맞춰 기대값을 고치기만 한다.
- `gh` 호출은 토큰을 출력하지 않는다. 비밀값을 로그에 남기지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: znbc3ase`, `Task: <N|review|none>`. PR 본문 마지막 문단은 `Assisted-by`와 `Plan: znbc3ase`다.
- 리뷰 원문과 기록에도 VM의 외부 IP와 Tailscale IP를 적지 않는다.
- 쓰기 대상: 아래 File Structure의 파일만 바꾼다.

## Review Focus

1. **리뷰 뒤에 커밋이 더 올라온 상태에서 게시함.** 이때 코멘트의 "reviewed head"가 실제로 리뷰한 커밋과 달라진다. → head는 게시 시점이 아니라 `review.sh`가 리뷰 시점에 남긴 값을 쓴다. Task 1 Step 1이 meta 파일 내용을 검사한다.
2. **한 회차를 반만 게시함.** 예: diff 코멘트는 올라갔는데 plan 코멘트가 길이 제한에 걸림. → 두 본문의 크기를 모두 확인한 뒤에 게시한다. Task 1 Step 1의 "too long" 테스트가 gh 호출 0번을 확인한다.
3. **Review record 코멘트가 둘 생기거나 엉뚱한 코멘트를 고침.** → 표식으로 찾고, 여러 개면 멈춘다. Task 2 Step 1이 세 경우(0개, 1개, 2개)를 검사한다.
4. **코멘트가 30개를 넘는 PR에서 Review record를 못 찾아 새로 만듦.** → `gh api --paginate`로 모든 페이지를 읽는다. 스텁으로는 페이지 나눔을 재현할 수 없으므로 Task 4에서 실제 PR로 확인한다.
5. **한국어 리포트는 글자당 3바이트라서, 실제로는 GitHub 제한(65536자) 안인데 바이트 기준으로 거부될 수 있음.** → 거부 메시지가 줄인 사본을 `gh pr comment`로 올리라고 안내한다. 조용히 잘리지는 않는다.

## File Structure

```
scripts/review.sh  tests/review.bats  scripts/post-review.sh (새 파일)  tests/post_review.bats (새 파일)
tests/stubs/gh (새 파일)  Makefile(review-post, REVIEW_MODEL)                                       Task 1
scripts/review-record.sh (새 파일)  tests/review_record.bats (새 파일)  Makefile(review-record)      Task 2
.agents/skills/git-workflow/references/review-and-merge.md  .agents/skills/branch-review/SKILL.md
AGENTS.md(Code Review Rules 3, 6)  docs/reviews/README.md  docs/ARCHITECTURE.md:30
docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md(14절 3·4번)                                       Task 3
이 계획 파일(Progress log)                                                                          시작, Task 4, 마무리
```

---

### 시작: 브랜치, github-switch 계획의 남은 확인, 초안 PR

- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/znbc3ase-review-posting`을 만든다(git-workflow 스킬).
- [ ] 계획 파일을 `docs/plans/active/`로 옮기고, Progress log에 [github-switch 계획](plan-2026-10-13-k93wjt1a-github-switch.md) 마무리의 두 확인 결과를 적는다.
  - squash 커밋의 작성자와 `Co-authored-by` 자동 추가 여부(스펙 Open question 3). 명령은 `git log -1 --format='%an <%ae>%n%b' <github-switch 계획의 squash 커밋>`이다.
  - 저장소 단위 secret scanning과 push protection을 켤 수 있었는지(Open question 4)

```bash
git mv docs/plans/plan-2026-10-13-znbc3ase-review-posting.md docs/plans/plan-2026-10-13-znbc3ase-review-posting.md
git add docs/plans/plan-2026-10-13-znbc3ase-review-posting.md
git commit -m "docs: start the review-posting plan and record the github-switch plan follow-ups" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: znbc3ase" --trailer "Task: none"
git push -u origin plan/znbc3ase-review-posting
gh pr create --draft --base main --title "feat: post agent reviews and the review record to pull requests" --body-file <.github/pull_request_template.md를 채운 파일>
```

Expected: `pr-rules`가 pass한다(이 계획이 새 흐름의 첫 실사용). PR 번호를 Progress log에 적는다.

---

### Task 1: 리뷰 메타와 리포트 게시 (`post-review.sh`)

**Files:**
- Create: `scripts/post-review.sh`(실행 권한), `tests/post_review.bats`, `tests/stubs/gh`(실행 권한)
- Modify: `scripts/review.sh`(main 함수), `tests/review.bats:28-45`(첫 테스트), `Makefile`(export 줄, `.PHONY`, `review-post` 타깃)

**Interfaces:**
- Consumes: `review.sh`가 만드는 `$OUT_DIR/<slug>-r<round>-<reviewer>-{diff,plan}.md`. `slug`는 브랜치 이름의 `/`를 `-`로 바꾼 값이다.
- Produces:
  - `review.sh`가 `$OUT_DIR/<slug>-r<round>-<reviewer>-meta.txt`를 쓴다. 내용은 `base <sha>`와 `head <sha>` 두 줄이다.
  - `scripts/post-review.sh PR BRANCH codex|claude [ROUND]`. 환경변수는 `REVIEW_OUT_DIR`, `REVIEW_MODEL`이다.
  - `make review-post PR=<n> BRANCH=<b> REVIEWER=<r> [ROUND=1] [REVIEW_MODEL=<m>]`
  - `tests/stubs/gh`: 호출마다 `gh <args>`를 `$STUB_LOG`에 남긴다. `--body-file F`와 `-F body=@F`의 F 내용은 `$STUB_LOG.body`에 이어 붙인다. `--jq`가 있는 호출은 `$GH_STUB_JQ_OUTPUT`을 출력한다. `GH_STUB_EXIT`가 있으면 그 값으로 실패한다. Task 2가 이 스텁을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/review.bats`의 첫 테스트(`codex reviews a claude-authored branch ...`)에서 `run ls "$REVIEW_OUT_DIR"` 이하 네 줄을 다음으로 바꾼다. 파일 목록 기대값에 meta 파일이 늘고, meta 내용 검사가 추가된다.

```bash
  run ls "$REVIEW_OUT_DIR"
  assert_output "plan-02-git-review-tooling-r1-codex-diff.md
plan-02-git-review-tooling-r1-codex-meta.txt
plan-02-git-review-tooling-r1-codex-plan.md"
  run cat "$OUT-r1-codex-meta.txt"
  assert_line "base $(git rev-parse main)"
  assert_line "head $(git rev-parse plan/qq4h1djv-git-review-tooling)"
```

`tests/stubs/gh`:

```bash
#!/usr/bin/env bash
# Test stub for gh: logs "gh <args>" to $STUB_LOG and appends the text of every --body-file FILE and
# -F body=@FILE to $STUB_LOG.body. A call with --jq prints $GH_STUB_JQ_OUTPUT (default: nothing), standing in
# for the filtered API result. GH_STUB_EXIT=<n> makes every call fail.
set -euo pipefail
printf 'gh %s\n' "$*" >>"$STUB_LOG"
if [[ -n "${GH_STUB_EXIT:-}" ]]; then
  echo "gh stub: simulated failure" >&2
  exit "$GH_STUB_EXIT"
fi
jq_call=""
while (($#)); do
  case "$1" in
    --body-file)
      cat "$2" >>"$STUB_LOG.body"
      shift 2
      ;;
    -F)
      if [[ "$2" == body=@* ]]; then
        cat "${2#body=@}" >>"$STUB_LOG.body"
      fi
      shift 2
      ;;
    --jq)
      jq_call=1
      shift 2
      ;;
    *) shift ;;
  esac
done
if [[ -n "$jq_call" ]]; then
  printf '%s' "${GH_STUB_JQ_OUTPUT:-}"
fi
```

`tests/post_review.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  export REVIEW_OUT_DIR="$BATS_TEST_TMPDIR/out"
  mkdir -p "$REVIEW_OUT_DIR"
  POST="$REPO_DIR/scripts/post-review.sh"
  PREFIX="$REVIEW_OUT_DIR/plan-09-review-posting-r1-codex"
  echo "Verdict: mergeable" >"$PREFIX-diff.md"
  echo "Verdict: blocked (1 P0/P1)" >"$PREFIX-plan.md"
  printf 'base %s\nhead %s\n' 1111111 2222222 >"$PREFIX-meta.txt"
}

@test "posts the change and plan reviews as two PR comments headed by round, reviewer, model and the reviewed SHAs" {
  REVIEW_MODEL=gpt-6.1-sol run "$POST" 12 plan/09-review-posting codex
  assert_success
  run grep -c '^gh pr comment 12 --body-file ' "$STUB_LOG"
  assert_output 2
  run cat "$STUB_LOG.body"
  assert_line "## Agent review R1: codex (gpt-6.1-sol)"
  assert_line 'Base `1111111`, reviewed head `2222222`.'
  assert_line "### Change review"
  assert_line "Verdict: mergeable"
  assert_line "### Plan review"
  assert_line "Verdict: blocked (1 P0/P1)"
}

@test "posts nothing when a file of the round is missing" {
  rm "$PREFIX-plan.md"
  run "$POST" 12 plan/09-review-posting codex
  assert_failure
  assert_output --partial "missing $PREFIX-plan.md"
  run grep -c '^gh ' "$STUB_LOG"
  assert_output 0
}

@test "posts nothing when either report is too long for one GitHub comment" {
  head -c 70000 /dev/zero | tr '\0' x >"$PREFIX-plan.md"
  run "$POST" 12 plan/09-review-posting codex
  assert_failure
  assert_output --partial "over GitHub's 65536 limit"
  run grep -c '^gh ' "$STUB_LOG"
  assert_output 0
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL.
- `review.bats`의 첫 테스트가 파일 목록 비교에서 실패한다(meta 파일이 없음).
- `post_review.bats` 3개가 `scripts/post-review.sh: No such file or directory`로 실패한다.

- [ ] **Step 3: `scripts/review.sh` 수정**

`main()`의 `local` 줄에 `base_sha head_sha meta_out`을 더한다. `git worktree add ...` 다음 줄(`WT="$wt_path"` 뒤)에서 리뷰 시점의 SHA를 잡는다.

```bash
  base_sha="$(git rev-parse "$BASE_BRANCH")" || exit 1
  head_sha="$(git rev-parse "refs/heads/$BRANCH")" || exit 1
```

`plan_out=...` 다음 줄에 `meta_out="$OUT_DIR/$slug-r$round-$REVIEWER-meta.txt"`를 넣는다. `rm -f` 줄에도 `"$meta_out"`을 더한다. 두 리포트의 `mv` 다음에 meta를 쓰고, 안내 줄을 바꾼다.

```bash
  printf 'base %s\nhead %s\n' "$base_sha" "$head_sha" >"$meta_out"
  log "reviews written: $diff_out and $plan_out"
  log "Next: verify each finding, then make review-post PR=<number> BRANCH=$BRANCH REVIEWER=$REVIEWER ROUND=$round and make review-record PR=<number> FILE=<findings file>"
```

- [ ] **Step 4: `scripts/post-review.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Post one review round's raw reports to its pull request: one comment for the change review and one for the
# plan review (docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, section 8). make review writes the reports.
# Usage: post-review.sh PR BRANCH codex|claude [ROUND]
#   REVIEW_OUT_DIR=<dir>   where make review wrote the reports (default: the main checkout's .review-out)
#   REVIEW_MODEL=<model>   the reviewer's model for the comment header (default: "CLI default model")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
readonly OUT_DIR="${REVIEW_OUT_DIR:-$MAIN_ROOT/.review-out}"
# GitHub rejects comment bodies over 65536 characters; counting bytes keeps every accepted body under it.
readonly MAX_COMMENT_BYTES=65536

usage() {
  die "usage: make review-post PR=<number> BRANCH=<plan/NN-slug|work/slug> REVIEWER=codex|claude [ROUND=1] [REVIEW_MODEL=<model>]"
}

# write_comment FILE HEADER TITLE REPORT: FILE gets HEADER, a "### TITLE" heading and the text of REPORT.
write_comment() {
  printf '%s\n\n### %s\n\n' "$2" "$3" >"$1"
  cat "$4" >>"$1"
}

# check_size FILE WHAT: die when FILE is too long for one GitHub comment.
check_size() {
  local bytes
  bytes="$(wc -c <"$1" | tr -d ' ')" || exit 1
  ((bytes <= MAX_COMMENT_BYTES)) \
    || die "$2 is $bytes bytes, over GitHub's $MAX_COMMENT_BYTES limit for one comment; post a shortened copy with gh pr comment and say so in it"
}

main() {
  local pr branch reviewer round slug prefix file base head header change_body plan_body
  [[ $# -ge 3 ]] || usage
  pr="$1"
  branch="$2"
  reviewer="$3"
  round="${4:-1}"
  [[ "$pr" =~ ^[0-9]+$ && "$round" =~ ^[0-9]+$ ]] || usage
  case "$reviewer" in
    codex | claude) ;;
    *) usage ;;
  esac
  require_cmd git gh
  slug="${branch//\//-}"
  prefix="$OUT_DIR/$slug-r$round-$reviewer"
  for file in "$prefix-diff.md" "$prefix-plan.md" "$prefix-meta.txt"; do
    [[ -f "$file" ]] || die "missing $file: run make review BRANCH=$branch REVIEWER=$reviewer ROUND=$round first"
  done
  base="$(sed -n 's/^base //p' "$prefix-meta.txt")" || exit 1
  head="$(sed -n 's/^head //p' "$prefix-meta.txt")" || exit 1
  [[ -n "$base" && -n "$head" ]] || die "$prefix-meta.txt names no base or head; rerun make review"
  header="## Agent review R$round: $reviewer (${REVIEW_MODEL:-CLI default model})

Base \`$base\`, reviewed head \`$head\`."
  change_body="$prefix-diff.comment.md"
  plan_body="$prefix-plan.comment.md"
  write_comment "$change_body" "$header" "Change review" "$prefix-diff.md"
  write_comment "$plan_body" "$header" "Plan review" "$prefix-plan.md"
  # Check both before posting either, so a failure never leaves half a round on the pull request.
  check_size "$change_body" "the change review comment"
  check_size "$plan_body" "the plan review comment"
  gh pr comment "$pr" --body-file "$change_body" || die "gh pr comment failed for the change review of PR #$pr"
  gh pr comment "$pr" --body-file "$plan_body" || die "gh pr comment failed for the plan review of PR #$pr"
  rm -f "$change_body" "$plan_body"
  log "posted the R$round $reviewer change and plan reviews to PR #$pr"
}

main "$@"
```

- [ ] **Step 5: Makefile**

- `export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR` 줄을 `export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR REVIEW_MODEL`로 바꾼다.
- `.PHONY`에 `review-post`를 더한다.
- `review` 타깃 다음에 다음을 넣는다.

```make
review-post: ## Post a review round's reports to its PR: PR=<number> BRANCH=<branch> REVIEWER=codex|claude [ROUND=1] [REVIEW_MODEL=<model>]
	scripts/post-review.sh "$(PR)" "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"
```

- [ ] **Step 6: 통과 확인**

Run: `make check`
Expected:
- exit 0
- `review.bats` 전부와 `post_review.bats` 3개가 ok다.
- 커버리지 목록에 `post-review.sh`가 나온다.

- [ ] **Step 7: 커밋과 push**

```bash
git add scripts/review.sh scripts/post-review.sh tests/review.bats tests/post_review.bats tests/stubs/gh Makefile
git commit -m "feat: record the reviewed SHAs and post review reports to the pull request" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: znbc3ase" --trailer "Task: 1"
git push
```

### Task 2: Review record 코멘트 (`review-record.sh`)

**Files:**
- Create: `scripts/review-record.sh`(실행 권한), `tests/review_record.bats`
- Modify: `Makefile`(`.PHONY`, `review-record` 타깃)

**Interfaces:**
- Consumes: Task 1의 `tests/stubs/gh`(`GH_STUB_JQ_OUTPUT`, `$STUB_LOG.body`)
- Produces:
  - `scripts/review-record.sh PR FILE`. FILE은 `docs/reviews/README.md` 형식의 지적 표다.
  - `make review-record PR=<n> FILE=<path>`
  - 코멘트 첫 줄 표식: `<!-- review-record -->`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/review_record.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs gh
  RECORD="$REPO_DIR/scripts/review-record.sh"
  FINDINGS="$BATS_TEST_TMPDIR/findings.md"
  printf '| ID | Sev | Location | Summary | Status |\n|---|---|---|---|---|\n| R1-F1 | P1 | scripts/x.sh:1 | breaks | open |\n' >"$FINDINGS"
}

@test "creates the Review record when the PR has none, with the marker as its first line" {
  run "$RECORD" 12 "$FINDINGS"
  assert_success
  run grep -F 'gh api -X POST repos/{owner}/{repo}/issues/12/comments -F body=@' "$STUB_LOG"
  assert_success
  run head -n 1 "$STUB_LOG.body"
  assert_output "<!-- review-record -->"
  run grep -F '| R1-F1 | P1 |' "$STUB_LOG.body"
  assert_success
}

@test "updates the existing Review record instead of adding a second one" {
  GH_STUB_JQ_OUTPUT=4242 run "$RECORD" 12 "$FINDINGS"
  assert_success
  run grep -F 'gh api -X PATCH repos/{owner}/{repo}/issues/comments/4242 -F body=@' "$STUB_LOG"
  assert_success
  run grep -c 'POST' "$STUB_LOG"
  assert_output 0
}

@test "refuses to guess when the PR has several Review records" {
  GH_STUB_JQ_OUTPUT=$'1\n2' run "$RECORD" 12 "$FINDINGS"
  assert_failure
  assert_output --partial "has 2 Review record comments"
  run grep -cE 'POST|PATCH' "$STUB_LOG"
  assert_output 0
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `review_record.bats` 3개가 `scripts/review-record.sh: No such file or directory`로 실패한다.

- [ ] **Step 3: `scripts/review-record.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Create or update the single "Review record" comment of a pull request from a findings file
# (docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, section 8; table format: docs/reviews/README.md).
# Usage: review-record.sh PR FILE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# The first line of the record comment; this script finds the record again by it.
readonly MARKER='<!-- review-record -->'

usage() {
  die "usage: make review-record PR=<number> FILE=<findings file>"
}

main() {
  local pr="${1:-}" file="${2:-}" body ids count
  [[ "$pr" =~ ^[0-9]+$ && -n "$file" ]] || usage
  [[ -f "$file" ]] || die "findings file '$file' not found"
  require_cmd gh
  body="$(mktemp "${TMPDIR:-/tmp}/review-record.XXXXXX")" || exit 1
  # shellcheck disable=SC2064  # expand $body now: it is local to main
  trap "rm -f '$body'" EXIT
  {
    printf '%s\n' "$MARKER"
    cat "$file"
  } >"$body"
  ids="$(gh api "repos/{owner}/{repo}/issues/$pr/comments" --paginate --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id")" \
    || die "could not list the comments of PR #$pr"
  count="$(grep -c . <<<"$ids" || true)"
  case "$count" in
    0)
      gh api -X POST "repos/{owner}/{repo}/issues/$pr/comments" -F "body=@$body" >/dev/null \
        || die "could not create the Review record on PR #$pr"
      log "created the Review record on PR #$pr"
      ;;
    1)
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$ids" -F "body=@$body" >/dev/null \
        || die "could not update the Review record comment $ids on PR #$pr"
      log "updated the Review record on PR #$pr (comment $ids)"
      ;;
    *)
      die "PR #$pr has $count Review record comments ($(tr '\n' ' ' <<<"$ids")); delete the extras on GitHub, then rerun"
      ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Makefile**

`.PHONY`에 `review-record`를 더하고, `review-post` 타깃 다음에 다음을 넣는다.

```make
review-record: ## Create or update the PR's Review record comment: PR=<number> FILE=<findings table file>
	scripts/review-record.sh "$(PR)" "$(FILE)"
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. `review_record.bats` 3개가 ok이고, 커버리지 목록에 `review-record.sh`가 나온다.

- [ ] **Step 6: 커밋과 push**

```bash
git add scripts/review-record.sh tests/review_record.bats Makefile
git commit -m "feat: keep one Review record comment per pull request" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: znbc3ase" --trailer "Task: 2"
git push
```

### Task 3: 리뷰 문서를 PR 기준으로

**Files:**
- Modify: `.agents/skills/git-workflow/references/review-and-merge.md`(Review 절 4·5번, Fix findings 3번), `.agents/skills/branch-review/SKILL.md:20,23`, `AGENTS.md`(Code Review Rules 3·6번), `docs/reviews/README.md`(전체), `docs/ARCHITECTURE.md:30`, `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md`(14절 3·4번)

**Interfaces:**
- Consumes: Task 1·2의 `make review-post`, `make review-record`, meta 파일, 표식

- [ ] **Step 1: git-workflow 참조 파일**

Review 절의 4·5번을 다음으로 바꾼다.

```markdown
4. Post both raw reports to the pull request: `make review-post PR=<PR> BRANCH=<branch> REVIEWER=<reviewer> REVIEW_MODEL=<reviewer model>` (add `ROUND=<n>` from round 2). It posts two comments headed by the round, the reviewer and model, and the base and reviewed head SHAs that `make review` recorded.
5. Keep the findings table in the main checkout's `.review-out/<branch-slug>-record.md` (format: docs/reviews/README.md) and publish it with `make review-record PR=<PR> FILE=<that file>`. Run it again after every status change: it updates the same "Review record" comment.
```

Fix findings 절 3번의 `and post it like round 1`을 `and post it with make review-post ... ROUND=2`로 바꾼다.

- [ ] **Step 2: branch-review 스킬**

`.agents/skills/branch-review/SKILL.md:20`(3번)을 다음으로 바꾼다.

```markdown
3. The author reports passing CI (`check`, `pr-rules`) and a passing `make check` in the plan's Progress log; `scripts/check-git.sh origin/main <branch>` passes. If you cannot run scripts, read the trailers at the end of each message in `git log origin/main..<branch>`.
```

`:23`(6번)을 다음으로 바꾼다.

```markdown
6. Every commit carries `Assisted-by`, `Plan` and `Task` trailers, and the pull request body ends with `Assisted-by` and `Plan` (the squash commit message).
```

- [ ] **Step 3: `AGENTS.md`의 Code Review Rules**

3번을 다음으로 바꾼다.

```markdown
3. The plan's Progress log records a passing `make check` and passing CI (`check`, `pr-rules`) on the PR; `scripts/check-git.sh origin/main <branch>` passes.
```

6번을 다음으로 바꾼다. `P0 ... P1 ... block the merge` 줄은 바꾸지 않는다(`tests/repo.bats`가 검사함).

```markdown
6. Every commit carries the Git trailers, and the PR body ends with the `Assisted-by` and `Plan` trailers.
```

- [ ] **Step 4: `docs/reviews/README.md` (전체 교체)**

````markdown
# Review records

The files here are the review records of branches merged before the review-posting plan; keep them as history and add no new ones. From the review-posting plan on, the record is the pull request's "Review record" comment. The author keeps the table in the main checkout's `.review-out/<branch-slug>-record.md` and publishes it with `make review-record PR=<number> FILE=<that file>`; `make review-post` posts the raw reports. Policy: `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md`, section 8.

## Template

```markdown
| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex <model> | <base sha> | <head sha> | blocked (1 P1) |

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/example.sh:42 | <failure scenario> | fixed <sha> |
```

Status values: `open`, `fixed <sha>`, `rejected <evidence>`, `deferred <human's reason>`.
````

- [ ] **Step 5: ARCHITECTURE와 스펙**

`docs/ARCHITECTURE.md:30`의 `` `docs/reviews/`(리뷰 기록) ``을 다음으로 바꾼다.

```markdown
`scripts/post-review.sh`·`scripts/review-record.sh`(리뷰 원문과 기록을 PR 코멘트로 게시), `docs/reviews/`(github-switch 계획까지의 리뷰 기록)
```

스펙 14절 3·4번을 "시작" 단계에서 적은 결과로 바꾼다. 형식은 `(확인됨, <날짜>) <결과>`다. 3번 결과에 GitHub이 squash 커밋에 `Co-authored-by`를 자동으로 붙인다고 나오면, 그 줄은 사람이 아닌 GitHub이 붙인 것이라 정책 위반이 아니라고 함께 적는다.

- [ ] **Step 6: 확인**

Run: `make check`
Expected: exit 0. `skills.bats`, `repo.bats`(Code Review Rules, 링크, docs 경로)가 통과한다.

Run: `grep -rn 'docs/reviews/<' .agents/skills AGENTS.md`
Expected: 출력 없음. 새 리뷰 기록 파일을 만들라는 안내가 남아 있지 않다.

- [ ] **Step 7: 커밋과 push**

```bash
git add .agents/skills AGENTS.md docs/reviews/README.md docs/ARCHITECTURE.md docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md
git commit -m "docs: move review reports and records to pull request comments" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: znbc3ase" --trailer "Task: 3"
git push
```

### Task 4: 실제 PR로 확인 (dogfooding)

- [ ] **Step 1:** 이 계획의 마무리 리뷰에서 `make review-post`와 `make review-record`를 실제로 쓴다.
- [ ] **Step 2:** PR 화면에서 세 가지를 확인한다.
  - 코멘트 두 개(change, plan)의 머리에 회차, 리뷰어, 모델, SHA가 있다.
  - Review record는 하나뿐이다.
  - 상태를 바꿔 `make review-record`를 다시 실행하면 같은 코멘트가 바뀐다(Review Focus 4).
- [ ] **Step 3:** 결과를 Progress log에 `Verified`로 적고 커밋한다(`Task: 4`).

### 마무리

- [ ] `make check`와 `make check-git`이 통과한다.
- [ ] 계획 파일을 `docs/plans/completed/`로 옮겨 커밋하고(`Task: none`) push한다.
- [ ] git-workflow 스킬의 Review 절을 따른다. 이번에는 새 Make 타깃을 쓴다. Codex 리뷰는 사용자의 승인을 받은 뒤 실행한다.
- [ ] CI가 통과하고 Review record에 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행한다. 사람이 승인하고 Squash and merge를 누른다.
- [ ] 병합 뒤 Clean up 절로 정리한다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
