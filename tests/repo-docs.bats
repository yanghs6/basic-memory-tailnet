#!/usr/bin/env bats
load helpers

# Document structure checks: location, file name and front matter only, read from the registry in docs/README.md
# (doc system spec section 8.3). ADR 0007 allows these checks; ADR 0004 still bans checks on wording.

# Files under docs/ that keep their names and belong to no type (spec section 3.1).
SINGLE_FILES="docs/README.md docs/ARCHITECTURE.md docs/reviews/README.md"
ALLOWED_KEYS="status date spec reviewed superseded-by amended-by"
# docs/ARCHITECTURE.md is outside the registry but carries status and reviewed (spec section 3.2).
ARCHITECTURE_ROW="$(printf 'architecture\tarch\t없음\tdocs/\tcurrent\tstatus, reviewed\t금지\t없음')"

setup() {
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
  TYPES="$(doc_types "$REPO_DIR/docs/README.md")" || fail "the registry under '## 문서 타입' in docs/README.md does not parse"
}

# doc_files: every tracked file under docs/ and every new (untracked, not ignored) Markdown file there, one per line,
# relative to the repo. New files other than Markdown (.DS_Store, editor swap files) are local clutter, not documents.
doc_files() {
  git -C "$REPO_DIR" ls-files --cached -- docs
  git -C "$REPO_DIR" ls-files --others --exclude-standard -- 'docs/*.md'
}

# type_row FILE: the registry row whose folder holds FILE directly; nothing when no type owns that folder.
type_row() {
  awk -F'\t' -v loc="${1%/*}/" '$4 == loc' <<<"$TYPES"
}

# docs_paths: the docs/...md paths of this repo in stdin, one per line. A match right after a path character is part
# of a URL or another path (code.claude.com/docs/..., design-docs/...), and "..." marks a placeholder; both are skipped.
docs_paths() {
  { grep -oE '(^|[^A-Za-z0-9_./-])docs/[A-Za-z0-9_./-]+\.md' || true; } | sed -E 's#^[^d]##' | { grep -vF '...' || true; }
}

# link_targets: the relative link targets in stdin without their #anchor, one per line; external URLs and bare anchors
# are left out.
link_targets() {
  { grep -oE '\]\([^)]+\)' || true; } | sed -E 's/^\]\((.*)\)$/\1/; s/#.*$//' | { grep -vE '^(https?:|mailto:|$)' || true; }
}

# path_refs: one "file<TAB>kind<TAB>target" line per path the repo names, with file relative to the repo.
# kind link: a relative link outside code in tracked Markdown; its target resolves from the file's folder.
# kind docs: a docs/...md path in AGENTS.md, scripts and skills (code included) or outside code in the other tracked
# Markdown; its target resolves from the repo.
path_refs() {
  local file
  cd "$REPO_DIR" || return 1
  for file in AGENTS.md $(git ls-files scripts .agents/skills); do
    docs_paths <"$file" | awk -v f="$file" '{ print f "\tdocs\t" $0 }'
  done
  while IFS= read -r file; do
    outside_code "$file" | link_targets | awk -v f="$file" '{ print f "\tlink\t" $0 }'
    case "$file" in
      AGENTS.md | .agents/skills/*) ;;
      *) outside_code "$file" | docs_paths | awk -v f="$file" '{ print f "\tdocs\t" $0 }' ;;
    esac
  done <<<"$(markdown_files)"
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

@test "plan and ADR numbers are unique" {
  local type code number location rest dups dup bad=""
  while IFS=$'\t' read -r type code number location rest; do
    [[ "$number" != "없음" ]] || continue
    dups="$(doc_files | grep "^$location$code-" | sed -E "s#^$location$code-[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]+)-.*#\1#" | sort | uniq -d)"
    for dup in $dups; do
      bad="$bad"$'\n'"  $type $dup: $(doc_files | grep -E "^$location$code-[0-9]{4}-[0-9]{2}-[0-9]{2}-$dup-" | tr '\n' ' ')"
    done
  done <<<"$TYPES"
  [[ -z "$bad" ]] || fail "renumber one document of each pair with git mv (make new-doc picks the next free number):$bad"
}

@test "every relative link and every docs path in tracked Markdown, scripts, skills and AGENTS.md resolves" {
  local refs file kind target links=0 docs=0 broken=""
  [[ -f "$REPO_DIR/README.md" ]] || fail "README.md is missing"
  refs="$(path_refs)" || fail "could not collect the links and docs paths"
  while IFS=$'\t' read -r file kind target; do
    case "$kind" in
      link)
        links=$((links + 1))
        [[ -e "$(cd "$REPO_DIR/$(dirname "$file")" && realpath -m "$target")" ]] || broken="$broken"$'\n'"  $file: link $target"
        ;;
      docs)
        docs=$((docs + 1))
        [[ -f "$REPO_DIR/$target" ]] || broken="$broken"$'\n'"  $file: $target"
        ;;
    esac
  done <<<"$(sort -u <<<"$refs")"
  ((links > 0 && docs > 0)) || fail "checked $links relative links and $docs docs paths; expected some of each"
  [[ -z "$broken" ]] || fail "these paths name no file; point them at the current file, or spell out a deleted one:$broken"
}

# name_problem FILE ROW: a line when the name of FILE is not <code>-<date>[-<number>]-<slug>.md of its registry ROW.
name_problem() {
  local file="$1" code number pattern hint
  IFS=$'\t' read -r _ code number _ <<<"$2"
  pattern="^${code}-${DOC_DATE_PATTERN}-"
  hint="$code-<YYYY-MM-DD>-<slug>.md"
  if [[ "$number" != "없음" ]]; then
    pattern="${pattern}[0-9]{${#number}}-"
    hint="$code-<YYYY-MM-DD>-$number-<slug>.md"
  fi
  pattern="${pattern}[a-z0-9]+(-[a-z0-9]+)*[.]md$"
  [[ "${file##*/}" =~ $pattern ]] || printf '%s: name it %s (git mv)\n' "$file" "$hint"
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
    [[ -z "$value" || "$value" =~ ^${DOC_DATE_PATTERN}$ ]] || printf '%s: %s %s is not YYYY-MM-DD\n' "$file" "$key" "$value"
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

