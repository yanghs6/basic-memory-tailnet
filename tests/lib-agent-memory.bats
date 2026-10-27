#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  # shellcheck source=../scripts/lib/agent-memory.sh
  . "$REPO_DIR/scripts/lib/agent-memory.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "https, ssh and scp remotes of one repo give one remote and one project key, from the repo root and from a subfolder" {
  local url repo="$BATS_TEST_TMPDIR/widget"
  git init -q "$repo" && mkdir -p "$repo/sub" && git -C "$repo" remote add origin https://example.invalid/x/y
  for url in https://GitHub.com/acme/widget.git git@github.com:acme/widget.git ssh://git@github.com:22/acme/widget https://user@github.com/acme/widget/; do
    (
      git -C "$repo" remote set-url origin "$url" || exit 1
      assert_equal "$(normalize_remote "$url")" github.com/acme/widget \
        && assert_equal "$(repo_for_dir "$repo/sub")" github.com/acme/widget \
        && assert_equal "$(project_key_for_dir "$repo")" acme-widget \
        && assert_equal "$(project_key_for_dir "$repo/sub")" acme-widget
    ) || fail "remote $url"
  done
  git -C "$repo" remote set-url origin git@bitbucket.org:acme_dev/data-pipeline.git
  assert_equal "$(project_key_for_dir "$repo")" acme_dev-data-pipeline
}

@test "the home folder is _global and a folder outside git is local-<name> with other characters turned into -" {
  mkdir -p "$BATS_TEST_TMPDIR/My Notes.v2"
  assert_equal "$(project_key_for_dir "$HOME")" _global
  assert_equal "$(project_key_for_dir "$BATS_TEST_TMPDIR/My Notes.v2")" local-my-notes-v2
  assert_equal "$(repo_for_dir "$BATS_TEST_TMPDIR/My Notes.v2")" ""
}

@test "a Claude folder takes the key of the cwd whose encoding is its name among several, and local-<folder name> when none matches or no session file exists" {
  local cwd="$BATS_TEST_TMPDIR/027_agent.poc" folder
  mkdir -p "$cwd"
  folder="$BATS_TEST_TMPDIR/projects/$(claude_folder_name "$cwd")"
  mkdir -p "$folder/memory"
  assert_equal "$(claude_folder_name /a/b_c.d)" -a-b-c-d
  printf '{"cwd":"%s"}\n{"cwd":"%s"}\n' "$cwd/.claude/worktrees/a" "$cwd" >"$folder/s1.jsonl"
  assert_equal "$(claude_folder_cwd "$folder")" "$cwd"
  assert_equal "$(claude_folder_key "$folder")" local-027_agent-poc
  printf '{"cwd":"/elsewhere"}\n' >"$folder/s1.jsonl"
  run claude_folder_cwd "$folder"
  assert_failure
  rm "$folder/s1.jsonl"
  assert_equal "$(claude_folder_key "$folder")" "local-$(sanitize_key "${folder##*/}")"
}

@test "require_memory_device takes a lowercase key and refuses an empty, uppercase or spaced one; is_excluded matches whole keys only" {
  local device
  BM_MEMORY_DEVICE=mac-work require_memory_device
  for device in "" Mac-Work "mac work"; do
    (
      export BM_MEMORY_DEVICE="$device"
      run require_memory_device
      assert_failure
    ) || fail "accepted device '$device'"
  done
  export BM_MEMORY_EXCLUDE=acme-widget,_global
  is_excluded acme-widget || fail "acme-widget is listed"
  ! is_excluded acme || fail "acme is not listed"
}
