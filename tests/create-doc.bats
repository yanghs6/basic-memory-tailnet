#!/usr/bin/env bats
load helpers

# Each test works in a fresh git repo that holds a copy of the real registry and templates.
setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  mkdir -p "$WORK/docs" "$WORK/.agents/skills/doc-authoring"
  cp "$REPO_DIR/docs/README.md" "$WORK/docs/README.md"
  cp -R "$REPO_DIR/.agents/skills/doc-authoring/assets" "$WORK/.agents/skills/doc-authoring/assets"
  cd "$WORK" || return
  git config user.email agent@example.com
  git config user.name agent
  git add -A
  git commit -q -m "chore: init"
  CREATE="$REPO_DIR/scripts/create-doc.sh"
  TODAY="$(date +%F)"
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/docs.sh
  . "$REPO_DIR/scripts/lib/docs.sh"
}

@test "make new-doc with ID= names the file and fills the id blank with that id, for every type that takes new documents" {
  local type code location statuses keys new path doc_status key checked=0 id
  while IFS=$'\t' read -r type code location statuses keys new _; do
    [[ "$new" == "허용" ]] || continue
    checked=$((checked + 1))
    id="k7m2x9q$checked"
    path="$("$CREATE" "$type" "check-$code" "$id" 2>/dev/null)" || fail "create-doc.sh failed for $type"
    assert_equal "$path" "${location%/}/$code-$TODAY-$id-check-$code.md"
    assert_equal "$(front_value "$path" id)" "$id"
    # Not "status": bats run sets that name.
    doc_status="$(front_value "$path" status)"
    [[ ", $statuses," == *", $doc_status,"* ]] || fail "$type: status '$doc_status' is not one of: $statuses"
    for key in $(tr ',' ' ' <<<"$keys"); do
      frontmatter "$path" | grep -q "^$key: " || fail "$type: the front matter has no $key"
    done
    # Only the blanks the script fills are checked; blanks like {{제목}} are for the author.
    run grep -nE '\{\{(date|id|slug|number)\}\}' "$path"
    assert_failure 1
  done <<<"$(doc_types "$WORK/docs/README.md")"
  ((checked > 0)) || fail "the registry has no type that takes new documents"
}

@test "without ID= a new unused id is used, and a second run with the same slug the same day is refused" {
  local path
  run "$CREATE" plan next-plan
  assert_success
  path="${lines[${#lines[@]} - 1]}"
  [[ "$path" =~ ^docs/plans/plan-${TODAY}-${DOC_ID_PATTERN}-next-plan\.md$ ]] || fail "unexpected path '$path'"
  assert_equal "$(front_value "$path" id)" "$(basename "$path" | sed -E "s/^plan-${DOC_DATE_PATTERN}-(${DOC_ID_PATTERN})-.*/\1/")"
  run "$CREATE" plan next-plan
  assert_failure
  assert_output --partial "already created today"
}

@test "make new-doc rejects a malformed, hex-only or already used ID" {
  local bad
  for bad in K7M2X9QA k7m2x9q k7m2x9qai k7m2x9qi; do
    run "$CREATE" spec some-spec "$bad"
    assert_failure
    assert_output --partial "must be 8 characters"
  done
  run "$CREATE" spec some-spec 0a1b2c3d
  assert_failure
  assert_output --partial "hex digits only"
  [[ ! -e "docs/specs/spec-$TODAY-0a1b2c3d-some-spec.md" ]] || fail "a hex-only id still wrote a file"
  run "$CREATE" spec first-spec k7m2x9qa
  assert_success
  run "$CREATE" spec second-spec k7m2x9qa
  assert_failure
  assert_output --partial "already used"
  [[ ! -e "docs/specs/spec-$TODAY-k7m2x9qa-second-spec.md" ]] || fail "a used id still wrote a file"
}

@test "refuses an unknown type, a retired type whose template still exists, a slug that is not lowercase-hyphen and an existing file, and writes nothing" {
  local case args message
  # Retire research in this copy of the registry; its template stays, so only the 새 문서 check can refuse it.
  awk -F'|' 'BEGIN { OFS = "|" } $2 == " research " { $7 = " 금지 " } { print }' docs/README.md >"$BATS_TEST_TMPDIR/README.md"
  cp "$BATS_TEST_TMPDIR/README.md" docs/README.md
  [[ -f "$(doc_type_row docs/README.md research | cut -f7)" ]] || fail "the copy has no research template"
  git commit -q -m "docs: retire research" docs/README.md
  run "$CREATE" spec same-name k7m2x9qa
  assert_success
  printf 'edited\n' >>"docs/specs/spec-$TODAY-k7m2x9qa-same-name.md"
  # Each case: the type and the slug | for the retired type, the message that shows the 새 문서 check refused it, not a
  # registry the awk edit broke.
  for case in "memo note|" "research late-note|no longer created" "spec Bad_Slug|" "spec ../escape|" "spec same-name|"; do
    IFS='|' read -r args message <<<"$case"
    (
      # shellcheck disable=SC2086 # two words: the type and the slug
      run "$CREATE" $args
      assert_failure || exit 1
      if [[ -n "$message" ]]; then
        assert_output --partial "$message"
      fi
    ) || fail "create-doc.sh did not refuse: $args"
  done
  [[ ! -e docs/research ]] || fail "a retired type wrote into docs/research"
  run git status --porcelain --untracked-files=all
  assert_output "?? docs/specs/spec-$TODAY-k7m2x9qa-same-name.md"
  run tail -n 1 "docs/specs/spec-$TODAY-k7m2x9qa-same-name.md"
  assert_output "edited"
}
