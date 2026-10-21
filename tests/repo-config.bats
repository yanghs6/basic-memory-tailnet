#!/usr/bin/env bats
load helpers

# Antigravity truncates a rule file at 24,000 bytes, the smallest limit of the four agents
# (docs/research/rsch-2026-10-15-agent-repo-conventions.md, section 1).
AGENTS_MD_MAX_BYTES=24000

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
  timeout="$(sed -nE 's/^readonly HEALTH_TIMEOUT_SECONDS=([0-9]+)$/\1/p' "$REPO_DIR/scripts/lib/vm.sh")"
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
  # shellcheck disable=SC2016 # the compose text ${SB_USER:?...} is matched literally
  grep -qF 'SB_USER: ${SB_USER:?' <<<"$sb" \
    || fail 'SB_USER must read ${SB_USER:?...} so compose refuses to start SilverBullet without a login'
  grep -qxF '      SB_SHELL_BACKEND: "off"' <<<"$sb" || fail 'silverbullet must set SB_SHELL_BACKEND: "off"'
  grep -qxF '      SB_RUNTIME_API: "0"' <<<"$sb" || fail 'silverbullet must set SB_RUNTIME_API: "0"'
  grep -qxF '    networks: [silverbullet]' <<<"$sb" || fail "silverbullet must use only its own network"
  grep -qxF '    networks: [basic-memory]' <<<"$bm" || fail "basic-memory must use only its own network"
  # shellcheck disable=SC2016 # the compose text ${BM_KNOWLEDGE_DIR...} is matched literally
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
  assert_line "          command: '\"\$CLAUDE_PROJECT_DIR\"/scripts/guard-reviewer-bash.sh || exit 2'"
  [[ -x "$REPO_DIR/scripts/guard-reviewer-bash.sh" ]] || fail "scripts/guard-reviewer-bash.sh must exist and be executable"
  run grep -F "git status" "$agent"
  assert_failure 1
}

# reviewer_hook_command: the hook command line from the branch-reviewer agent frontmatter.
reviewer_hook_command() {
  frontmatter "$REPO_DIR/.claude/agents/branch-reviewer.md" | sed -n "s/^ *command: '\(.*\)'\$/\1/p"
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
