#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
load helpers

setup() {
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CLAUDE_CONFIG_DIR CODEX_HOME
  mkdir -p "$HOME/.claude" "$HOME/.codex"
  jq -n '{model: "x", hooks: {UserPromptSubmit: [{hooks: [{type: "command", command: "bash memsearch.sh", timeout: 10}]}]}}' \
    >"$HOME/.claude/settings.json"
  MAIN="$(main_checkout_root "$REPO_DIR")"
  SYNC_CMD="make -s --no-print-directory -C '$MAIN' memory-sync HOOK=1"
  INDEX_CMD="make -s --no-print-directory -C '$MAIN' memory-index MEMORY_AGENT"
  INSTALL="$REPO_DIR/scripts/install-memory-hooks.sh"
}

# commands FILE EVENT -> the hook commands of EVENT in FILE, one per line.
commands() { jq -r --arg e "$2" '.hooks[$e][]?.hooks[]?.command' "$1"; }

@test "adds the sync and index hooks once to both files with each agent's name, adds nothing to UserPromptSubmit, keeps the other hooks and settings, backs up a changed file once and creates a missing Codex hooks.json with only a hooks key" {
  local file agent
  run "$INSTALL"
  assert_success
  run "$INSTALL"
  assert_success
  for file in "$HOME/.claude/settings.json:claude-code" "$HOME/.codex/hooks.json:codex"; do
    agent="${file##*:}" file="${file%:*}"
    (
      assert_equal "$(commands "$file" SessionStart)" "$(printf '%s\n%s=%s' "$SYNC_CMD" "$INDEX_CMD" "$agent")" \
        && assert_equal "$(commands "$file" Stop)" "$SYNC_CMD"
    ) || fail "hooks in $file"
  done
  assert_equal "$(commands "$HOME/.claude/settings.json" UserPromptSubmit)" "bash memsearch.sh"
  assert_equal "$(jq -c 'keys' "$HOME/.codex/hooks.json")" '["hooks"]'
  assert_equal "$(jq -r .model "$HOME/.claude/settings.json")" x
  assert_equal "$(find "$HOME/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" 1
  assert_equal "$(find "$HOME/.codex" -name '*.bak-*' | wc -l | tr -d ' ')" 0
}

@test "--remove takes out only its own hooks and writes through a symlinked settings file" {
  mv "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/dotfiles-settings.json"
  ln -s "$BATS_TEST_TMPDIR/dotfiles-settings.json" "$HOME/.claude/settings.json"
  run "$INSTALL"
  assert_success
  run "$INSTALL" --remove
  assert_success
  [[ -L "$HOME/.claude/settings.json" ]] || fail "the symlink was replaced by a file"
  assert_equal "$(commands "$HOME/.claude/settings.json" UserPromptSubmit)" "bash memsearch.sh"
  assert_equal "$(commands "$HOME/.claude/settings.json" SessionStart)" ""
  assert_equal "$(commands "$HOME/.codex/hooks.json" Stop)" ""
}

@test "stops without writing or backing up either file when a settings file is not valid JSON" {
  echo '{' >"$HOME/.claude/settings.json"
  run "$INSTALL"
  assert_failure
  assert_equal "$(cat "$HOME/.claude/settings.json")" "{"
  assert_equal "$(find "$HOME/.claude" -name '*.bak-*' | wc -l | tr -d ' ')" 0
  [[ ! -e "$HOME/.codex/hooks.json" ]] || fail "wrote the Codex file although the Claude file is broken"
}