# doc_problems: one line per problem of a file under docs/: no type owns its folder, its name, its front matter, or a
# template blank left outside code. ARCHITECTURE gets only the front matter check (with ARCHITECTURE_ROW).
doc_problems() {
  local file row
  while IFS= read -r file; do
    if [[ "$file" == docs/ARCHITECTURE.md ]]; then
      front_problems "$file" "$ARCHITECTURE_ROW"
      continue
    fi
    case " $SINGLE_FILES " in *" $file "*) continue ;; esac
    row="$(type_row "$file")"
    if [[ -z "$row" ]]; then
      printf '%s: no document type owns %s/\n' "$file" "${file%/*}"
      continue
    fi
    name_problem "$file" "$row"
    front_problems "$file" "$row"
    # shellcheck disable=SC2016 # the backticks are a literal sed pattern for Markdown code spans
    if outside_code "$REPO_DIR/$file" | sed 's/`[^`]*`//g' | grep -q '{{'; then
      printf '%s: fill each {{...}} blank or delete its line\n' "$file"
    fi
  done <<<"$(doc_files)"
}

@test "every file under docs/ is a single file or a typed document with a valid name, front matter and no template blank" {
  local problems
  [[ -n "$(doc_files)" ]] || fail "git lists no files under docs/"
  problems="$(doc_problems)"
  [[ -z "$problems" ]] || fail "fix these files under docs/ (rules and metadata: docs/README.md):"$'\n'"$problems"
}

@test "every gcloud command in runbooks, README.md and docs/ARCHITECTURE.md names the bm-personal configuration" {
  local file hits line status missing="" checked=0
  # Skills name no gcloud command at all: tests/repo-cloud-neutral.bats fails on one.
  for file in "$REPO_DIR"/docs/runbooks/*.md "$REPO_DIR/README.md" "$REPO_DIR/docs/ARCHITECTURE.md"; do
    status=0
    hits="$(grep -nE 'gcloud [a-z]' "$file")" || status=$?
    ((status <= 1)) || fail "grep failed on $file (exit status $status)"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      case "$line" in
        *'gcloud config configurations create'* | *'gcloud config configurations list'*) continue ;;
      esac
      checked=$((checked + 1))
      [[ "$line" == *'--configuration=bm-personal'* ]] || missing="$missing ${file#"$REPO_DIR"/}:${line%%:*}"
    done <<<"$hits"
  done
  ((checked > 0)) || fail "no gcloud commands were checked"
  [[ -z "$missing" ]] || fail "gcloud commands without --configuration=bm-personal:$missing"
}
