---
status: active
spec: docs/specs/spec-2026-10-15-doc-system.md
---

# 14 Doc Rename And Checks Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 없다. `AGENTS.md`는 시작 절에서 사용자가 승인한 문구로만 고친다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 기존 문서 44개를 레지스트리 규칙의 이름과 위치로 옮기고(계획 폴더 통합 포함) 모든 참조를 고친 뒤, 모든 타입 문서와 ARCHITECTURE에 front matter를 달고, 증거 위치(D4)와 계획 생애 주기 문장을 새 규칙으로 바꾸며, `tests/repo-docs.bats`가 이름·위치·메타데이터·경로를 검사하게 한다.

**Architecture:**
- 이름 변경은 손으로 하지 않는다. 시작 시점의 `main`에서 옛 경로 → 새 경로 표를 스크립트로 만들고, `git mv`와 참조 고치기(perl)를 그 표로 한 번에 한다. 스크립트는 저장소 밖 scratch 폴더에 두고 커밋하지 않는다.
- 참조 고치기는 옛 파일 이름(basename)을 앞이 파일 이름 글자가 아닌 곳에서만 바꾼다. 그래서 `docs/runbooks/…` 경로, 같은 폴더의 상대 링크, 백틱 안의 이름이 모두 바뀌고, 두 번 돌려도 결과가 같다. `docs/` 아래 Markdown의 코드 블록은 그때의 명령·출력 기록이므로 바꾸지 않는다.
- 검사는 `scripts/lib/docs.sh`의 `doc_types`로 레지스트리를 읽어 반복문으로 한다(ADR 0007). 계획 13의 파서를 그대로 쓴다.
- Task 1은 이름과 경로, Task 2는 front matter, Task 3은 문장(생애 주기와 D4)이다. 각 Task가 끝날 때 `make check`가 통과한다.

**Spec:** `docs/specs/spec-2026-10-15-doc-system.md` (특히 §3.1, §4, §6.3, §6.4, §8.3, §9, §10)

