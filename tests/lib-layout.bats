#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/layout.sh
  . "$REPO_DIR/scripts/lib/layout.sh"
  SKILL="$BATS_TEST_TMPDIR/SKILL.md"
}

@test "script_verbs reads the first column of the table under ## Verbs and stops when the table is missing" {
  local case
  # shellcheck disable=SC2016 # the backticks are literal Markdown in the verb table
  printf '# Skill\n\n## Verbs\n\n| Verb | Meaning | Example |\n|---|---|---|\n| `show` | Prints state | `show-status` |\n| check | Reports only | `check-git` |\n\n## Libraries\n\n| File | Topic |\n|---|---|\n| common | core |\n' >"$SKILL"
  run script_verbs "$SKILL"
  assert_success
  assert_output $'show\ncheck'
  # Each case: a skill file without the verb table (no heading, or the heading with no table under it).
  for case in '# Skill\n\n## Libraries\n\n| Verb | Meaning |\n|---|---|\n| show | Prints |\n' '# Skill\n\n## Verbs\n\nNo table yet.\n\n## Libraries\n'; do
    # shellcheck disable=SC2059 # each case is the printf format that writes the file
    printf "$case" >"$SKILL"
    (
      run script_verbs "$SKILL"
      assert_failure || exit 1
    ) || fail "script_verbs did not stop on: $case"
  done
}

@test "pair_test maps scripts, remote scripts and libraries to their test and refuses other paths" {
  local case path expected
  # Each case: the path | its pair test, or nothing when pair_test must refuse the path.
  for case in "scripts/show-status.sh|tests/show-status.bats" \
    "scripts/remote/provision-vm.sh|tests/remote-provision-vm.bats" \
    "scripts/lib/vm.sh|tests/lib-vm.bats" \
    "scripts/other/show-status.sh|" "scripts/remote/sub/check-probe.sh|" "scripts/show-status|" \
    "tests/show-status.bats|" "docs/show-status.sh|"; do
    IFS='|' read -r path expected <<<"$case"
    (
      run pair_test "$path"
      if [[ -n "$expected" ]]; then
        assert_success && assert_output "$expected" || exit 1
      else
        assert_failure || exit 1
      fi
    ) || fail "pair_test $path: expected ${expected:-a refusal}"
  done
}
