#!/usr/bin/env bats
load helpers

# Antigravity truncates a rule file at 24,000 bytes, the smallest limit of the four agents
# (docs/research/rsch-2026-10-15-agent-repo-conventions.md, section 1).
AGENTS_MD_MAX_BYTES=24000
# Measured on the VM (plan 05 Progress log, 2026-10-13): healthy 161s after the first deploy, 192s after a reboot.
MIN_START_PERIOD_SECONDS=240
# An image line with a version tag and a sha256 digest.
PINNED_IMAGE='^ +image: [a-z0-9./_-]+:[0-9.]+(-[a-z]+)?@sha256:[0-9a-f]{64}$'

# service_block NAME -> the lines of service NAME in compose.yaml, up to the next service or top-level key.
service_block() {
  awk -v name="$1" '$0 == "  " name ":" { inside = 1; next } inside && (/^[^ ]/ || /^  [^ ]/) { exit } inside { print }' "$REPO_DIR/compose.yaml"
}

# compose_services: the service names under services: in compose.yaml, one per line.
compose_services() {
  awk '/^[^ ]/ { inside = ($0 == "services:"); next } inside && /^  [a-z0-9-]+:$/ { sub(/^ +/, ""); sub(/:$/, ""); print }' "$REPO_DIR/compose.yaml"
}

@test "every compose image is pinned by digest" {
  local services service images line bad=""
  services="$(compose_services)"
  [[ -n "$services" ]] || fail "compose.yaml defines no services"
  for service in $services; do
    service_block "$service" | grep -qE '^ +image:' || bad="$bad"$'\n'"  $service: no image line"
  done
  # Every image line of the file, so a service the name pattern above skips is checked too.
  images="$(grep -nE '^ +image:' "$REPO_DIR/compose.yaml")" || fail "compose.yaml has no image lines"
  while IFS= read -r line; do
    [[ "${line#*:}" =~ $PINNED_IMAGE ]] || bad="$bad"$'\n'"  compose.yaml:$line"
  done <<<"$images"
  [[ -z "$bad" ]] || fail "pin every image by digest (image: <name>:<version>@sha256:<digest>):$bad"
}

@test "compose publishes ports on 127.0.0.1 only" {
  local ports
  ports="$(awk '/^ +ports:/ { p = 1; next } p && /^ +- / { print; next } p { p = 0 }' "$REPO_DIR/compose.yaml")"
  [[ -n "$ports" ]] || fail "compose.yaml has no ports entries"
  if grep -vqE '^ +- "127\.0\.0\.1:' <<<"$ports"; then
    fail "every published port must start with \"127.0.0.1: (Basic Memory has no auth): $ports"
  fi
}

@test "basic-memory runs the basicmachines-co image, serves streamable-http on /mcp, probes port 8000 without --version, has a start_period of at least 240 s that HEALTH_TIMEOUT_SECONDS exceeds, restarts unless-stopped and uses only its own network" {
  local bm healthcheck period timeout
  bm="$(service_block basic-memory)"
  [[ -n "$bm" ]] || fail "compose.yaml must define the basic-memory service"
  grep -qE '^ +image: ghcr\.io/basicmachines-co/basic-memory:' <<<"$bm" \
    || fail "basic-memory must run the ghcr.io/basicmachines-co/basic-memory image"
  # The image's default command serves SSE.
  grep -qF '"--transport", "streamable-http"' <<<"$bm" || fail "basic-memory must run with --transport streamable-http"
  grep -qF '"--path", "/mcp"' <<<"$bm" || fail "basic-memory must serve --path /mcp"
  healthcheck="$(grep -E '^ +test: \[' <<<"$bm")" || fail "basic-memory has no healthcheck test"
  [[ "$healthcheck" != *"--version"* ]] || fail "the basic-memory healthcheck must not use --version (passes while the server is down)"
  [[ "$healthcheck" == *"8000"* ]] || fail "the basic-memory healthcheck must probe port 8000"
  period="$(sed -nE 's/^ +start_period: ([0-9]+)s$/\1/p' <<<"$bm")"
  [[ -n "$period" ]] || fail "basic-memory has no healthcheck start_period in whole seconds (e.g. 300s)"
  ((period >= MIN_START_PERIOD_SECONDS)) \
    || fail "start_period ${period}s is below ${MIN_START_PERIOD_SECONDS}s: on the VM the container turns unhealthy during a cold start and 'docker compose up --wait' fails at once"
  timeout="$(sed -nE 's/^readonly HEALTH_TIMEOUT_SECONDS=([0-9]+)$/\1/p' "$REPO_DIR/scripts/lib/vm.sh")"
  [[ -n "$timeout" ]] || fail "could not read HEALTH_TIMEOUT_SECONDS from scripts/lib/vm.sh"
  ((timeout > period)) \
    || fail "HEALTH_TIMEOUT_SECONDS=$timeout must exceed start_period ${period}s, or deploy and restore give up inside the grace period"
  grep -qE '^ +restart: unless-stopped$' <<<"$bm" || fail "basic-memory must set restart: unless-stopped, or it stays down after a VM reboot"
  grep -qxF '    networks: [basic-memory]' <<<"$bm" || fail "basic-memory must use only its own network"
}