**Sequence:** 계획 14. 다음을 모두 만족한 뒤 시작한다.
- 계획 13(PR #11, `03432a1`)이 병합됐다(충족).
- 계획 12의 결과 PR(#12, `4cedf49`)이 병합됐다(충족). 그 PR이 고친 계획 12 파일, ADR 0006, 접속 방식 설계, 런북을 이 계획이 옮긴다.
- 열린 PR #10(`work/docker-log-rotation`)은 `docs/ARCHITECTURE.md`와 `tests/repo.bats`를 고친다. 이 계획도 두 파일을 고치므로(front matter, 옮기는 경로 검사), 나중에 병합되는 쪽이 `git merge origin/main`으로 충돌을 푼다. 리베이스하지 않는다.

## Global Constraints

- 새 이름은 스펙 §3.1: 번호가 없는 타입은 `<코드>-<YYYY-MM-DD>-<slug>.md`, 계획은 `plan-<YYYY-MM-DD>-<NN>-<slug>.md`, ADR은 `adr-<YYYY-MM-DD>-<NNNN>-<slug>.md`. 이름에 날짜가 있던 문서는 그 날짜를, 없던 문서(ADR, 런북, 리뷰)는 처음 커밋된 날(`git log --diff-filter=A --follow --format=%as`의 마지막 줄)을 쓴다. 스펙은 `-design` 꼬리를 뗀다. `README.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, `docs/reviews/README.md`는 그대로 둔다.
- 계획은 모두 `docs/plans/`에 두고, 상태는 front matter의 `status`가 말한다. `backlog/`, `active/`, `completed/` 폴더는 없어진다.
- 바꾸지 않는 것(스펙 §9): 증거(명령, 출력, SHA, 날짜, 측정값), ADR의 결정 문장, 스펙의 사용자 결정, 완료 계획의 체크박스, 계획 본문에 복사된 파일 내용(코드 블록), 기록 문서 속 옛 스크립트 이름, 이름이나 번호로 인용되는 런북 제목(스펙 §5.4). 리뷰 기록은 이름과 `status: final`만 바꾼다.
- 경로를 고칠 때: 옮긴 문서는 새 경로로, 지워진 문서는 경로 대신 말로 풀어 쓴다(스펙 §9). 다른 저장소의 파일은 저장소 이름을 앞에 붙여 이 저장소 경로와 구별한다.
- `AGENTS.md`는 시작 절에서 사용자가 승인한 문구로만 고친다.
- 검사 테스트는 문구를 되풀이하지 않는다(ADR 0004, 0007). 레지스트리를 읽어 반복문으로 확인하고, 실패 메시지는 파일, 어긋난 값, 고칠 곳을 함께 출력한다.
- 테스트는 `make test`/`make check`로만 돌린다. `git add`하기 전에 `git status`를 본다. 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 14`, `Task: <N|review|none>`.
- PR: 브랜치 `plan/14-doc-rename-and-checks`, 제목 `refactor: rename every document to the registry rules and check them`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 14`다.

## Review Focus

1. **이름을 바꾼 문서를 가리키던 참조가 남음.** 경로가 아니라 이름만 쓴 곳(같은 폴더 상대 링크, 백틱 속 파일 이름, 스크립트 메시지의 런북 경로)도 있다. → Task 1 Step 1의 경로 검사가 추적 중인 모든 Markdown(코드 블록 밖)과 `scripts/`, 스킬, `AGENTS.md`를 보고, 기존 상대 링크 검사와 bats의 스크립트 메시지 단언이 나머지를 잡는다.
2. **계획을 한 단계 위 폴더로 옮기면서 깨지는 상대 링크.** 계획 12의 `../../runbooks/…` 링크가 그렇다. → Task 1 Step 3의 perl이 옮긴 계획 파일의 `](../../`를 `](../`로 고치고, 상대 링크 검사가 확인한다.
3. **URL이나 다른 저장소 경로를 이 저장소 경로로 오인함.** `code.claude.com/docs/…`, `design-docs/index.md`, SilverBullet 저장소의 `docs/API/…`. → Task 1 Step 1 검사의 앞 글자 규칙(앞이 경로 글자면 건너뜀)과 Step 4의 저장소 이름 붙이기.
4. **기록을 바꿈.** 참조 고치기가 코드 블록 속 명령이나 Progress log의 SHA를 건드리면 기록이 사실과 달라진다. → perl은 `docs/` 아래 Markdown의 코드 블록을 건너뛰고, Step 5에서 바뀐 것이 경로와 Step 4의 손 수정뿐인지 본다.
5. **front matter 값이 사실과 다름.** 대체 관계, 상태 날짜, 계획의 근거 스펙. → Task 2 Step 3의 표가 각 값의 근거(머리 줄, 병합일)를 적고, 검사 3이 경로 존재와 허용 값을 확인한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `tests/repo-docs.bats` | 문서 구조 검사 1~6(스펙 §8.3) | 1, 2 |
| `tests/repo.bats` | 옮긴 문서 경로 검사를 지움 | 1 |
| `docs/**`의 문서 44개 | 새 이름과 위치(Task 1), front matter와 상태 줄(Task 2) | 1, 2 |
| 문서를 가리키는 모든 파일(`AGENTS.md`, `README.md`, 스킬, 스크립트 메시지와 머리 주석, 테스트, `.github/`) | 새 경로 | 1 |
| `AGENTS.md`, `git-workflow`·`branch-review`·`bm-upgrade`·`doc-authoring` 스킬, `docs/README.md`, 계획 템플릿, PR 템플릿 | 생애 주기와 증거 위치(D4), 전환 문장 삭제 | 3 |

---

### 시작: 브랜치, `AGENTS.md` 문구 승인, 초안 PR

- [x] `git fetch origin` 뒤 `origin/main`에서 `plan/14-doc-rename-and-checks` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [x] 사용자 OK: `AGENTS.md`에서 바뀌는 곳을 보여 승인받고 Progress log에 `Verified`로 적는다. (a) Task 1이 바꾸는 문서 경로: 4행(Read first), 30행(`## Git`의 정책 경로), 54행(GitHub 런북). (b) Task 3 Step 1의 문구: 5·41·49·60행.
- [x] 첫 커밋에서 이 계획 파일의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

---

### Task 1: 새 이름과 위치, 경로 검사

**Files:**
- Create: `tests/repo-docs.bats`
- Modify: `tests/repo.bats`(옛 문서 경로 검사 삭제), 문서 44개의 이름(`git mv`), 그 문서들을 가리키는 모든 파일
- Test: `tests/repo-docs.bats`(검사 1, 2, 4, 6), `tests/repo.bats`의 상대 링크 검사

**Interfaces:**
- Consumes: `scripts/lib/docs.sh`의 `doc_types`(8개 필드: type code number location statuses keys new template), `tests/helpers.bash`의 `frontmatter`
- Produces: `tests/repo-docs.bats`의 도우미 `doc_files`, `type_row FILE`, `outside_code FILE`, `docs_paths`(stdin → 이 저장소의 docs 경로, 한 줄에 하나)와 상수 `SINGLE_FILES`. Task 2가 같은 파일에 검사 3, 5를 더한다.

- [ ] **Step 1: 실패하는 검사 작성 (`tests/repo-docs.bats`)**

```bash
#!/usr/bin/env bats
load helpers

# Document structure checks: location, file name and front matter only, read from the registry in docs/README.md
# (doc system spec section 8.3). ADR 0007 allows these checks; ADR 0004 still bans checks on wording.

# Files under docs/ that keep their names and belong to no type (spec section 3.1).
SINGLE_FILES="docs/README.md docs/ARCHITECTURE.md docs/reviews/README.md"

setup() {
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
  TYPES="$(doc_types "$REPO_DIR/docs/README.md")" || fail "the registry under '## 문서 타입' in docs/README.md does not parse"
}

# doc_files: every tracked or new (not ignored) file under docs/, one per line, relative to the repo.
doc_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- docs
}

# type_row FILE: the registry row whose folder holds FILE directly; nothing when no type owns that folder.
type_row() {
  awk -F'\t' -v loc="${1%/*}/" '$4 == loc' <<<"$TYPES"
}

# outside_code FILE: the lines of FILE outside ``` fences (the rule of the relative link check in repo.bats).
outside_code() {
  awk '/^```/ { fence = !fence; next } !fence' "$1"
}

# docs_paths: the docs/...md paths of this repo in stdin, one per line. A match right after a path character is part
# of a URL or another path (code.claude.com/docs/..., design-docs/...), and "..." marks a placeholder; both are skipped.
docs_paths() {
  { grep -oE '(^|[^A-Za-z0-9_./-])docs/[A-Za-z0-9_./-]+\.md' || true; } | sed -E 's#^[^d]##' | { grep -vF '...' || true; }
}

@test "the registry has unique types and codes, valid number and 새 문서 cells, and a template for every type that takes new documents" {
  local type code number location statuses keys new template bad="" dup
  dup="$(
    cut -f1 <<<"$TYPES" | sort | uniq -d
    cut -f2 <<<"$TYPES" | sort | uniq -d
  )"
  [[ -z "$dup" ]] || bad="$bad"$'\n'"  used twice: $dup"
  while IFS=$'\t' read -r type code number location statuses keys new template; do
    [[ "$code" =~ ^[a-z]{3,4}$ ]] || bad="$bad"$'\n'"  $type: code '$code' must be 3-4 lowercase letters"
    case "$number" in 없음 | NN | NNNN) ;; *) bad="$bad"$'\n'"  $type: 번호 '$number' must be 없음, NN or NNNN" ;; esac
    case "$new" in
      허용) [[ -f "$REPO_DIR/$template" ]] || bad="$bad"$'\n'"  $type: template $template does not exist" ;;
      금지) ;;
      *) bad="$bad"$'\n'"  $type: 새 문서 '$new' must be 허용 or 금지" ;;
    esac
  done <<<"$TYPES"
  [[ -z "$bad" ]] || fail "fix the table under '## 문서 타입' in docs/README.md:$bad"
}

@test "every file under docs/ is a single file or sits in its type's folder named <code>-<date>[-<number>]-<slug>.md" {
  local file row code number pattern hint bad=""
  while IFS= read -r file; do
    case " $SINGLE_FILES " in *" $file "*) continue ;; esac
    row="$(type_row "$file")"
    if [[ -z "$row" ]]; then
      bad="$bad"$'\n'"  $file: no document type owns ${file%/*}/"
      continue
    fi
    IFS=$'\t' read -r _ code number _ <<<"$row"
    pattern="^${code}-[0-9]{4}-[0-9]{2}-[0-9]{2}-"
    hint="$code-<YYYY-MM-DD>-<slug>.md"
    if [[ "$number" != "없음" ]]; then
      pattern="${pattern}[0-9]{${#number}}-"
      hint="$code-<YYYY-MM-DD>-$number-<slug>.md"
    fi
    pattern="${pattern}[a-z0-9]+(-[a-z0-9]+)*[.]md$"
    [[ "${file##*/}" =~ $pattern ]] || bad="$bad"$'\n'"  $file: name it $hint"
  done <<<"$(doc_files)"
  [[ -z "$bad" ]] || fail "move or rename these with git mv (rules: docs/README.md):$bad"
}

