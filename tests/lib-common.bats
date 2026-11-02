#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
}

@test "mask hides short values completely and keeps only a 4-character prefix of long ones" {
  run mask "short"
  assert_output "****"
  run mask "tskey-auth-abcdef123456"
  assert_output "tske****"
}

@test "new_temp makes a file, or with -d a directory, NAME.XXXXXX under TMPDIR without a double slash, and under /tmp when TMPDIR is unset or empty" {
  local base="$BATS_TEST_TMPDIR/tmp" case tmpdir flag dir path
  mkdir -p "$base"
  # Each case: TMPDIR (unset: not set) | the new_temp flag (none or -d) | the directory the new path must be in.
  for case in "$base|none|$base" "$base/|none|$base" "$base/|-d|$base" "unset|none|/tmp" "unset|-d|/tmp" "|none|/tmp"; do
    IFS='|' read -r tmpdir flag dir <<<"$case"
    (
      if [[ "$tmpdir" == unset ]]; then
        unset TMPDIR
      else
        TMPDIR="$tmpdir"
      fi
      if [[ "$flag" == -d ]]; then
        path="$(new_temp -d probe)" && [[ -d "$path" ]] || exit 1
      else
        path="$(new_temp probe)" && [[ -f "$path" ]] || exit 1
      fi
      rm -rf "$path" && [[ "$path" == "$dir"/probe.?????? ]] || exit 1
    ) || fail "new_temp with TMPDIR '$tmpdir' and flag $flag made no new path $dir/probe.XXXXXX"
  done
}
