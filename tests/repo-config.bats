#!/usr/bin/env bats
load helpers

# Antigravity truncates a rule file at 24,000 bytes, the smallest limit of the four agents
# (docs/research/rsch-2026-10-15-f20fshxg-agent-repo-conventions.md, section 1).
AGENTS_MD_MAX_BYTES=24000
# Measured on the VM (the vm-rollout plan Progress log, 2026-10-13): healthy 161s after the first deploy, 192s after a reboot.
MIN_START_PERIOD_SECONDS=240
# An image line with a version tag and a sha256 digest.
PINNED_IMAGE='^ +image: [a-z0-9./_-]+:[0-9.]+(-[a-z]+)?@sha256:[0-9a-f]{64}$'
# The end of an image reference pinned by digest (Makefile *_IMAGE values, tools/Dockerfile FROM lines).
DIGEST='@sha256:[0-9a-f]{64}'
# The 18 Basic Memory tools the web gateway opens (spec web-connector 3.4): the 21 of the VM tools/list without
# delete_note, create_memory_project and delete_project.
WEB_ALLOWED_TOOLS="basic_memory_diagnostics build_context edit_note fetch list_directory list_memory_projects list_workspaces
move_note read_content read_note recent_activity schema_diff schema_infer schema_validate search search_notes view_note write_note"
# The web services: compose starts them only in their profiles, so their variables must not stop other compose calls.
WEB_SERVICES="gateway cloudflared"
# The docker run options that take their value as the next word, so that word is not the image.
DOCKER_RUN_VALUE_OPTIONS=" -e -p -u -v -w --entrypoint --env --env-file --mount --name --network --platform --publish --user --volume --workdir "
# The first --hash line under a requirement in a pip-compile --generate-hashes file.
HASH_LINE='^ +--hash=sha256:[0-9a-f]{64}'

# service_block NAME -> the lines of service NAME in compose.yaml, up to the next service or top-level key.
service_block() {
  awk -v name="$1" '$0 == "  " name ":" { inside = 1; next } inside && (/^[^ ]/ || /^  [^ ]/) { exit } inside { print }' "$REPO_DIR/compose.yaml"
}

# compose_services: the service names under services: in compose.yaml, one per line.
compose_services() {
  awk '/^[^ ]/ { inside = ($0 == "services:"); next } inside && /^  [a-z0-9-]+:$/ { sub(/^ +/, ""); sub(/:$/, ""); print }' "$REPO_DIR/compose.yaml"
}

# docker_run_image ARGS -> the image of a docker run argument list: the first word that is neither an option nor the
# value of an option in DOCKER_RUN_VALUE_OPTIONS. Globbing is off, so make text such as $(CURDIR) stays as it is.
docker_run_image() (
  set -f
  local word wants_value=false
  for word in $1; do
    if [[ "$wants_value" == true ]]; then
      wants_value=false
    elif [[ "$word" == -* ]]; then
      [[ "$DOCKER_RUN_VALUE_OPTIONS" != *" $word "* ]] || wants_value=true
    else
      printf '%s\n' "$word"
      return 0
    fi
  done
)

