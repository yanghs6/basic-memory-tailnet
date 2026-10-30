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
  # The memsearch plugin's Stop hook runs a claude -p child with MEMSEARCH_NO_WATCH=1, which runs our hooks too.
  # shellcheck disable=SC2016  # the text is written into the hook file, so ${...} must stay unexpanded
  GUARD='[ "${MEMSEARCH_NO_WATCH:-}" = 1 ] || '
  SYNC_CMD="${GUARD}make -s --no-print-directory -C '$MAIN' memory-sync HOOK=1 || exit 1"
  INDEX_CMD="${GUARD}make -s --no-print-directory -C '$MAIN' memory-index MEMORY_AGENT"
  INSTALL="$REPO_DIR/scripts/install-memory-hooks.sh"
}

# commands FILE EVENT -> the hook commands of EVENT in FILE, one per line.
commands() { jq -r --arg e "$2" '.hooks[$e][]?.hooks[]?.command' "$1"; }

@test "adds the sync and index hooks once to both files with each agent's name, adds nothing to UserPromptSubmit, keeps the other hooks and settings, backs up a changed file once and creates a missing Codex hooks.json with only a hooks key" {
  local file agent
  run "$INSTALL"
  assert_success
  assert_output --partial "settings.json: added SessionStart Stop"
  assert_output --partial "hooks.json: added SessionStart Stop"
  run "$INSTALL"
  assert_success
  assert_output --partial "settings.json: already up to date"
  for file in "$HOME/.claude/settings.json:claude-code" "$HOME/.codex/hooks.json:codex"; do
    agent="${file##*:}" file="${file%:*}"
    (
      assert_equal "$(commands "$file" SessionStart)" "$(printf '%s\n%s=%s || exit 1' "$SYNC_CMD" "$INDEX_CMD" "$agent")" \
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
  assert_output --partial "settings.json: removed SessionStart Stop"
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

@test "leaves the file byte-identical when the user added a hook after ours, and replaces a stale own entry of another checkout path in the older form without || exit 1" {
  local before
  run "$INSTALL"
  assert_success
  jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "other.sh", timeout: 5}]}]' \
    "$HOME/.claude/settings.json" >"$BATS_TEST_TMPDIR/edited.json"
  cp "$BATS_TEST_TMPDIR/edited.json" "$HOME/.claude/settings.json"
  before="$(cat "$HOME/.claude/settings.json")"
  rm -f "$HOME/.claude"/settings.json.bak-*
  run "$INSTALL"
  assert_success
  assert_equal "$(cat "$HOME/.claude/settings.json")" "$before"
  assert_equal "$(find "$HOME/.claude" -name '*.bak-*' | wc -l | tr -d ' ')" 0
  assert_equal "$(commands "$HOME/.claude/settings.json" SessionStart | tail -n 1)" other.sh
  local form
  for form in 'sub("-C .+ memory"; "-C /old/place memory") | sub("^[^|]*[|][|] "; "") | sub(" [|][|] exit 1$"; "")' 'sub("^[^|]*[|][|] "; "")'; do
    (
      jq ".hooks.Stop[0].hooks[0].command |= ($form)" "$HOME/.claude/settings.json" >"$BATS_TEST_TMPDIR/stale.json" \
        && [[ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$BATS_TEST_TMPDIR/stale.json")" != "$SYNC_CMD" ]] \
        && cp "$BATS_TEST_TMPDIR/stale.json" "$HOME/.claude/settings.json" \
        && "$INSTALL" >/dev/null 2>&1 \
        && assert_equal "$(commands "$HOME/.claude/settings.json" Stop)" "$SYNC_CMD" || exit 1
    ) || fail "older form not replaced: $form"
  done
}

@test "an installed hook command does nothing when MEMSEARCH_NO_WATCH is 1 and runs make otherwise" {
  local cmd
  setup_stubs make
  run "$INSTALL"
  assert_success
  for cmd in "$(commands "$HOME/.claude/settings.json" Stop)" "$(commands "$HOME/.codex/hooks.json" SessionStart | tail -n 1)"; do
    printf '#!/usr/bin/env bash\n%s\n' "$cmd" >"$BATS_TEST_TMPDIR/hook.sh"
    chmod +x "$BATS_TEST_TMPDIR/hook.sh"
    : >"$STUB_LOG"
    (
      MEMSEARCH_NO_WATCH=1 "$BATS_TEST_TMPDIR/hook.sh" && refute_stub_called '^make ' || exit 1
    ) || fail "make ran in the memsearch child: $cmd"
    (
      env -u MEMSEARCH_NO_WATCH "$BATS_TEST_TMPDIR/hook.sh" && assert_stub_called '^make ' || exit 1
    ) || fail "make did not run without the guard variable: $cmd"
  done
}
