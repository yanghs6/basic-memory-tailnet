#!/usr/bin/env bats
load helpers

# Each test works in a fresh git repo that holds a copy of the script-authoring skill: its verb table and templates.
setup() {
  init_git_repo
  mkdir -p .agents/skills
  cp -R "$REPO_DIR/.agents/skills/script-authoring" .agents/skills/script-authoring
  git add -A
  git commit -q -m "chore: add the script-authoring skill"
  CREATE="$REPO_DIR/scripts/create-script.sh"
}

@test "creates a script, a remote script and a library with their pair test from the templates" {
  local case kind name script test file
  # Each case: the kind | the name | the script and the pair test it must create.
  for case in "script|show-probe|scripts/show-probe.sh|tests/show-probe.bats" \
    "remote|check-probe|scripts/remote/check-probe.sh|tests/remote-check-probe.bats" \
    "lib|probe-kit|scripts/lib/probe-kit.sh|tests/lib-probe-kit.bats"; do
    IFS='|' read -r kind name script test <<<"$case"
    run "$CREATE" "$name" "$kind"
    assert_success
    assert_line "$script"
    assert_line "$test"
    if [[ "$kind" == lib ]]; then
      [[ ! -x "$script" ]] || fail "$script is a library, so it must not be executable"
    else
      [[ -x "$script" ]] || fail "$script must be executable"
    fi
    grep -qF "$script" "$test" || fail "$test does not run or source $script"
    for file in "$script" "$test"; do
      refute_matches "$file" '\{\{name\}\}|_BM_LIB_NAME'
      # bash cannot parse @test lines; bats turns each into a function first, so do the same.
      sed -E 's/^@test .*\{$/test_case() {/' "$file" | bash -n || fail "$file does not parse"
    done
  done
  grep -qx 'readonly _BM_LIB_PROBE_KIT=1' scripts/lib/probe-kit.sh || fail "the library guard is not _BM_LIB_PROBE_KIT"
}

@test "refuses a name whose first word is not a verb of the table or that has no object, and writes nothing" {
  local case kind name message
  # Each case: the kind | the name | the part of the message that names the check that stopped it.
  for case in "script|frob-probe|not a verb" "remote|frob-probe|not a verb" \
    "script|show|<verb>-<object>" "remote|check|<verb>-<object>"; do
    IFS='|' read -r kind name message <<<"$case"
    (
      run "$CREATE" "$name" "$kind"
      assert_failure && assert_output --partial "$message" || exit 1
    ) || fail "create-script.sh did not refuse $kind $name with: $message"
  done
  run git status --porcelain --untracked-files=all
  assert_output ""
}

@test "refuses when the script or its test already exists and leaves both untouched" {
  local case kind name
  mkdir -p scripts tests
  printf 'edited\n' >scripts/show-probe.sh
  printf 'edited\n' >tests/remote-check-probe.bats
  printf 'edited\n' >tests/lib-probe-kit.bats
  git add -A
  git commit -q -m "test: one file of each pair already exists"
  # Each case: the kind and the name; the script exists for the first, the pair test for the other two.
  for case in "script show-probe" "remote check-probe" "lib probe-kit"; do
    read -r kind name <<<"$case"
    (
      run "$CREATE" "$name" "$kind"
      assert_failure && assert_output --partial "already exists" || exit 1
    ) || fail "create-script.sh did not refuse $kind $name"
  done
  run git status --porcelain --untracked-files=all
  assert_output ""
}
