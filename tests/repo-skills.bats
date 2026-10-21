#!/usr/bin/env bats
load helpers

# Repository skills follow the Agent Skills specification (https://agentskills.io/specification), so Claude Code,
# Codex, Gemini CLI and Antigravity load the same files. How to add or change one: the skill-authoring skill.

# The length limits of the specification: frontmatter key and maximum characters.
MAX_FIELD_CHARS="name 64
description 1024
compatibility 500"
MAX_SKILL_LINES=500

# bundled_files DIR -> the files a skill ships in its subfolders, relative to DIR, one per line.
bundled_files() {
  (cd "$1" && find . -mindepth 2 -type f | sed 's#^\./##' | sort)
}

@test "every SKILL.md frontmatter uses only standard keys on one line, the directory name in the name format, a plain description with 'Use when' and length limits" {
  local dirs dir skill file key description limit value bad=""
  dirs="$(skill_dirs)"
  [[ -n "$dirs" ]] || fail "found no skills under .agents/skills"
  for dir in $dirs; do
    skill="$(basename "$dir")"
    file="$dir/SKILL.md"
    # Underscores and capitals too: Claude-only keys such as when_to_use must not slip through.
    for key in $(frontmatter "$file" | grep -oE '^[A-Za-z0-9_-]+:' | tr -d ':'); do
      case "$key" in
        name | description | license | compatibility | metadata | allowed-tools) ;;
        *) bad="$bad $skill(non-standard key $key: Codex and Antigravity may reject it)" ;;
      esac
    done
    # Frontmatter values stay on one line; only metadata holds nested keys.
    frontmatter "$file" | awk '/^[A-Za-z0-9_-]+:/ { key = $1; next } key != "metadata:" { bad = 1 } END { exit bad }' \
      || bad="$bad $skill(multi-line frontmatter)"
    [[ "$(front_value "$file" name)" == "$skill" ]] || bad="$bad $skill(name must equal the directory name)"
    # The directory name equals the skill name, so checking the directory checks the name format.
    [[ "$skill" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || bad="$bad $skill(name: use a-z, 0-9 and single inner hyphens)"
    description="$(front_value "$file" description)"
    [[ -n "$description" ]] || bad="$bad $skill(no description)"
    # ': ' or ' #' end a plain YAML scalar early; a leading quote or block marker changes how parsers read it.
    case "$description" in
      *': '* | *' #'* | [\"\'\>\|]*) bad="$bad $skill(description is not plain YAML)" ;;
    esac
    # Angle brackets look like XML tags, which the Claude API rejects in skill metadata.
    [[ "$description" != *[\<\>]* ]] || bad="$bad $skill(angle brackets in the description)"
    [[ "$description" == *'Use when'* ]] || bad="$bad $skill(no 'Use when' in the description)"
    while read -r key limit; do
      value="$(front_value "$file" "$key")"
      ((${#value} <= limit)) || bad="$bad $skill($key has ${#value} characters, max $limit)"
    done <<<"$MAX_FIELD_CHARS"
  done
  [[ -z "$bad" ]] || fail "fix the SKILL.md frontmatter of:$bad"
}

@test "every SKILL.md is at most 500 lines" {
  local dir lines
  for dir in $(skill_dirs); do
    lines="$(wc -l <"$dir/SKILL.md")"
    ((lines <= MAX_SKILL_LINES)) || fail "$dir/SKILL.md has $lines lines; move reference material into separate files"
  done
}

@test "skill folders hold only SKILL.md and the allowed folders, with no nested SKILL.md" {
  local dirs dir entry found nested bad=""
  dirs="$(skill_dirs)"
  [[ -n "$dirs" ]] || fail "found no skills under .agents/skills"
  for dir in $dirs; do
    for entry in "$dir"/* "$dir"/.[!.]*; do
      [[ -e "$entry" ]] || continue
      case "$(basename "$entry")" in
        SKILL.md | scripts | references | assets | agents) ;;
        *) bad="$bad"$'\n'"  ${entry#"$REPO_DIR"/}: move it into references/, scripts/ or assets/ (or out of the skill)" ;;
      esac
    done
    found="$(find "$dir" -mindepth 2 -iname SKILL.md)" || fail "find could not search ${dir#"$REPO_DIR"/} for nested SKILL.md files"
    while IFS= read -r nested; do
      [[ -n "$nested" ]] || continue
      bad="$bad"$'\n'"  ${nested#"$REPO_DIR"/}: scanners would load it as a separate skill; rename it"
    done <<<"$found"
  done
  [[ -z "$bad" ]] || fail "fix these skill folders:$bad"
}

@test "every bundled file is named in SKILL.md and reference files point to no other file of their skill" {
  local dirs dir skill file bundled=0 bad=""
  dirs="$(skill_dirs)"
  [[ -n "$dirs" ]] || fail "found no skills under .agents/skills"
  for dir in $dirs; do
    skill="$(basename "$dir")"
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      bundled=$((bundled + 1))
      grep -qF "$file" "$dir/SKILL.md" \
        || bad="$bad"$'\n'"  $skill/$file: agents never find a file SKILL.md does not name; link it (say when to read it)"
    done <<<"$(bundled_files "$dir")"
    [[ -d "$dir/references" ]] || continue
    # One level deep: SKILL.md links every reference file, so a reference file links no other file of its skill.
    refute_matches "$dir/references" '\]\([A-Za-z0-9_.-]+\.md|references/' \
      || bad="$bad"$'\n'"  $skill/references: link every reference file from SKILL.md instead (lines above)"
  done
  ((bundled > 0)) || fail "found no bundled files in the skill subfolders"
  [[ -z "$bad" ]] || fail "fix these skill files:$bad"
}

@test "every skill is linked both ways and listed in AGENTS.md and README.md" {
  local dirs dir name link entry skills_section bad=""
  dirs="$(skill_dirs)"
  [[ -n "$dirs" ]] || fail "found no skills under .agents/skills"
  skills_section="$(awk '/^## / { inside = ($0 == "## Skills") } inside' "$REPO_DIR/AGENTS.md")"
  [[ -n "$skills_section" ]] || fail "AGENTS.md has no '## Skills' section"
  for dir in $dirs; do
    name="$(basename "$dir")"
    link="$REPO_DIR/.claude/skills/$name"
    if [[ ! -L "$link" ]]; then
      bad="$bad"$'\n'"  $name: missing link; run: ln -s ../../.agents/skills/$name .claude/skills/$name"
    elif [[ "$(readlink "$link")" != "../../.agents/skills/$name" ]]; then
      bad="$bad"$'\n'"  $name: .claude/skills/$name must point to ../../.agents/skills/$name"
    fi
    grep -qF "\`$name\`" <<<"$skills_section" || bad="$bad"$'\n'"  $name: add it to '## Skills' in AGENTS.md"
    grep -qF "\`$name\`" "$REPO_DIR/README.md" || bad="$bad"$'\n'"  $name: add it to the skill list in README.md"
  done
  for entry in "$REPO_DIR"/.claude/skills/*; do
    name="$(basename "$entry")"
    [[ -L "$entry" ]] || bad="$bad"$'\n'"  .claude/skills/$name is not a link; keep the skill in .agents/skills/$name"
    [[ -f "$REPO_DIR/.agents/skills/$name/SKILL.md" ]] || bad="$bad"$'\n'"  .claude/skills/$name points to no skill; remove the stale link"
  done
  [[ -z "$bad" ]] || fail "fix the skill registration:$bad"
}

@test "skills never rely on an exported AGENT_ID surviving between commands" {
  # Agent shells often start fresh per command; an unset $AGENT_ID writes an empty Assisted-by trailer.
  # shellcheck disable=SC2016 # the grep pattern matches the literal text $AGENT_ID
  refute_matches "$REPO_DIR/.agents/skills" 'export AGENT_ID|\$AGENT_ID|\$\{AGENT_ID\}'
}
