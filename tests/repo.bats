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
  run grep -rnE 'mapfile|readarray|declare -A|local -A|inherit_errexit|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)' "$REPO_DIR/scripts"
  assert_failure
}

@test "every Make target has a ## description" {
  local missing
  missing="$(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | grep -v '## ' | cut -d: -f1 || true)"
  [[ -z "$missing" ]] || fail "add '## <description>' to these Makefile targets: $missing"
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