@test "plan and ADR numbers are unique" {
  local type code number location rest dups bad=""
  while IFS=$'\t' read -r type code number location rest; do
    [[ "$number" != "없음" ]] || continue
    dups="$(doc_files | grep "^$location$code-" | sed -E "s#^$location$code-[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]+)-.*#\1#" | sort | uniq -d)"
    [[ -z "$dups" ]] || bad="$bad"$'\n'"  $type: $dups"
  done <<<"$TYPES"
  [[ -z "$bad" ]] || fail "renumber one document of each pair with git mv (make new-doc picks the next free number):$bad"
}

@test "every docs path named in scripts, skills, AGENTS.md or outside code in tracked Markdown exists" {
  local path paths missing="" count=0
  paths="$(
    cd "$REPO_DIR" || exit 1
    cat AGENTS.md $(git ls-files scripts .agents/skills) | docs_paths
    git ls-files --cached --others --exclude-standard -- '*.md' | grep -vE '^(AGENTS[.]md|[.]agents/skills/)' |
      while IFS= read -r file; do outside_code "$file" | docs_paths; done
  )" || fail "could not collect the docs paths"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    count=$((count + 1))
    [[ -f "$REPO_DIR/$path" ]] || missing="$missing $path"
  done <<<"$(sort -u <<<"$paths")"
  ((count > 0)) || fail "no docs paths were checked"
  [[ -z "$missing" ]] || fail "these paths name no file; point them at the current file, or spell out a deleted one:$missing"
}
```

`tests/repo.bats`에서 `every docs markdown path named in scripts, skills and AGENTS.md exists` 테스트를 지운다. 위의 마지막 검사가 범위를 넓혀 대신한다.

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `every file under docs/ is a single file …`(옛 이름과 계획 하위 폴더)와 `every docs path named …`(이미 없는 옛 경로들) 두 개가 실패한다. 레지스트리 검사와 번호 검사는 통과한다.

- [ ] **Step 3: 이름 변경과 참조 고치기 (scratch 스크립트, 커밋하지 않음)**

아래 두 파일을 저장소 밖 scratch 폴더(이하 `$S`)에 만든다.

`$S/rename-map.sh`: 옛 경로 → 새 경로 표를 만든다.

```bash
set -euo pipefail
# Prints "old<TAB>new" for every typed document whose name changes (doc system spec 3.1).
cd "$1"
first_date() { git log --diff-filter=A --follow --format=%as -- "$1" | tail -n 1; }
git ls-files docs | while IFS= read -r f; do
  base="${f##*/}"
  case "$f" in
    docs/README.md | docs/ARCHITECTURE.md | docs/reviews/README.md) continue ;;
    docs/specs/spec-* | docs/plans/plan-* | docs/decisions/adr-* | docs/runbooks/rbk-* | docs/research/rsch-* | docs/reviews/rev-*) continue ;;
    docs/specs/*) new="docs/specs/spec-${base%-design.md}"; [[ "$new" == *.md ]] || new="$new.md" ;;
    docs/plans/*/*) new="docs/plans/plan-$base" ;;
    docs/decisions/*) new="docs/decisions/adr-$(first_date "$f")-$base" ;;
    docs/runbooks/*) new="docs/runbooks/rbk-$(first_date "$f")-$base" ;;
    docs/research/*) new="docs/research/rsch-$base" ;;
    docs/reviews/*) new="docs/reviews/rev-$(first_date "$f")-$base" ;;
    *) printf 'UNMAPPED\t%s\n' "$f"; continue ;;
  esac
  printf '%s\t%s\n' "$f" "$new"
done
```

`$S/rewrite-doc-refs.pl`: 표대로 참조를 고친다.

```perl
#!/usr/bin/env perl
# Rewrite references to renamed documents. Usage: rewrite-doc-refs.pl MAP FILE...
# MAP lines are old-path<TAB>new-path. Inside ``` fences of Markdown under docs/ the lines are records and stay.
use strict;
use warnings;

my $map = shift @ARGV;
open my $mh, '<', $map or die "cannot read $map: $!";
my @pairs;
while (my $line = <$mh>) {
  chomp $line;
  my ($old, $new) = split /\t/, $line;
  my ($old_base) = $old =~ m{([^/]+)$};
  my ($new_base) = $new =~ m{([^/]+)$};
  push @pairs, [$old_base, $new_base, $old =~ m{^docs/plans/} ? 1 : 0];
}
close $mh;

for my $file (@ARGV) {
  open my $fh, '<', $file or die "cannot read $file: $!";
  my @lines = <$fh>;
  close $fh;
  my $records = $file =~ m{^docs/.*[.]md$};
  my $moved_plan = $file =~ m{^docs/plans/plan-};
  my ($fence, $changed) = (0, 0);
  for my $line (@lines) {
    if ($records && $line =~ /^```/) { $fence = !$fence; next; }
    next if $fence;
    my $before = $line;
    for my $p (@pairs) {
      my ($ob, $nb, $plan) = @$p;
      if ($plan) {
        $line =~ s{[.][.]/(?:backlog|active|completed)/\Q$ob\E}{$nb}g;
        $line =~ s{plans/(?:backlog|active|completed)/\Q$ob\E}{plans/$nb}g;
      }
      $line =~ s{(?<![A-Za-z0-9_.\-])\Q$ob\E}{$nb}g;
    }
    # Plans moved up one folder (docs/plans/<state>/ to docs/plans/).
    $line =~ s{\]\([.][.]/[.][.]/}{](../}g if $moved_plan;
    $changed = 1 if $line ne $before;
  }
  next unless $changed;
  open my $out, '>', $file or die "cannot write $file: $!";
  print {$out} @lines;
  close $out;
  print "rewrote $file\n";
}
```

worktree 루트에서 실행한다.

```bash
bash "$S/rename-map.sh" "$PWD" > "$S/rename-map.tsv"
grep -c . "$S/rename-map.tsv"        # 44
grep UNMAPPED "$S/rename-map.tsv"    # 출력 없음
while IFS=$'\t' read -r old new; do git mv "$old" "$new"; done < "$S/rename-map.tsv"
rmdir docs/plans/backlog docs/plans/active docs/plans/completed 2>/dev/null || true
cut -f1 "$S/rename-map.tsv" | sed 's#.*/##' > "$S/old-names.txt"
git grep -lIF -f "$S/old-names.txt" | xargs perl "$S/rewrite-doc-refs.pl" "$S/rename-map.tsv"
```

2026-10-16에 `main` `4cedf49`에서 만든 표다. 시작할 때 다시 만들고 같은지 본다.

```text
docs/decisions/0001-basic-memory-on-gcp-tailscale.md	docs/decisions/adr-2026-10-12-0001-basic-memory-on-gcp-tailscale.md
docs/decisions/0002-vm-sizing.md	docs/decisions/adr-2026-10-12-0002-vm-sizing.md
docs/decisions/0003-skill-structure.md	docs/decisions/adr-2026-10-13-0003-skill-structure.md
docs/decisions/0004-test-scope.md	docs/decisions/adr-2026-10-13-0004-test-scope.md
docs/decisions/0005-web-ui-silverbullet.md	docs/decisions/adr-2026-10-15-0005-web-ui-silverbullet.md
docs/decisions/0006-access-modes.md	docs/decisions/adr-2026-10-15-0006-access-modes.md
docs/plans/backlog/2026-10-13-07-ipv6-egress.md	docs/plans/plan-2026-10-13-07-ipv6-egress.md
docs/plans/completed/2026-10-07-01-local-foundation.md	docs/plans/plan-2026-10-07-01-local-foundation.md
docs/plans/completed/2026-10-07-02-git-review-tooling.md	docs/plans/plan-2026-10-07-02-git-review-tooling.md
docs/plans/completed/2026-10-07-03-vm-scripts.md	docs/plans/plan-2026-10-07-03-vm-scripts.md
docs/plans/completed/2026-10-07-04-docs-skills.md	docs/plans/plan-2026-10-07-04-docs-skills.md
docs/plans/completed/2026-10-07-05-vm-rollout.md	docs/plans/plan-2026-10-07-05-vm-rollout.md
docs/plans/completed/2026-10-13-06-test-pruning.md	docs/plans/plan-2026-10-13-06-test-pruning.md
docs/plans/completed/2026-10-13-08-github-switch.md	docs/plans/plan-2026-10-13-08-github-switch.md
docs/plans/completed/2026-10-13-09-review-posting.md	docs/plans/plan-2026-10-13-09-review-posting.md
docs/plans/completed/2026-10-14-10-web-ui-local.md	docs/plans/plan-2026-10-14-10-web-ui-local.md
docs/plans/completed/2026-10-14-11-web-ui-vm-rollout.md	docs/plans/plan-2026-10-14-11-web-ui-vm-rollout.md
docs/plans/completed/2026-10-15-12-access-modes.md	docs/plans/plan-2026-10-15-12-access-modes.md
docs/plans/completed/2026-10-16-13-doc-system-foundation.md	docs/plans/plan-2026-10-16-13-doc-system-foundation.md
docs/research/2026-10-13-agent-oss-git-strategies.md	docs/research/rsch-2026-10-13-agent-oss-git-strategies.md
docs/research/2026-10-15-agent-repo-conventions.md	docs/research/rsch-2026-10-15-agent-repo-conventions.md
docs/reviews/plan-01-local-foundation.md	docs/reviews/rev-2026-10-07-plan-01-local-foundation.md
docs/reviews/plan-02-git-review-tooling.md	docs/reviews/rev-2026-10-08-plan-02-git-review-tooling.md
docs/reviews/plan-03-vm-scripts.md	docs/reviews/rev-2026-10-08-plan-03-vm-scripts.md
docs/reviews/plan-04-docs-skills.md	docs/reviews/rev-2026-10-12-plan-04-docs-skills.md
docs/reviews/plan-06-test-pruning.md	docs/reviews/rev-2026-10-13-plan-06-test-pruning.md
docs/reviews/work-backup-skip-model-cache.md	docs/reviews/rev-2026-10-13-work-backup-skip-model-cache.md
docs/reviews/work-rename-agent-hub.md	docs/reviews/rev-2026-10-12-work-rename-agent-hub.md
docs/reviews/work-skill-best-practices.md	docs/reviews/rev-2026-10-13-work-skill-best-practices.md
docs/reviews/work-slow-start-health.md	docs/reviews/rev-2026-10-13-work-slow-start-health.md
docs/reviews/work-workflow-alignment.md	docs/reviews/rev-2026-10-13-work-workflow-alignment.md
docs/runbooks/accounts.md	docs/runbooks/rbk-2026-10-12-accounts.md
docs/runbooks/bootstrap.md	docs/runbooks/rbk-2026-10-12-bootstrap.md
docs/runbooks/gcp-vm.md	docs/runbooks/rbk-2026-10-12-gcp-vm.md
docs/runbooks/github.md	docs/runbooks/rbk-2026-10-14-github.md
docs/runbooks/operations.md	docs/runbooks/rbk-2026-10-12-operations.md
docs/specs/2026-10-07-basic-memory-oci-tailscale-design.md	docs/specs/spec-2026-10-07-basic-memory-oci-tailscale.md
docs/specs/2026-10-07-git-review-policy-design.md	docs/specs/spec-2026-10-07-git-review-policy.md
docs/specs/2026-10-12-basic-memory-gcp-tailscale-design.md	docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md
docs/specs/2026-10-13-github-pr-workflow-design.md	docs/specs/spec-2026-10-13-github-pr-workflow.md
docs/specs/2026-10-14-silverbullet-web-ui-design.md	docs/specs/spec-2026-10-14-silverbullet-web-ui.md
docs/specs/2026-10-15-access-modes-design.md	docs/specs/spec-2026-10-15-access-modes.md
docs/specs/2026-10-15-doc-system-design.md	docs/specs/spec-2026-10-15-doc-system.md
docs/specs/2026-10-15-script-test-layout-design.md	docs/specs/spec-2026-10-15-script-test-layout.md
```

- [ ] **Step 4: 남은 경로 고치기**

Run: `make test`
Expected: 이름 검사는 통과하고, 경로 검사에 이름 변경으로 고칠 수 없는 경로만 남는다. 2026-10-16에 미리 확인한 것과 고치는 방법:

| 파일(새 이름) | 경로 | 고치는 방법 |
|---|---|---|
| `docs/plans/plan-2026-10-07-04-docs-skills.md` | OCI 시절 ADR 0001, OCI VM 런북 | 지워진 문서다. 경로를 "OCI 시절의 ADR 0001(계획 04에서 지움)", "OCI VM 런북(계획 04에서 지움)"처럼 풀어 쓴다 |
| `docs/plans/plan-2026-10-07-05-vm-rollout.md` | 계획 05 리뷰 기록 파일 | 만들어지지 않은 파일이다. "계획 05의 리뷰 기록(PR 댓글)"으로 풀어 쓴다 |
| `docs/specs/spec-2026-10-07-basic-memory-oci-tailscale.md` | OCI VM 런북 | "OCI VM 런북(계획 04에서 지움)"으로 풀어 쓴다 |
| `docs/plans/plan-2026-10-16-13-doc-system-foundation.md` | 테스트 예시 `2026-10-01-draft.md`, 지운 확인용 조사 문서 | 경로 앞의 폴더를 떼고 "ADR 폴더의 `2026-10-01-draft.md`", "확인 뒤 지운 `rsch-2026-10-16-plan13-smoke.md`"로 쓴다 |
| `docs/specs/spec-2026-10-14-silverbullet-web-ui.md` | SilverBullet 저장소의 `API/view.md`, `API/widget.md`(그 저장소의 docs 폴더) | 다른 저장소 파일이다. `silverbullet/docs/API/view.md:39-58`처럼 저장소 이름을 앞에 붙인다 |

새로 나오는 경로도 같은 규칙으로 고친다. 고친 내용을 Progress log에 적는다.

- [ ] **Step 5: 통과 확인과 기록 보존 확인**

Run: `make check`
Expected: exit 0. 새 검사 4개, 상대 링크 검사, 스크립트 메시지를 단언하는 테스트(`vm_ops.bats`, `cloud_neutral.bats` 등)가 통과한다.

Run: `git status --short | grep -c '^R'`
Expected: 44(모두 rename으로 잡힘).

Run: `git diff -M --word-diff=porcelain | grep -E '^[-+][^-+]' | grep -vE 'docs/|[.]md'`
Expected: 경로가 아닌 낱말이 바뀐 줄은 Step 4에서 손으로 고친 줄뿐이다.

- [ ] **Step 6: 커밋**

```bash
git status --short
git add -A docs tests/repo-docs.bats
git add -u
git commit -m "refactor: rename every document to the registry rules and fix references" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 14" --trailer "Task: 1"
git push
```

---

### Task 2: front matter와 상태 줄

**Files:**
- Modify: 타입 문서와 `docs/ARCHITECTURE.md`(front matter), 상태 줄이 있는 문서, 낡은 상태 문구가 있는 스펙
- Test: `tests/repo-docs.bats`(검사 3, 5 추가)

**Interfaces:**
- Consumes: Task 1의 `doc_files`, `type_row`, `outside_code`, `SINGLE_FILES`, `tests/helpers.bash`의 `frontmatter FILE`
- Produces: 없음

- [ ] **Step 1: 실패하는 검사 작성 (`tests/repo-docs.bats`에 추가)**

파일 위쪽 상수에 더한다.

```bash
ALLOWED_KEYS="status date spec reviewed superseded-by amended-by"
DATE_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
# docs/ARCHITECTURE.md is outside the registry but carries status and reviewed (spec section 3.2).
ARCHITECTURE_ROW="$(printf 'architecture\tarch\t없음\tdocs/\tcurrent\tstatus, reviewed\t금지\t없음')"
```

파일 끝에 더한다.

```bash
# front_value FILE KEY: the value of KEY in the front matter of FILE.
front_value() {
  frontmatter "$1" | sed -n "s/^$2: *//p"
}

