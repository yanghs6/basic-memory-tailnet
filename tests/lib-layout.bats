#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/layout.sh
  . "$REPO_DIR/scripts/lib/layout.sh"
  SKILL="$BATS_TEST_TMPDIR/SKILL.md"
}

@test "script_verbs reads the first column of the table under ## Verbs and stops when the table is missing, its second line is not the separator row or a first cell is empty" {
  local case message text
  # shellcheck disable=SC2016 # the backticks are literal Markdown in the verb table
  printf '# Skill\n\n## Verbs\n\n| Verb | Meaning | Example |\n|---|---|---|\n| `show` | Prints state | `show-status` |\n| check | Reports only | `check-git` |\n\n## Libraries\n\n| File | Topic |\n|---|---|\n| common | core |\n' >"$SKILL"
  run script_verbs "$SKILL"
  assert_success
  assert_output $'show\ncheck'
  # Each case: the part of the message that names the check that stopped it, a colon, then the printf format of a skill
  # file whose verb table is missing (no heading, no table under it), lacks its separator or header row, or has an
  # empty first cell.
  for case in 'no heading:# Skill\n\n## Libraries\n\n| Verb | Meaning |\n|---|---|\n| show | Prints |\n' \
    'no verb rows:# Skill\n\n## Verbs\n\nNo table yet.\n\n## Libraries\n' \
    'separator row:# Skill\n\n## Verbs\n\n| Verb | Meaning |\n| show | Prints |\n| check | Reports |\n' \
    'separator row:# Skill\n\n## Verbs\n\n|---|---|\n| show | Prints |\n| check | Reports |\n' \
    'empty first cell:# Skill\n\n## Verbs\n\n| Verb | Meaning |\n|---|---|\n| show | Prints |\n|  | Reports |\n'; do
    message="${case%%:*}"
    text="${case#*:}"
    (
      # shellcheck disable=SC2059 # each case is the printf format that writes the file
      printf "$text" >"$SKILL" || exit 1
      run script_verbs "$SKILL"
      assert_failure && assert_output --partial "$message" || exit 1
    ) || fail "script_verbs did not stop with '$message' on: $text"
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

@test "script_dir names the folder of each kind of script and refuses any other kind" {
  local case kind expected
  # Each case: the kind | its folder, or nothing when script_dir must refuse the kind.
  for case in "script|scripts" "remote|scripts/remote" "lib|scripts/lib" "frob|" "|"; do
    IFS='|' read -r kind expected <<<"$case"
    (
      run script_dir "$kind"
      if [[ -n "$expected" ]]; then
        assert_success && assert_output "$expected" || exit 1
      else
        assert_failure || exit 1
      fi
    ) || fail "script_dir '$kind': expected ${expected:-a refusal}"
  done
}
