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

@test "scripts avoid bash 4+ features (macOS ships bash 3.2)" {
  run grep -rnE 'mapfile|readarray|declare -[Ann]|local -[Ann]|inherit_errexit|coproc|wait -n|\|&|&>>|\$\{[A-Za-z_][A-Za-z0-9_]*(\^|,)|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]' "$REPO_DIR/scripts"
  assert_failure 1
}

@test "no script enables Tailscale Funnel" {
  run grep -rniE 'tailscale[[:space:]]+funnel' "$REPO_DIR/scripts"
  assert_failure 1
}