# front_problems FILE ROW: one line per front matter problem of FILE against its registry ROW.
front_problems() {
  local file="$1" row="$2" type statuses keys key value status path
  IFS=$'\t' read -r type _ _ _ statuses keys _ <<<"$row"
  if [[ -z "$(frontmatter "$REPO_DIR/$file")" ]]; then
    printf '%s: no front matter (--- block at the top)\n' "$file"
    return 0
  fi
  for key in $(frontmatter "$REPO_DIR/$file" | sed -n 's/^\([^:]*\):.*/\1/p'); do
    case " $ALLOWED_KEYS " in *" $key "*) ;; *) printf '%s: key %s is not one of: %s\n' "$file" "$key" "$ALLOWED_KEYS" ;; esac
  done
  for key in $(tr ',' ' ' <<<"$keys"); do
    [[ -n "$(front_value "$REPO_DIR/$file" "$key")" ]] || printf '%s: %s needs %s\n' "$file" "$type" "$key"
  done
  status="$(front_value "$REPO_DIR/$file" status)"
  [[ ", $statuses," == *", $status,"* ]] || printf '%s: status %s is not one of: %s\n' "$file" "$status" "$statuses"
  for key in date reviewed; do
    value="$(front_value "$REPO_DIR/$file" "$key")"
    [[ -z "$value" || "$value" =~ $DATE_PATTERN ]] || printf '%s: %s %s is not YYYY-MM-DD\n' "$file" "$key" "$value"
  done
  for key in spec superseded-by amended-by; do
    value="$(front_value "$REPO_DIR/$file" "$key" | tr -d '[]' | tr ',' ' ')"
    for path in $value; do
      if [[ "$path" == none && "$key" == spec ]]; then
        continue
      fi
      [[ -f "$REPO_DIR/$path" ]] || printf '%s: %s %s names no file\n' "$file" "$key" "$path"
    done
  done
  if [[ "$status" == superseded && -z "$(front_value "$REPO_DIR/$file" superseded-by)" ]]; then
    printf '%s: superseded needs superseded-by\n' "$file"
  fi
}

