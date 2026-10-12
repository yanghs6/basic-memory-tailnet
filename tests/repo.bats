#!/usr/bin/env bats
load helpers

shell_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*'
}

# require_shell_files: set $files to the tracked shell files; fail loudly if git is unusable (no vacuous passes).
require_shell_files() {
  files="$(shell_files)" || fail "git ls-files failed inside the test container (see Makefile GIT_COMMON_DIR mount)"
  [[ "$files" == *tests/stubs/ssh* ]] || fail "git returned no files (expected at least tests/stubs/ssh)"
}

@test "every executable shell file enables strict mode" {
  local file files missing=""
  require_shell_files
  while IFS= read -r file; do
    case "$file" in
      *.bash | scripts/lib/*) continue ;;
    esac
    grep -qx 'set -euo pipefail' "$REPO_DIR/$file" || missing="$missing $file"
  done <<<"$files"
  [[ -z "$missing" ]] || fail "add 'set -euo pipefail' right after the shebang in:$missing"
}

@test "every script and stub is executable" {
  local file files missing=""
  require_shell_files
  while IFS= read -r file; do
    case "$file" in
      *.bash | scripts/lib/*) continue ;;
    esac
    [[ -x "$REPO_DIR/$file" ]] || missing="$missing $file"
  done <<<"$files"
  [[ -z "$missing" ]] || fail "run: chmod +x$missing"
}

@test "scripts avoid bash 4+ features (macOS ships bash 3.2)" {
  run grep -rnE 'mapfile|readarray|declare -[Ann]|local -[Ann]|inherit_errexit|coproc|wait -n|\|&|&>>|\$\{[A-Za-z_][A-Za-z0-9_]*(\^|,)|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]' "$REPO_DIR/scripts"
  assert_failure 1
}

@test "every Make target has a ## description" {
  local missing
  missing="$(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | grep -v '## ' | cut -d: -f1 || true)"
  [[ -z "$missing" ]] || fail "add '## <description>' to these Makefile targets: $missing"
}

@test "every documented Make target is declared .PHONY" {
  local phony target missing=""
  phony=" $(grep -E '^\.PHONY:' "$REPO_DIR/Makefile" | cut -d: -f2 | tr '\n' ' ') "
  for target in $(grep -oE '^[a-z0-9-]+:.*## ' "$REPO_DIR/Makefile" | cut -d: -f1); do
    [[ "$phony" == *" $target "* ]] || missing="$missing $target"
  done
  [[ -z "$missing" ]] || fail "add these targets to .PHONY in the Makefile:$missing"
}

@test "no Make target is defined twice" {
  local dupes
  dupes="$(grep -oE '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | cut -d: -f1 | sort | uniq -d)"
  [[ -z "$dupes" ]] || fail "these Make targets are defined more than once (make keeps only the last recipe): $dupes"
}

@test "make help lists every documented target" {
  # kcov exports xtrace settings that break the `bash -u` shell make spawns; the Makefile needs no tracing.
  run env -u SHELLOPTS -u PS4 -u BASH_ENV make -s -C "$REPO_DIR" help
  assert_success
  local target
  for target in $(grep -oE '^[a-z0-9-]+:.*## ' "$REPO_DIR/Makefile" | cut -d: -f1); do
    assert_output --partial "  $target "
  done
}

@test "compose pins the Basic Memory image by digest" {
  run grep -E '^ +image: ghcr\.io/basicmachines-co/basic-memory:[0-9.]+@sha256:[0-9a-f]{64}$' "$REPO_DIR/compose.yaml"
  assert_success
}

@test "compose publishes ports on 127.0.0.1 only" {
  local ports
  ports="$(awk '/^ +ports:/ { p = 1; next } p && /^ +- / { print; next } p { p = 0 }' "$REPO_DIR/compose.yaml")"
  [[ -n "$ports" ]] || fail "compose.yaml has no ports entries"
  if grep -vqE '^ +- "127\.0\.0\.1:' <<<"$ports"; then
    fail "every published port must start with \"127.0.0.1: (Basic Memory has no auth): $ports"
  fi
}

@test "compose overrides the image's default SSE command with streamable-http on /mcp" {
  run grep -F '"--transport", "streamable-http"' "$REPO_DIR/compose.yaml"
  assert_success
  run grep -F '"--path", "/mcp"' "$REPO_DIR/compose.yaml"
  assert_success
}

@test "compose healthcheck probes port 8000 and does not rely on --version" {
  local healthcheck
  healthcheck="$(grep -E '^ +test: \[' "$REPO_DIR/compose.yaml")"
  [[ -n "$healthcheck" ]] || fail "compose.yaml has no healthcheck test"
  [[ "$healthcheck" != *"--version"* ]] || fail "healthcheck must not use --version (passes while the server is down)"
  [[ "$healthcheck" == *"8000"* ]] || fail "healthcheck must probe port 8000"
}

@test "compose restarts the container after reboots" {
  run grep -E '^ +restart: unless-stopped$' "$REPO_DIR/compose.yaml"
  assert_success
}

@test ".env is never tracked by git" {
  local files
  files="$(git -C "$REPO_DIR" ls-files)" || fail "git ls-files failed"
  [[ -n "$files" ]] || fail "git ls-files returned nothing"
  if grep -qE '(^|/)\.env$' <<<"$files"; then
    fail ".env must never be tracked by git"
  fi
}

@test ".env.example has only comments and unquoted KEY=value lines" {
  [[ -f "$REPO_DIR/.env.example" ]] || fail "create .env.example"
  local bad
  bad="$(grep -vE '^(#.*|[A-Z][A-Z0-9_]*=[^"'"'"' ]*|)$' "$REPO_DIR/.env.example" || true)"
  [[ -z "$bad" ]] || fail "make reads quotes and spaces literally; fix these .env.example lines: $bad"
}

@test "AGENTS.md stays a short map (at most 100 lines)" {
  local lines
  lines="$(wc -l <"$REPO_DIR/AGENTS.md")"
  ((lines <= 100)) || fail "AGENTS.md has $lines lines; move detail into docs/ and point to it"
}

@test "CLAUDE.md only imports AGENTS.md" {
  run cat "$REPO_DIR/CLAUDE.md"
  assert_output "@AGENTS.md"
}

@test ".env variants are git-ignored but .env.example is not" {
  run git -C "$REPO_DIR" check-ignore -q .env.local
  assert_success
  run git -C "$REPO_DIR" check-ignore -q .env.production
  assert_success
  run git -C "$REPO_DIR" check-ignore -q .env.example
  assert_failure 1
}

skill_dirs() {
  find "$REPO_DIR/.agents/skills" -mindepth 1 -maxdepth 1 -type d | sort
}

frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1"
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

@test "skills never rely on an exported AGENT_ID surviving between commands" {
  # Agent shells often start fresh per command; an unset $AGENT_ID writes an empty Assisted-by trailer.
  run grep -rnE 'export AGENT_ID|\$AGENT_ID|\$\{AGENT_ID\}' "$REPO_DIR/.agents/skills"
  assert_failure 1
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

@test "the Claude reviewer agent runs every Bash call through the read-only guard hook" {
  local agent="$REPO_DIR/.claude/agents/branch-reviewer.md"
  run frontmatter "$agent"
  assert_line "hooks:"
  assert_line "  PreToolUse:"
  assert_line '    - matcher: "Bash"'
  assert_line "      hooks:"
  assert_line "        - type: command"
  assert_line "          command: '\"\$CLAUDE_PROJECT_DIR\"/scripts/review-bash-guard.sh || exit 2'"
  [[ -x "$REPO_DIR/scripts/review-bash-guard.sh" ]] || fail "scripts/review-bash-guard.sh must exist and be executable"
  run grep -F "git status" "$agent"
  assert_failure 1
}

# reviewer_hook_command: the hook command line from the branch-reviewer agent frontmatter.
reviewer_hook_command() {
  frontmatter "$REPO_DIR/.claude/agents/branch-reviewer.md" | sed -n "s/^ *command: '\(.*\)'\$/\1/p"
}

@test "no script enables Tailscale Funnel" {
  run grep -rniE 'tailscale[[:space:]]+funnel' "$REPO_DIR/scripts"
  assert_failure 1
}

@test "the reviewer hook command blocks (exit 2) even when the guard script is missing" {
  # Only exit 2 blocks a tool call; a missing script exits 127, which would let the call through.
  local hook input='{"tool_input": {"command": "git diff"}}'
  hook="$(reviewer_hook_command)"
  [[ -n "$hook" ]] || fail "no hook command found in .claude/agents/branch-reviewer.md"
  mkdir -p "$BATS_TEST_TMPDIR/no-guard"
  CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/no-guard" run sh -c "$hook" <<<"$input"
  assert_failure 2
  CLAUDE_PROJECT_DIR="$REPO_DIR" run sh -c "$hook" <<<"$input"
  assert_success
}

@test "operational skills bm-upgrade, bm-recover and bm-diagnose exist" {
  local name
  for name in bm-upgrade bm-recover bm-diagnose; do
    [[ -f "$REPO_DIR/.agents/skills/$name/SKILL.md" ]] || fail "missing .agents/skills/$name/SKILL.md"
  done
}

markdown_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.md'
}

# markdown_links FILE -> the link targets of FILE, one per line, ignoring fenced code blocks and external URLs.
# grep exits 1 when a file has no links, which is fine; exit 2 (a real error) must surface.
markdown_links() {
  local links status=0
  links="$(awk '/^```/ { fence = !fence; next } !fence' "$REPO_DIR/$1" | grep -oE '\]\([^)]+\)')" || status=$?
  ((status <= 1)) || return "$status"
  if [[ -n "$links" ]]; then
    sed -E 's/^\]\((.*)\)$/\1/' <<<"$links" | grep -vE '^(https?:|mailto:)' || [[ $? -eq 1 ]]
  fi
}

@test "relative links in markdown files resolve" {
  local files file link target broken="" checked=0
  files="$(markdown_files)" || fail "git ls-files failed"
  [[ -n "$files" ]] || fail "git returned no markdown files"
  [[ -f "$REPO_DIR/README.md" ]] || fail "README.md is missing"
  while IFS= read -r file; do
    while IFS= read -r link; do
      link="${link%%#*}"
      [[ -n "$link" ]] || continue
      checked=$((checked + 1))
      target="$(cd "$REPO_DIR/$(dirname "$file")" && realpath -m "$link")"
      [[ -e "$target" ]] || broken="$broken $file->$link"
    done < <(markdown_links "$file")
  done <<<"$files"
  ((checked > 0)) || fail "no relative links were checked"
  [[ -z "$broken" ]] || fail "broken relative links:$broken"
}

@test "every docs markdown path named in scripts, skills and AGENTS.md exists" {
  local path missing="" count=0 paths
  paths="$(grep -rhoE 'docs/[A-Za-z0-9_./-]+\.md' "$REPO_DIR/scripts" "$REPO_DIR/.agents/skills" "$REPO_DIR/AGENTS.md" | sort -u)" \
    || fail "found no docs/*.md references to check"
  while IFS= read -r path; do
    count=$((count + 1))
    [[ -f "$REPO_DIR/$path" ]] || missing="$missing $path"
  done <<<"$paths"
  ((count > 0)) || fail "no docs paths were checked"
  [[ -z "$missing" ]] || fail "referenced docs do not exist:$missing"
}

@test "runbooks contain the sections scripts and skills point to" {
  run grep -E '^## (Exposure audit|Idle reclamation|Incident log)' "$REPO_DIR/docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md"
  assert_success
  assert_line --partial "Exposure audit"
  assert_line --partial "Idle reclamation"
  assert_line --partial "Incident log"
}
