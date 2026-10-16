#!/usr/bin/env bats
load helpers

# Antigravity truncates a rule file at 24,000 bytes, the smallest limit of the four agents
# (docs/research/2026-10-15-agent-repo-conventions.md, section 1).
AGENTS_MD_MAX_BYTES=24000

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

@test "scripts avoid bash 4+ features (macOS ships bash 3.2)" {
  run grep -rnE 'mapfile|readarray|declare -[Ann]|local -[Ann]|inherit_errexit|coproc|wait -n|\|&|&>>|\$\{[A-Za-z_][A-Za-z0-9_]*(\^|,)|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]' "$REPO_DIR/scripts"
  assert_failure 1
}

@test "every Make target has a ## description and is declared .PHONY" {
  local line phony target missing_desc="" missing_phony=""
  phony=" $(grep -E '^\.PHONY:' "$REPO_DIR/Makefile" | cut -d: -f2 | tr '\n' ' ') "
  while IFS= read -r line; do
    target="${line%%:*}"
    [[ "$line" == *"## "* ]] || missing_desc="$missing_desc $target"
    [[ "$phony" == *" $target "* ]] || missing_phony="$missing_phony $target"
  done < <(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile")
  [[ -z "$missing_desc" ]] || fail "add '## <description>' to these Makefile targets:$missing_desc"
  [[ -z "$missing_phony" ]] || fail "add these targets to .PHONY in the Makefile:$missing_phony"
}

@test "no Make target is defined twice" {
  local dupes
  dupes="$(grep -oE '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | cut -d: -f1 | sort | uniq -d)"
  [[ -z "$dupes" ]] || fail "these Make targets are defined more than once (make keeps only the last recipe): $dupes"
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

# service_block NAME -> the lines of service NAME in compose.yaml, up to the next service or top-level key.
service_block() {
  awk -v name="$1" '$0 == "  " name ":" { inside = 1; next } inside && (/^[^ ]/ || /^  [^ ]/) { exit } inside { print }' "$REPO_DIR/compose.yaml"
}

# compose_start_period_seconds: print the Basic Memory healthcheck start_period in whole seconds (empty if absent).
compose_start_period_seconds() {
  service_block basic-memory | sed -nE 's/^ +start_period: ([0-9]+)s$/\1/p'
}

@test "compose healthcheck start_period covers the measured e2-micro cold start" {
  # Measured on the VM (plan 05 Progress log, 2026-10-13): healthy 161s after the first deploy, 192s after a reboot.
  local min_start_period_seconds=240 period
  period="$(compose_start_period_seconds)"
  [[ -n "$period" ]] || fail "compose.yaml has no healthcheck start_period in whole seconds (e.g. 300s)"
  ((period >= min_start_period_seconds)) \
    || fail "start_period ${period}s is below ${min_start_period_seconds}s: on the VM the container turns unhealthy during a cold start and 'docker compose up --wait' fails at once"
}

@test "deploy and restore wait longer than the healthcheck start_period" {
  local period timeout
  period="$(compose_start_period_seconds)"
  timeout="$(sed -nE 's/^readonly HEALTH_TIMEOUT_SECONDS=([0-9]+)$/\1/p' "$REPO_DIR/scripts/lib/common.sh")"
  [[ -n "$period" && -n "$timeout" ]] || fail "could not read start_period ('$period') or HEALTH_TIMEOUT_SECONDS ('$timeout')"
  ((timeout > period)) \
    || fail "HEALTH_TIMEOUT_SECONDS=$timeout must exceed start_period ${period}s, or --wait gives up inside the grace period"
}

@test "compose restarts both services after reboots" {
  local service
  for service in basic-memory silverbullet; do
    service_block "$service" | grep -qE '^ +restart: unless-stopped$' \
      || fail "$service must set restart: unless-stopped, or it stays down after a VM reboot"
  done
}

@test "SilverBullet is pinned, needs a login, has no shell or runtime API and shares no network or data beyond the notes" {
  local sb bm
  sb="$(service_block silverbullet)"
  bm="$(service_block basic-memory)"
  [[ -n "$sb" && -n "$bm" ]] || fail "compose.yaml must define the basic-memory and silverbullet services"
  grep -qE '^ +image: ghcr\.io/silverbulletmd/silverbullet:[0-9.]+-slim@sha256:[0-9a-f]{64}$' <<<"$sb" \
    || fail "pin the silverbullet -slim image by digest"
  grep -qF 'SB_USER: ${SB_USER:?' <<<"$sb" \
    || fail 'SB_USER must read ${SB_USER:?...} so compose refuses to start SilverBullet without a login'
  grep -qxF '      SB_SHELL_BACKEND: "off"' <<<"$sb" || fail 'silverbullet must set SB_SHELL_BACKEND: "off"'
  grep -qxF '      SB_RUNTIME_API: "0"' <<<"$sb" || fail 'silverbullet must set SB_RUNTIME_API: "0"'
  grep -qxF '    networks: [silverbullet]' <<<"$sb" || fail "silverbullet must use only its own network"
  grep -qxF '    networks: [basic-memory]' <<<"$bm" || fail "basic-memory must use only its own network"
  grep -qxF '      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}/basic-memory:/data"' <<<"$sb" \
    || fail "silverbullet must mount the notes folder at /data"
  if grep -q 'BM_CONFIG_DIR' <<<"$sb"; then
    fail "silverbullet must not mount the Basic Memory config and database"
  fi
}

@test ".env is never tracked by git" {
  local files
  files="$(git -C "$REPO_DIR" ls-files)" || fail "git ls-files failed"
  [[ -n "$files" ]] || fail "git ls-files returned nothing"
  if grep -qE '(^|/)\.env$' <<<"$files"; then
    fail ".env must never be tracked by git"
  fi
}

@test "CLAUDE.md only imports AGENTS.md" {
  run cat "$REPO_DIR/CLAUDE.md"
  assert_output "@AGENTS.md"
}

@test "Gemini CLI reads AGENTS.md through .gemini/settings.json" {
  run jq -e '.context.fileName | if type == "array" then index("AGENTS.md") != null else . == "AGENTS.md" end' \
    "$REPO_DIR/.gemini/settings.json"
  assert_success
}

@test "AGENTS.md fits the smallest rule file limit of the four agents" {
  local bytes
  bytes="$(wc -c <"$REPO_DIR/AGENTS.md")"
  ((bytes <= AGENTS_MD_MAX_BYTES)) \
    || fail "AGENTS.md has $bytes bytes (max $AGENTS_MD_MAX_BYTES; Antigravity drops the rest): move detail into docs/README.md or a skill"
}

@test ".env variants are git-ignored but .env.example is not" {
  run git -C "$REPO_DIR" check-ignore -q .env.local
  assert_success
  run git -C "$REPO_DIR" check-ignore -q .env.production
  assert_success
  run git -C "$REPO_DIR" check-ignore -q .env.example
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
  local path missing="" count=0 found paths
  # Capture grep alone: tests run without pipefail, so a pipe into sort would hide grep's exit status.
  found="$(grep -rhoE 'docs/[A-Za-z0-9_./-]+\.md' "$REPO_DIR/scripts" "$REPO_DIR/.agents/skills" "$REPO_DIR/AGENTS.md")" \
    || fail "found no docs/*.md references to check (grep exit status $?)"
  paths="$(sort -u <<<"$found")"
  while IFS= read -r path; do
    count=$((count + 1))
    [[ -f "$REPO_DIR/$path" ]] || missing="$missing $path"
  done <<<"$paths"
  ((count > 0)) || fail "no docs paths were checked"
  [[ -z "$missing" ]] || fail "referenced docs do not exist:$missing"
}

@test "every gcloud command in runbooks and skills names the bm-personal configuration" {
  local file hits line status missing="" checked=0
  for file in "$REPO_DIR"/docs/runbooks/*.md "$REPO_DIR/README.md" "$REPO_DIR/docs/ARCHITECTURE.md" "$REPO_DIR"/.agents/skills/*/SKILL.md; do
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