@test "every typed document and ARCHITECTURE has front matter with the allowed and required keys and valid values" {
  local file row bad=""
  while IFS= read -r file; do
    if [[ "$file" == docs/ARCHITECTURE.md ]]; then
      row="$ARCHITECTURE_ROW"
    else
      row="$(type_row "$file")"
      [[ -n "$row" ]] || continue
    fi
    bad="$bad$(front_problems "$file" "$row")"$'\n'
  done <<<"$(doc_files)"
  bad="$(grep -v '^$' <<<"$bad" || true)"
  [[ -z "$bad" ]] || fail "fix the front matter (keys and values: docs/README.md, 메타데이터):"$'\n'"$bad"
}

@test "no typed document keeps a template blank outside code" {
  local file bad=""
  while IFS= read -r file; do
    [[ -n "$(type_row "$file")" ]] || continue
    if outside_code "$REPO_DIR/$file" | sed 's/`[^`]*`//g' | grep -q '{{'; then
      bad="$bad $file"
    fi
  done <<<"$(doc_files)"
  [[ -z "$bad" ]] || fail "fill each {{...}} blank or delete its line in:$bad"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: front matter 검사가 계획 13·14와 ADR 0007을 뺀 모든 타입 문서와 ARCHITECTURE를 "no front matter"로 들며 실패한다. `{{` 검사는 통과한다(계획 13의 템플릿 내용은 코드 블록 안이다).

- [ ] **Step 3: front matter 달기**

각 파일 맨 위에 `---`, 아래 키, `---`, 빈 줄을 넣는다. 값의 근거는 각 문서의 머리 줄과 PR 병합일이다.

| 파일 | status | date / reviewed | 그 밖의 키 | 근거 |
|---|---|---|---|---|
| `docs/specs/spec-2026-10-07-basic-memory-oci-tailscale.md` | superseded | date 2026-10-12 | superseded-by: `docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md` | 머리 줄 "대체됨 (2026-10-12)" |
| `docs/specs/spec-2026-10-07-git-review-policy.md` | approved | date 2026-10-07 | amended-by: `docs/specs/spec-2026-10-13-github-pr-workflow.md` | "승인됨 (2026-10-07)", "부분 대체 (2026-10-13)" |
| `docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md` | approved | date 2026-10-12 | amended-by: `[docs/specs/spec-2026-10-15-access-modes.md, docs/specs/spec-2026-10-15-doc-system.md]` | 접속 방식 설계가 "tailnet 안에서만" 전제를 넓힘, 문서 체계 설계가 §5 문서 배치를 대체 |
| `docs/specs/spec-2026-10-13-github-pr-workflow.md` | approved | date 2026-10-13 | | "승인됨 (2026-10-13)" |
| `docs/specs/spec-2026-10-14-silverbullet-web-ui.md` | approved | date 2026-10-14 | amended-by: `docs/specs/spec-2026-10-15-access-modes.md` | 접속 방식 설계가 웹 UI 노출 방식을 맞춤 |
| `docs/specs/spec-2026-10-15-access-modes.md` | approved | date 2026-10-15 | | PR #7 병합(2026-10-15). 머리 줄의 "초안"은 낡은 표기 |
| `docs/specs/spec-2026-10-15-doc-system.md` | approved | date 2026-10-16 | | "승인 (2026-10-16)" |
| `docs/specs/spec-2026-10-15-script-test-layout.md` | approved | date 2026-10-16 | | "승인 (2026-10-16)" |
| `docs/decisions/adr-2026-10-12-0001-basic-memory-on-gcp-tailscale.md` | accepted | date 2026-10-12 | | "Accepted (2026-10-12)" |
| `docs/decisions/adr-2026-10-12-0002-vm-sizing.md` | accepted | date 2026-10-14 | | "Accepted (2026-10-14)" |
| `docs/decisions/adr-2026-10-13-0003-skill-structure.md` | accepted | date 2026-10-13 | | |
| `docs/decisions/adr-2026-10-13-0004-test-scope.md` | accepted | date 2026-10-13 | amended-by: `docs/decisions/adr-2026-10-16-0007-structure-checks.md` | 머리의 "일부 대체" 줄을 이 키로 옮기고 지운다 |
| `docs/decisions/adr-2026-10-15-0005-web-ui-silverbullet.md` | accepted | date 2026-10-14 | | "Accepted (2026-10-14)" |
| `docs/decisions/adr-2026-10-15-0006-access-modes.md` | accepted | date 2026-10-15 | | 머리 줄의 "계획 12 병합일" 자리를 PR #8 병합일(2026-10-15)로 |
| 계획 01, 02, 03 | completed | | spec: `docs/specs/spec-2026-10-07-basic-memory-oci-tailscale.md`(02는 `docs/specs/spec-2026-10-07-git-review-policy.md`) | 각 계획의 Spec 줄의 첫 경로 |
| 계획 04, 05 | completed | | spec: `docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md` | |
| 계획 06 | completed | | spec: none | "별도 스펙 없음" |
| 계획 07 | backlog | | spec: none | 아직 스펙 없음 |
| 계획 08, 09 | completed | | spec: `docs/specs/spec-2026-10-13-github-pr-workflow.md` | |
| 계획 10, 11 | completed | | spec: `docs/specs/spec-2026-10-14-silverbullet-web-ui.md` | |
| 계획 12 | completed | | spec: `docs/specs/spec-2026-10-15-access-modes.md` | |
| 계획 13 | completed | | spec: `docs/specs/spec-2026-10-15-doc-system.md` | 이미 front matter가 있다. `status`만 확인한다 |
| 런북 accounts, bootstrap | current | reviewed 2026-10-15 | | 마지막 변경일(**Assumption:** 마지막 변경 때 내용을 실제와 대조했다고 본다) |
| 런북 gcp-vm, operations | current | reviewed 2026-10-16 | | 계획 12 결과 PR에서 확인 |
| 런북 github | current | reviewed 2026-10-14 | | 마지막 변경일 |
| 조사 2개 | snapshot | | | |
| 리뷰 10개 | final | | | 본문은 그대로 |
| `docs/ARCHITECTURE.md` | current | reviewed 2026-10-15 | | 마지막 변경일 |

계획 14는 시작 커밋에서 `active`다.

- [ ] **Step 4: 상태 줄과 낡은 상태 문구**

- 상태 줄: 첫 `##` 앞의 머리에서 `상태:` 줄의 상태 낱말과 날짜를 지운다. 남는 문장이 있으면 `- `로 시작하는 줄로 남기고, 없으면 줄을 지운다. 대상: 스펙 8개, ADR 6개, 조사 2개, 계획 07의 `> **상태:** 백로그.` 줄. 예: GCP 설계의 상태 줄 "상태: 승인됨 (2026-10-12). OCI 설계(링크)를 대체한다. …"는 "OCI 설계(링크)를 대체한다. …"만 남는다(링크는 그대로 둔다). OCI 설계의 "이전 상태" 줄은 그때의 기록이므로 둔다.
- 낡은 상태 문구(스펙 §2의 예):
  - GCP 설계 4행 "구현 계획 (진행 중은 …, 대기는 …, 완료는 …)" → "구현 계획 (계획은 `docs/plans/`, 상태는 각 계획의 front matter)". 8행의 계획 04 "(진행 중, 이 설계로 확장)" → "(완료, 이 설계로 확장)".
  - 웹 UI 설계 4행 "구현 계획 (대기는 …)" → "구현 계획". 6행의 계획 11 "계획 10이 병합된 뒤 시작한다"는 그때의 순서 기록이므로 둔다. 두 계획이 끝났다는 사실은 계획의 front matter가 말한다.
  - ADR 0004 머리의 "일부 대체" 줄은 지운다(Step 3에서 `amended-by`로 옮김).

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. 검사 6개가 모두 통과한다. `git diff --word-diff`에서 본문 변경은 front matter, 상태 줄, 위 낡은 문구뿐이다.

- [ ] **Step 6: 커밋**

```bash
git status --short
git add -u docs tests/repo-docs.bats
git commit -m "docs: give every document front matter and drop the status lines" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 14" --trailer "Task: 2"
git push
```

---

### Task 3: 계획 생애 주기와 증거 위치(D4)

**Files:**
- Modify: `AGENTS.md`(승인된 문구), `.agents/skills/git-workflow/SKILL.md`, `.agents/skills/git-workflow/references/review-and-merge.md`, `.agents/skills/branch-review/SKILL.md`, `.agents/skills/bm-upgrade/SKILL.md`, `.agents/skills/doc-authoring/SKILL.md`, `.agents/skills/doc-authoring/assets/plan.md`, `docs/README.md`, `.github/pull_request_template.md`
- Test: 기존 검사 전체(`tests/skills.bats`, `tests/repo.bats`, `tests/repo-docs.bats`). 문구 테스트는 쓰지 않는다(ADR 0004).

**Interfaces:**
- Consumes: Task 1의 계획 폴더 통합, Task 2의 front matter
- Produces: 없음

- [ ] **Step 1: `AGENTS.md` (시작 절에서 승인한 문구)**

줄 번호는 `4cedf49` 기준이다. 4행과 `## Git`의 정책 경로는 Task 1이 이미 새 경로로 바꿨다. 아래 네 줄을 바꾼다(5행, 41행, 49행, 60행 순서).

```markdown
Plans: `docs/plans/`; each plan's front matter `status` says backlog, active, completed or dropped.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`; record the pull request's CI results in its body (Verification), which needs no commit.
- `docs/specs/`, `docs/plans/` (state in front matter).
3. The plan's Progress log records a passing `make check`, the PR body's Verification records passing CI (`check`, `pr-rules`), and `scripts/check-git.sh origin/main <branch>` passes.
```

- [ ] **Step 2: 스킬, 템플릿, 문서 지도**

- `git-workflow` Start 3 → "For a plan, make the first commit change the plan's front matter `status` from `backlog` to `active` (`doc-authoring`)."
- `review-and-merge.md` Review 1 → "Set a finished plan's front matter `status` to `completed` (commit with `Task: none`) and push. Put the CI results in the PR body's Verification."
- `branch-review` SKILL.md 20행의 앞 문장 → "3. The plan's Progress log records a passing `make check`, the PR body's Verification records passing CI (`check`, `pr-rules`), and `scripts/check-git.sh origin/main <branch>` passes."(그 뒤 문장은 그대로)
- `bm-upgrade` SKILL.md 43행의 "Record the outcome (Verified/Command) in the active plan's Progress log or in a new ADR under `docs/decisions/`." → "Record the outcome (Verified/Command) in the active plan's Progress log, or, without a plan, in the PR body's Verification; a decision goes in a new ADR (`make new-doc TYPE=adr`)."
- `doc-authoring` SKILL.md: "Until plan 14 merges, …" 항목을 지운다. "Record evidence …" 항목 끝에 "; the PR's CI results go in the PR body's Verification"을 더한다.
- 계획 템플릿 Finish 첫 항목 뒤에 "- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다." 한 줄을 더한다.
- `docs/README.md`의 "전환 중" 문단을 지운다.
- PR 템플릿 Verification 설명 → "Commands and results (for example `make check`: N ok, 0 not ok, coverage X%) and CI (`check`, `pr-rules`)."

- [ ] **Step 3: 남은 옛 흐름 찾기**

Run: `git grep -nE 'plans/(active|backlog|completed)|Progress log.*CI|CI.*Progress log' -- AGENTS.md README.md .agents .github scripts docs/README.md`
Expected: 출력 없음. 남으면 위 규칙으로 고친다. 기록 문서(완료 계획, 스펙, ADR, 조사, 리뷰)의 옛 표현은 그대로 둔다.

- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0. `wc -c AGENTS.md`가 24,000 이하다.

- [ ] **Step 5: 커밋**

```bash
git status --short
git add -u
git commit -m "docs: keep plan state in front matter and CI evidence in the PR body" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 14" --trailer "Task: 3"
git push
```

---

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- 계획 15: 본문 소급(템플릿 절 구성, 레이블 표기 통일, README의 `AGENTS.md` 중복 삭제). 이 계획 다음에 시작한다.
- 계획 16·17: 스크립트·테스트 구조 설계. 계획 16은 이 계획이 병합된 뒤 시작한다(런북 이름이 바뀐 뒤의 스크립트 메시지를 기준으로 한다).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-16 | Command | 시작: `plan/14-doc-rename-and-checks`를 `origin/main` `4cedf49`(PR #12 병합)에서 만들고(worktree `repo-structure` 재사용), `make new-doc TYPE=plan`으로 만든 이 계획을 첫 커밋으로 넣음(사용자 결정: 문서 PR 없이 같은 PR에서 실행). 실행은 사용자 결정대로 가능한 Task를 병렬로: Task 1 뒤 Task 2(이 worktree)와 Task 3(별도 worktree의 서브에이전트)을 함께. |
| 2026-10-16 | Verified | 사용자가 `AGENTS.md` 변경을 승인함(2026-10-16, `4cedf49` 기준): (a) 이름 변경으로 바뀌는 경로 4·30·54행, (b) Task 3 Step 1의 문구 5·41·49·60행. |
| 2026-10-16 | Verified | Task 1 RED `make test`: 이름·위치 검사와 경로 검사 실패, 레지스트리·번호 검사 통과. 시작 시점에 다시 만든 이름 변경표가 계획의 표와 같음(44행, `diff` 출력 없음). |
| 2026-10-16 | Verified | Task 1 Step 3: `git mv` 44개, perl이 76개 파일의 참조를 고침. Step 4에서 계획대로 남은 경로 다섯 묶음을 고침(계획 04 6곳, 계획 05 1곳, OCI 설계 1곳, 계획 13 2곳, 웹 UI 설계 2곳). 계획에 없던 두 가지: (1) `tests/cloud_neutral.bats`의 예외 패턴이 정규식으로 이스케이프된 `gcp-vm\.md`라 perl이 놓쳐 클라우드 이름 검사 3개가 실패함 → 새 이름으로 고침(이스케이프된 옛 이름은 이것과 계획 04 코드 블록의 기록뿐). (2) 옮긴 계획의 `](../../` 규칙이 원래부터 `docs/plans/`에 있던 이 계획의 Review Focus 문장도 바꿈 → 되돌림. |
| 2026-10-16 | Verified | Task 1 GREEN `make check`: exit 0, 210 ok, 0 not ok, 커버리지 94.51%. 스테이징한 rename 44개, 경로가 아닌 낱말만 바뀐 줄 없음(`git diff --cached -M --word-diff=porcelain`). |
| 2026-10-16 | Verified | Task 2 RED `make test`: front matter 검사 실패, `{{` 검사 통과. 계획 결함 두 가지: (1) 검사 3·5가 리뷰 폴더의 단일 파일 `docs/reviews/README.md`도 타입 문서로 셈 → 검사 2처럼 `SINGLE_FILES`를 건너뛰게 고침. (2) 계획 13 파일은 템플릿 이전에 써서 front matter가 없었음 → 다른 문서처럼 새로 닮(`status: completed`). |
| 2026-10-16 | Verified | Task 2: 표대로 45개(이름을 바꾼 44개와 ARCHITECTURE)에 front matter를 닮. 머리의 상태 줄 19곳을 정리함(상태 낱말과 날짜만 지움, 상태만 있던 ADR 0003~0006 줄과 ADR 0004의 "일부 대체" 줄은 지움, 조사 문서는 "YYYY-MM-DD 시점의 스냅샷이다"로). OCI 설계의 "이전 상태" 줄은 기록이라 둠. GCP 설계 4·8행과 웹 UI 설계 4행의 낡은 계획 상태 문구를 고침. GREEN `make check` exit 0, 0 not ok. |
| 2026-10-16 | Verified | Task 3(서브에이전트, 별도 worktree, Task 2와 병렬): `ff6e7b5`(브랜치 `plan/14-doc-rename-and-checks-t3`), 파일 9개. 그쪽 `make check` 210 ok, 94.51%, `AGENTS.md` 9,216바이트. Step 3의 grep은 승인된 새 문구 4줄에도 걸림(`make check`는 Progress log, CI는 PR 본문을 한 줄에 함께 말함). 옛 지시는 남지 않음. |