@test "SilverBullet is a -slim image, needs a login, has no shell or runtime API, restarts unless-stopped, probes without --version and shares no network or data beyond the notes" {
  local sb healthcheck
  sb="$(service_block silverbullet)"
  [[ -n "$sb" ]] || fail "compose.yaml must define the silverbullet service"
  grep -qE '^ +image: ghcr\.io/silverbulletmd/silverbullet:[0-9.]+-slim@' <<<"$sb" || fail "use the silverbullet -slim image"
  # shellcheck disable=SC2016 # the compose text ${SB_USER:?...} is matched literally
  grep -qF 'SB_USER: ${SB_USER:?' <<<"$sb" \
    || fail 'SB_USER must read ${SB_USER:?...} so compose refuses to start SilverBullet without a login'
  grep -qxF '      SB_SHELL_BACKEND: "off"' <<<"$sb" || fail 'silverbullet must set SB_SHELL_BACKEND: "off"'
  grep -qxF '      SB_RUNTIME_API: "0"' <<<"$sb" || fail 'silverbullet must set SB_RUNTIME_API: "0"'
  grep -qE '^ +restart: unless-stopped$' <<<"$sb" || fail "silverbullet must set restart: unless-stopped, or it stays down after a VM reboot"
  healthcheck="$(grep -E '^ +test: \[' <<<"$sb")" || fail "silverbullet has no healthcheck test"
  [[ "$healthcheck" != *"--version"* ]] || fail "the silverbullet healthcheck must not use --version (passes while the server is down)"
  grep -qxF '    networks: [silverbullet]' <<<"$sb" || fail "silverbullet must use only its own network"
  # shellcheck disable=SC2016 # the compose text ${BM_KNOWLEDGE_DIR...} is matched literally
  grep -qxF '      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}/basic-memory:/data"' <<<"$sb" \
    || fail "silverbullet must mount the notes folder at /data"
  if grep -q 'BM_CONFIG_DIR' <<<"$sb"; then
    fail "silverbullet must not mount the Basic Memory config and database"
  fi
}

@test "the .env files are never tracked and are git-ignored, but .env.example is not ignored" {
  local files file tracked="" entry path expected
  files="$(git -C "$REPO_DIR" ls-files)" || fail "git ls-files failed"
  [[ -n "$files" ]] || fail "git ls-files returned nothing"
  while IFS= read -r file; do
    case "${file##*/}" in
      .env.example) ;;
      .env | .env.*) tracked="$tracked $file" ;;
    esac
  done <<<"$files"
  [[ -z "$tracked" ]] || fail "these hold secrets and must never be tracked by git:$tracked"
  # check-ignore exits 0 for an ignored path and 1 for one that is not; --no-index reads the ignore rules even for a
  # tracked path such as .env.example.
  for entry in .env:0 .env.local:0 .env.production:0 .env.example:1; do
    path="${entry%:*}" expected="${entry#*:}"
    run git -C "$REPO_DIR" check-ignore -q --no-index "$path"
    [[ "$status" -eq "$expected" ]] || fail "git check-ignore $path exited $status, expected $expected"
  done
}

@test "Claude Code and Gemini CLI load AGENTS.md" {
  [[ "$(cat "$REPO_DIR/CLAUDE.md")" == "@AGENTS.md" ]] || fail "Claude Code: CLAUDE.md must hold only @AGENTS.md"
  jq -e '.context.fileName | if type == "array" then index("AGENTS.md") != null else . == "AGENTS.md" end' \
    "$REPO_DIR/.gemini/settings.json" >/dev/null || fail "Gemini CLI: .gemini/settings.json must name AGENTS.md in context.fileName"
}

@test "AGENTS.md fits the smallest rule file limit of the four agents" {
  local bytes
  bytes="$(wc -c <"$REPO_DIR/AGENTS.md")"
  ((bytes <= AGENTS_MD_MAX_BYTES)) \
    || fail "AGENTS.md has $bytes bytes (max $AGENTS_MD_MAX_BYTES; Antigravity drops the rest): move detail into docs/README.md or a skill"
}

@test "AGENTS.md defines the Code Review Rules that Codex reads" {
  run grep -x '## Code Review Rules' "$REPO_DIR/AGENTS.md"
  assert_success
}

# reviewer_hook_command: the hook command line from the branch-reviewer agent frontmatter.
reviewer_hook_command() {
  frontmatter "$REPO_DIR/.claude/agents/branch-reviewer.md" | sed -n "s/^ *command: '\(.*\)'\$/\1/p"
}

@test "the Claude reviewer agent cannot edit files and runs every Bash call through the guard hook, which blocks (exit 2) even when the guard is missing" {
  local agent="$REPO_DIR/.claude/agents/branch-reviewer.md" hook input='{"tool_input": {"command": "git diff"}}'
  run frontmatter "$agent"
  assert_line "permissionMode: plan"
  assert_line --regexp '^disallowedTools: .*Write.*Edit'
  refute_line --regexp '^tools: .*(Write|Edit)'
  assert_line "hooks:"
  assert_line "  PreToolUse:"
  assert_line '    - matcher: "Bash"'
  assert_line "      hooks:"
  assert_line "        - type: command"
  assert_line "          command: '\"\$CLAUDE_PROJECT_DIR\"/scripts/guard-reviewer-bash.sh || exit 2'"
  [[ -x "$REPO_DIR/scripts/guard-reviewer-bash.sh" ]] || fail "scripts/guard-reviewer-bash.sh must exist and be executable"
  # The guard blocks git status, so the agent's instructions must not ask for it.
  run grep -F "git status" "$agent"
  assert_failure 1
  # Only exit 2 blocks a tool call; a missing script exits 127, which would let the call through.
  hook="$(reviewer_hook_command)"
  [[ -n "$hook" ]] || fail "no hook command found in .claude/agents/branch-reviewer.md"
  mkdir -p "$BATS_TEST_TMPDIR/no-guard"
  CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/no-guard" run sh -c "$hook" <<<"$input"
  assert_failure 2
  CLAUDE_PROJECT_DIR="$REPO_DIR" run sh -c "$hook" <<<"$input"
  assert_success
}
