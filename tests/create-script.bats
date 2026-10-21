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
  local case kind name script test guard file
  # Each case: the kind | the name | the script and the pair test it must create | a library's source guard.
  # An empty kind is what make new-script passes when KIND is omitted: it means script.
  for case in "script|show-probe|scripts/show-probe.sh|tests/show-probe.bats|" \
    "|show-default|scripts/show-default.sh|tests/show-default.bats|" \
    "remote|check-probe|scripts/remote/check-probe.sh|tests/remote-check-probe.bats|" \
    "lib|probe|scripts/lib/probe.sh|tests/lib-probe.bats|_BM_LIB_PROBE" \
    "lib|probe-kit|scripts/lib/probe-kit.sh|tests/lib-probe-kit.bats|_BM_LIB_PROBE_KIT"; do
    IFS='|' read -r kind name script test guard <<<"$case"
    (
      run "$CREATE" "$name" "$kind" && assert_success && assert_line "$script" && assert_line "$test" || exit 1
      if [[ -n "$guard" ]]; then
        [[ ! -x "$script" ]] || fail "a library must not be executable" || exit 1
        grep -qx "readonly $guard=1" "$script" || fail "the library guard is not $guard" || exit 1
      else
        [[ -x "$script" ]] || fail "a script must be executable" || exit 1
      fi
      grep -qF "$script" "$test" || fail "the test does not run or source the script" || exit 1
      for file in "$script" "$test"; do
        refute_matches "$file" '\{\{name\}\}|_BM_LIB_NAME' || exit 1
        # bash cannot parse @test lines; bats turns each into a function first, so do the same.
        sed -E 's/^@test .*\{$/test_case() {/' "$file" | bash -n || fail "$file does not parse" || exit 1
      done
    ) || fail "create-script.sh did not create $kind $name as $script and $test"
  done
}

@test "refuses an unknown kind, a name whose first word is not a verb of the table or that has no object, and writes nothing" {
  local case kind name message
  # Each case: the kind | the name | the part of the message that names the check that stopped it.
  for case in "frob|show-probe|KIND must be" "script|frob-probe|not a verb" "remote|frob-probe|not a verb" \
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

@test "leaves neither the script nor its test when writing the test fails" {
  local real_sed
  real_sed="$(command -v sed)"
  setup_stubs
  # This sed fails only on the test template, after the script has been written.
  fake_cmd sed "case \"\$*\" in *.bats) exit 1 ;; esac
exec \"$real_sed\" \"\$@\""
  run "$CREATE" show-probe
  assert_failure
  [[ ! -e scripts/show-probe.sh && ! -e tests/show-probe.bats ]] || fail "a file of the half-written pair was left"
  assert_output --partial "could not write tests/show-probe.bats"
  run git status --porcelain --untracked-files=all
  assert_output ""
}
