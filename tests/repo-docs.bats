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
