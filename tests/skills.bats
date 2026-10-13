#!/usr/bin/env bats
load helpers

# Repository skills follow the Agent Skills specification (https://agentskills.io/specification), so Claude Code,
# Codex, Gemini CLI and Antigravity load the same files. How to add or change one: the skill-authoring skill.

MAX_NAME_CHARS=64
MAX_DESCRIPTION_CHARS=1024
MAX_COMPATIBILITY_CHARS=500
MAX_SKILL_LINES=500
TEMPLATE="$REPO_DIR/.agents/skills/skill-authoring/assets/skill-template.md"

# field_of FILE KEY -> the one-line value of KEY in the frontmatter of FILE.
field_of() {
  frontmatter "$1" | sed -n "s/^$2: *//p"
}

# bundled_files DIR -> the files a skill ships in its subfolders, relative to DIR, one per line.
bundled_files() {
  (cd "$1" && find . -mindepth 2 -type f | sed 's#^\./##' | sort)
}

@test "at least one repository skill exists" {
  [[ -d "$REPO_DIR/.agents/skills" ]] || fail "missing directory .agents/skills"
  local skills
  skills="$(find "$REPO_DIR/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md)"
  [[ -n "$skills" ]] || fail "no .agents/skills/*/SKILL.md found"
}

@test "skills use only Agent Skills standard frontmatter keys" {
  local dir key bad=""
  for dir in $(skill_dirs); do
    # Underscores and capitals too: Claude-only keys such as when_to_use must not slip through.
    for key in $(frontmatter "$dir/SKILL.md" | grep -oE '^[A-Za-z0-9_-]+:' | tr -d ':'); do
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

@test "skill names are lowercase words joined by single hyphens, at most 64 characters" {
  local dir name bad=""
  for dir in $(skill_dirs); do
    name="$(basename "$dir")"
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || bad="$bad $name(characters)"
    ((${#name} <= MAX_NAME_CHARS)) || bad="$bad $name(length ${#name})"
  done
  [[ -z "$bad" ]] || fail "rename these skills (a-z, 0-9 and single inner hyphens, at most $MAX_NAME_CHARS):$bad"
}

@test "frontmatter values fit on one line; only metadata holds nested keys" {
  local dir bad=""
  for dir in $(skill_dirs); do
    frontmatter "$dir/SKILL.md" | awk '/^[A-Za-z0-9_-]+:/ { key = $1; next } key != "metadata:" { bad = 1 } END { exit bad }' \
      || bad="$bad $(basename "$dir")"
  done
  [[ -z "$bad" ]] || fail "multi-line frontmatter values (folded or wrapped) in:$bad"
}

@test "skill descriptions are plain YAML of at most 1024 characters that say when to use the skill" {
  local dir description bad=""
  for dir in $(skill_dirs); do
    description="$(field_of "$dir/SKILL.md" description)"
    ((${#description} <= MAX_DESCRIPTION_CHARS)) || bad="$bad $(basename "$dir")(length ${#description})"
    # ': ' or ' #' end a plain YAML scalar early; a leading quote or block marker changes how parsers read it.
    case "$description" in
      *': '* | *' #'* | [\"\'\>\|]*) bad="$bad $(basename "$dir")(YAML)" ;;
    esac
    # Angle brackets look like XML tags, which the Claude API rejects in skill metadata.
    [[ "$description" != *[\<\>]* ]] || bad="$bad $(basename "$dir")(angle brackets)"
    [[ "$description" == *'Use when'* ]] || bad="$bad $(basename "$dir")(no 'Use when')"
  done
  [[ -z "$bad" ]] || fail "fix these descriptions:$bad"
}

@test "an optional compatibility field is at most 500 characters" {
  local dir compatibility
  for dir in $(skill_dirs); do
    compatibility="$(field_of "$dir/SKILL.md" compatibility)"
    ((${#compatibility} <= MAX_COMPATIBILITY_CHARS)) \
      || fail "$(basename "$dir"): compatibility has ${#compatibility} characters (max $MAX_COMPATIBILITY_CHARS)"
  done
}

@test "every SKILL.md is at most 500 lines" {
  local dir lines
  for dir in $(skill_dirs); do
    lines="$(wc -l <"$dir/SKILL.md")"
    ((lines <= MAX_SKILL_LINES)) || fail "$dir/SKILL.md has $lines lines; move reference material into separate files"
  done
}

@test "skill folders hold only SKILL.md and the scripts, references, assets and agents folders" {
  local dir entry bad=""
  for dir in $(skill_dirs); do
    for entry in "$dir"/* "$dir"/.[!.]*; do
      [[ -e "$entry" ]] || continue
      case "$(basename "$entry")" in
        SKILL.md | scripts | references | assets | agents) ;;
        *) bad="$bad ${entry#"$REPO_DIR"/}" ;;
      esac
    done
  done
  [[ -z "$bad" ]] || fail "move these into references/, scripts/ or assets/ (or out of the skill):$bad"
}

@test "no SKILL.md is nested inside a skill folder" {
  local nested
  nested="$(find "$REPO_DIR/.agents/skills" -mindepth 3 -iname SKILL.md)"
  [[ -z "$nested" ]] || fail "scanners would load these as separate skills; rename them:"$'\n'"$nested"
}

@test "every bundled file is named in its SKILL.md" {
  local dir file orphans=""
  for dir in $(skill_dirs); do
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      grep -qF "$file" "$dir/SKILL.md" || orphans="$orphans $(basename "$dir")/$file"
    done <<<"$(bundled_files "$dir")"
  done
  [[ -z "$orphans" ]] || fail "agents never find files SKILL.md does not name; link them (say when to read them):$orphans"
}

@test "reference files point to no other file of their skill (one level deep)" {
  local hits
  hits="$(grep -rnE '\]\([A-Za-z0-9_.-]+\.md|references/' "$REPO_DIR"/.agents/skills/*/references 2>/dev/null)" || true
  [[ -z "$hits" ]] || fail "link every reference file from SKILL.md instead:"$'\n'"$hits"
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

@test ".claude/skills holds only links to existing canonical skills" {
  local entry name
  for entry in "$REPO_DIR"/.claude/skills/*; do
    name="$(basename "$entry")"
    [[ -L "$entry" ]] || fail ".claude/skills/$name is not a link; keep the skill in .agents/skills/$name"
    [[ -f "$REPO_DIR/.agents/skills/$name/SKILL.md" ]] || fail ".claude/skills/$name points to no skill; remove the stale link"
  done
}

@test "AGENTS.md and README.md list every skill" {
  local dir name skills_section missing=""
  skills_section="$(awk '/^## / { inside = ($0 == "## Skills") } inside' "$REPO_DIR/AGENTS.md")"
  [[ -n "$skills_section" ]] || fail "AGENTS.md has no '## Skills' section"
  for dir in $(skill_dirs); do
    name="$(basename "$dir")"
    grep -qF "\`$name\`" <<<"$skills_section" || missing="$missing AGENTS.md:$name"
    grep -qF "\`$name\`" "$REPO_DIR/README.md" || missing="$missing README.md:$name"
  done
  [[ -z "$missing" ]] || fail "add the skill to the list:$missing"
}

@test "skills never rely on an exported AGENT_ID surviving between commands" {
  # Agent shells often start fresh per command; an unset $AGENT_ID writes an empty Assisted-by trailer.
  run grep -rnE 'export AGENT_ID|\$AGENT_ID|\$\{AGENT_ID\}' "$REPO_DIR/.agents/skills"
  assert_failure 1
}

@test "operational skills bm-upgrade, bm-recover and bm-diagnose exist" {
  local name
  for name in bm-upgrade bm-recover bm-diagnose; do
    [[ -f "$REPO_DIR/.agents/skills/$name/SKILL.md" ]] || fail "missing .agents/skills/$name/SKILL.md"
  done
}

@test "the skill-authoring template starts with standard frontmatter" {
  [[ -f "$TEMPLATE" ]] || fail "missing ${TEMPLATE#"$REPO_DIR"/}"
  run frontmatter "$TEMPLATE"
  assert_line --regexp '^name: '
  assert_line --regexp '^description: .+ Use when .+ Not for '
  refute_line --regexp '^(when_to_use|disable-model-invocation|user-invocable|argument-hint|context|model):'
}