# makefile_image_problems -> one "  Makefile:line: ..." line for each image the Makefile names without a digest: an
# *_IMAGE value without @sha256:<digest> (a value read from compose.yaml with $(shell ...) is checked there; an image a
# recipe builds with docker build -t $(VAR) has no registry digest), a $(DOCKER_RUN) recipe whose next word is not
# a $(..._IMAGE) variable, and a bare docker run recipe whose image (docker_run_image) is not one. A Makefile with no
# *_IMAGE variable or no $(DOCKER_RUN) recipe is a problem too, so the check cannot pass on nothing.
makefile_image_problems() {
  local built images line name value
  built="$(grep -oE '^'$'\t''.*docker build .*-t \$\([A-Z_]+\)' "$REPO_DIR/Makefile" | sed -E 's/.*-t \$\(([A-Z_]+)\)$/\1/')" || true
  images="$(grep -nE '^[A-Z_]+_IMAGE[[:space:]]*[:?]?=' "$REPO_DIR/Makefile")" \
    || echo "  Makefile: found no *_IMAGE variable"
  grep -qE '^'$'\t''.*\$\(DOCKER_RUN\)' "$REPO_DIR/Makefile" || echo "  Makefile: found no \$(DOCKER_RUN) recipe"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    name="${line#*:}"
    name="${name%%[ :?=]*}"
    value="${line#*=}"
    value="${value# }"
    grep -qxF "$name" <<<"$built" && continue
    # shellcheck disable=SC2016 # $(shell is make text, matched literally
    [[ "$value" == '$(shell '*compose.yaml')' || "$value" =~ $DIGEST$ ]] \
      || echo "  Makefile:${line%%:*}: $name is '$value', expected <name>:<version>@sha256:<64 hex>"
  done <<<"$images"
  grep -nE '^'$'\t''.*\$\(DOCKER_RUN\)' "$REPO_DIR/Makefile" | while IFS= read -r line; do
    value="${line#*\$(DOCKER_RUN) }"
    value="${value%% *}"
    [[ "$value" =~ ^\$\([A-Z_]+_IMAGE\)$ ]] \
      || echo "  Makefile:${line%%:*}: \$(DOCKER_RUN) runs '$value', expected a \$(<NAME>_IMAGE) variable pinned above"
  done
  grep -nE '^'$'\t''.*docker run ' "$REPO_DIR/Makefile" | while IFS= read -r line; do
    value="$(docker_run_image "${line#*docker run }")"
    [[ "$value" =~ ^\$\([A-Z_]+_IMAGE\)$ ]] \
      || echo "  Makefile:${line%%:*}: docker run runs '$value', expected a \$(<NAME>_IMAGE) variable pinned above"
  done
}

@test "every image in compose.yaml, the Makefile and tools/Dockerfile is pinned by digest" {
  local services service images line froms bad=""
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
  bad="$(makefile_image_problems)"
  froms="$(grep -niE '^[[:space:]]*FROM[[:space:]]' "$REPO_DIR/tools/Dockerfile")" || fail "tools/Dockerfile has no FROM line"
  while IFS= read -r line; do
    [[ "${line#*:}" =~ ^FROM[[:space:]]+[^[:space:]@]+$DIGEST([[:space:]]+AS[[:space:]]+[A-Za-z0-9_-]+)?$ ]] \
      || bad="$bad"$'\n'"  tools/Dockerfile:$line"
  done <<<"$froms"
  [[ -z "$bad" ]] || fail "pin every image by digest (<name>:<version>@sha256:<digest>; read the release notes, then pass make check local-up local-verify, AGENTS.md Invariants) in the Makefile *_IMAGE variables, the \$(DOCKER_RUN) recipes and tools/Dockerfile:"$'\n'"${bad#$'\n'}"
}

@test "compose publishes ports on 127.0.0.1 only" {
  local ports
  ports="$(awk '/^ +ports:/ { p = 1; next } p && /^ +- / { print; next } p { p = 0 }' "$REPO_DIR/compose.yaml")"
  [[ -n "$ports" ]] || fail "compose.yaml has no ports entries"
  if grep -vqE '^ +- "127\.0\.0\.1:' <<<"$ports"; then
    fail "every published port must start with \"127.0.0.1: (Basic Memory has no auth): $ports"
  fi
}

@test "every compose service caps its Docker log through the bounded-logging block" {
  # Docker's json-file driver keeps every line by default (max-size -1), and Basic Memory's uvicorn logs one line
  # per MCP request, so without a cap the log under /var/lib/docker grows until the container is recreated.
  local logging services service bad=""
  logging="$(awk '$0 == "x-logging: &bounded-logging" { inside = 1; next } inside && /^[^ ]/ { exit } inside { print }' "$REPO_DIR/compose.yaml")"
  [[ -n "$logging" ]] || fail "compose.yaml must define the top-level 'x-logging: &bounded-logging' block"
  grep -qxF '  driver: json-file' <<<"$logging" || fail "compose.yaml x-logging must set driver: json-file"
  grep -qE '^    max-size: "[0-9]+m"$' <<<"$logging" || fail 'compose.yaml x-logging must set options.max-size, e.g. "10m"'
  grep -qE '^    max-file: "[0-9]+"$' <<<"$logging" || fail 'compose.yaml x-logging must set options.max-file, e.g. "3"'
  services="$(compose_services)"
  [[ -n "$services" ]] || fail "compose.yaml defines no services"
  for service in $services; do
    service_block "$service" | grep -qxF '    logging: *bounded-logging' || bad="$bad $service"
  done
  [[ -z "$bad" ]] || fail "set 'logging: *bounded-logging' in compose.yaml for:$bad (or its Docker log grows without a limit)"
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

# sandbox.excludedCommands must hold exactly these entries (the exact strings and the `*` ones): a target that takes arguments needs
# `make <t> *`, and any other entry (make *, docker *, bash, make) would take the sandbox off for everything it matches.
SANDBOX_EXACT_EXCLUDES='make check|make test|make lint|make coverage|make fmt|make check-git|make secret-scan|make tools-image|make gateway-lock'
SANDBOX_STAR_EXCLUDES='make local-up *|make local-down *|make local-logs *|make local-verify *|make review *|make review-post *|make review-record *|make probe *|make status *|make logs *|make export-logs *|make verify *|make backup *|make access-check *|make tunnel *|make deploy *|make restore *|make vm-bootstrap *|make sb-fonts *|gh *|gcloud *|git push *'
# The ask rules the settings must keep: outward actions and VM or cloud changes.
SANDBOX_ASK_RULES='Bash(git push --force*)|Bash(git push * --force*)|Bash(git push -f*)|Bash(git push * -f*)|Bash(git push *)|Bash(gh pr create *)|Bash(gh pr edit *)|Bash(gh pr comment *)|Bash(gh pr ready *)|Bash(make review-post *)|Bash(make review-record *)|Bash(make deploy *)|Bash(make restore *)|Bash(make vm-bootstrap *)|Bash(make sb-fonts *)|Bash(gcloud compute instances create *)|Bash(gcloud compute instances delete *)|Bash(gcloud compute firewall-rules create *)|Bash(gcloud compute firewall-rules delete *)'

# settings_problems FILE: print one line per way the Claude Code settings in FILE break the sandbox rules; print nothing when they hold.
settings_problems() {
  jq -r --arg exact "$SANDBOX_EXACT_EXCLUDES" --arg star "$SANDBOX_STAR_EXCLUDES" --arg ask "$SANDBOX_ASK_RULES" '
    def need(cond; msg): if cond then empty else msg end;
    ($star | split("|")) as $stars
    | ($exact | split("|")) as $exact
    | ($ask | split("|")) as $asks
    | (.sandbox.filesystem.denyRead // []) as $deny_read
    | (.sandbox.excludedCommands // []) as $excluded
    | (.permissions.deny // []) as $deny
    | (.permissions.ask // []) as $asked
    | need(.sandbox.enabled == true; "sandbox.enabled must be true"),
      need(.sandbox.allowUnsandboxedCommands == false; "sandbox.allowUnsandboxedCommands must be false"),
      need((.permissions | has("blockReadsOutsideWorkingDirectories") | not); "permissions.blockReadsOutsideWorkingDirectories must be absent (the spike fell back to 1-B)"),
      ("../../../.env", "~/.ssh", "~/.config/gcloud", "~/.config/gh" | . as $p | need($deny_read | index($p); "sandbox.filesystem.denyRead lacks " + $p)),
      need(((.sandbox.network.allowedDomains // []) | length) > 0; "sandbox.network.allowedDomains must not be empty"),
      need($deny | index("Read(~/**/.env)"); "permissions.deny lacks Read(~/**/.env)"),
      ($exact + $stars | .[] | . as $r | need($excluded | index($r); "sandbox.excludedCommands lacks " + $r)),
      ($excluded[] | select(. as $e | ($exact + $stars) | index($e) | not) | "sandbox.excludedCommands has an entry outside the fixed list: " + .),
      ($deny[] | select((test("^Read\\((\\./\\.env|\\./backups/\\*\\*|\\./\\.local-data/\\*\\*|~/\\.ssh/\\*\\*|~/\\.config/gcloud/\\*\\*|~/\\.config/gh/\\*\\*|~/\\*\\*/\\.env)\\)$") or test("^Bash\\(rm .*(backups|basic-memory\\.prev)")) | not) | "permissions.deny holds a rule that is neither a secret read nor a backup deletion: " + .),
      need($deny | any(test("^Bash\\(rm .*backups")); "permissions.deny lacks a backups deletion rule"),
      need($deny | any(test("^Bash\\(rm .*basic-memory\\.prev")); "permissions.deny lacks a basic-memory.prev deletion rule"),
      ($asks[] | . as $r | need($asked | index($r); "permissions.ask lacks " + $r))
  ' "$1" || return 1
}

@test "the Claude Code settings keep the sandbox on, deny only secret reads and backup deletion, and ask before outward or VM commands" {
  local settings="$REPO_DIR/.claude/settings.json" bad="$BATS_TEST_TMPDIR/bad.json"
  # The check itself: a copy without one required key and a copy with `make *` added must both be reported.
  jq 'del(.sandbox.enabled)' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "sandbox.enabled must be true"
  jq '.sandbox.excludedCommands += ["make *"]' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "outside the fixed list: make *"
  jq '.sandbox.excludedCommands += ["bash"]' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "outside the fixed list: bash"
  jq 'del(.sandbox.excludedCommands[0])' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "sandbox.excludedCommands lacks make check"
  jq 'del(.sandbox.excludedCommands[20])' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "sandbox.excludedCommands lacks "
  jq '.permissions.blockReadsOutsideWorkingDirectories = true' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "blockReadsOutsideWorkingDirectories must be absent"
  jq 'del(.permissions.ask[0])' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "permissions.ask lacks "
  jq 'del(.sandbox.filesystem.denyRead[0])' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "sandbox.filesystem.denyRead lacks "
  jq '.permissions.deny += ["Bash(rm *)"]' "$settings" >"$bad"
  run settings_problems "$bad"
  assert_output --partial "neither a secret read nor a backup deletion"
  # The committed file holds every rule.
  run settings_problems "$settings"
  assert_output ""
  # A committed file must stay portable: no home directory path.
  refute_matches "$settings" '/Users/|/home/'
}

@test "cloudflared runs a pinned cloudflared image as a remotely managed tunnel in the tunnel profile, publishes no port and joins only the web network" {
  local cf command
  cf="$(service_block cloudflared)"
  [[ -n "$cf" ]] || fail "compose.yaml must define the cloudflared service"
  grep -qE '^ +image: cloudflare/cloudflared:' <<<"$cf" || fail "cloudflared must run the cloudflare/cloudflared image"
  command="$(grep -E '^ +command: \[' <<<"$cf")" || fail "cloudflared has no command list"
  [[ "$command" == *'"tunnel"'* && "$command" == *'"run"'* ]] \
    || fail "cloudflared must run 'tunnel run', a tunnel managed in the Cloudflare dashboard"
  # A quick tunnel (--url) publishes an unauthenticated trycloudflare.com address.
  if grep -qF -- '--url' <<<"$cf"; then
    fail "cloudflared must not use --url (a quick tunnel)"
  fi
  # shellcheck disable=SC2016 # the compose text ${BM_WEB_TUNNEL_TOKEN:-} is matched literally
  grep -qxF '      TUNNEL_TOKEN: ${BM_WEB_TUNNEL_TOKEN:-}' <<<"$cf" \
    || fail 'cloudflared must read its token from the environment: TUNNEL_TOKEN: ${BM_WEB_TUNNEL_TOKEN:-}'
  if grep -qE '^ +ports:' <<<"$cf"; then
    fail "cloudflared must publish no port: it only dials out"
  fi
  grep -qxF '    networks: [web]' <<<"$cf" || fail "cloudflared must use only the web network"
  grep -qxF '    profiles: [tunnel]' <<<"$cf" || fail "cloudflared must be in the tunnel profile"
  grep -qE '^ +restart: unless-stopped$' <<<"$cf" || fail "cloudflared must set restart: unless-stopped"
  grep -qE '^ +test: \[' <<<"$cf" || fail "cloudflared has no healthcheck test"
}

@test "gateway runs the pinned python slim image in the web profile, joins basic-memory and web and mounts its code read-only" {
  local gw healthcheck
  gw="$(service_block gateway)"
  [[ -n "$gw" ]] || fail "compose.yaml must define the gateway service"
  grep -qE '^ +image: python:[0-9.]+-slim@' <<<"$gw" || fail "gateway must run the python -slim image"
  grep -qxF '    profiles: [web]' <<<"$gw" || fail "gateway must be in the web profile"
  grep -qxF '    networks: [basic-memory, web]' <<<"$gw" || fail "gateway must use exactly the basic-memory and web networks"
  grep -qxF '      - "./gateway:/app:ro"' <<<"$gw" || fail "gateway must mount ./gateway read-only at /app"
  grep -qE '^ +restart: unless-stopped$' <<<"$gw" || fail "gateway must set restart: unless-stopped"
  healthcheck="$(grep -E '^ +test: \[' <<<"$gw")" || fail "gateway has no healthcheck test"
  [[ "$healthcheck" == *oauth-authorization-server* ]] \
    || fail "the gateway healthcheck must read the OAuth authorization server metadata"
}

@test "web services never use a required-variable default" {
  local service block bad=""
  # shellcheck disable=SC2086 # WEB_SERVICES is a list of words
  for service in $WEB_SERVICES; do
    block="$(service_block "$service")"
    [[ -n "$block" ]] || fail "compose.yaml must define the $service service"
    # compose expands the variables of services in disabled profiles too, so ${VAR:?} would stop every compose call.
    if grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' <<<"$block"; then
      bad="$bad $service"
    fi
  done
  [[ -z "$bad" ]] || fail "use \${VAR:-} instead of \${VAR:?...} in:$bad (BM_WEB=off installs would stop at every compose call)"
}

@test "nothing starts a quick tunnel" {
  local file
  for file in compose.yaml Makefile; do
    if grep -qi 'trycloudflare' "$REPO_DIR/$file"; then
      fail "$file names trycloudflare: a quick tunnel publishes an unauthenticated address"
    fi
  done
  refute_matches "$REPO_DIR/scripts" 'trycloudflare' -i
}

@test "gateway requirements pin every package with a hash" {
  local req="$REPO_DIR/gateway/requirements.txt" line previous="" count=0 bad=""
  [[ -f "$req" ]] || fail "gateway/requirements.txt is missing: run make gateway-lock"
  # A requirement line starts with neither a space nor #; the line right after it must be its first --hash line.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$previous" ]]; then
      [[ "$line" =~ $HASH_LINE ]] || bad="$bad"$'\n'"  $previous"
      previous=""
    fi
    case "$line" in
      "" | " "* | "#"*) ;;
      *)
        count=$((count + 1))
        [[ "$line" == *==* ]] || bad="$bad"$'\n'"  $line"
        previous="$line"
        ;;
    esac
  done <"$req"
  [[ -z "$previous" ]] || bad="$bad"$'\n'"  $previous"
  ((count > 0)) || fail "gateway/requirements.txt has no requirement lines: run make gateway-lock"
  [[ -z "$bad" ]] || fail "pin each requirement with == and a --hash=sha256 line (make gateway-lock):$bad"
}

@test "gateway.py strips client headers, opens only the allowed tools, checks the owner by numeric id and culls its store" {
  local py="$REPO_DIR/gateway/gateway.py" text names expected
  [[ -f "$py" ]] || fail "gateway/gateway.py is missing"
  for text in 'forward_incoming_headers=False' 'only=True' '"sub"' 'cull('; do
    grep -qF -- "$text" "$py" || fail "gateway/gateway.py must contain $text"
  done
  names="$(awk '/^ALLOWED_TOOLS = frozenset\(/ { inside = 1 } inside { print } inside && /\)/ { exit }' "$py" \
    | grep -oE '"[a-z_]+"' | tr -d '"' | sort)"
  expected="$(tr ' ' '\n' <<<"$WEB_ALLOWED_TOOLS" | sort)"
  [[ "$names" == "$expected" ]] \
    || fail "ALLOWED_TOOLS in gateway/gateway.py must be exactly the 18 tools of the spec:"$'\n'"$(diff <(echo "$expected") <(echo "$names"))"
}
