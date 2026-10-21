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

@test "creates a document of every type that takes new ones, named, placed and with front matter as its registry row says" {
  local type code number location statuses keys new path expected doc_status key checked=0
  while IFS=$'\t' read -r type code number location statuses keys new _; do
    [[ "$new" == "허용" ]] || continue
    checked=$((checked + 1))
    path="$("$CREATE" "$type" "check-$code" 2>/dev/null)" || fail "create-doc.sh failed for $type"
    if [[ "$number" == "없음" ]]; then
      expected="${location%/}/$code-$TODAY-check-$code.md"
    else
      expected="${location%/}/$code-$TODAY-$(printf '%0*d' "${#number}" 1)-check-$code.md"
    fi
    assert_equal "$path" "$expected"
    # Not "status": bats run sets that name.
    doc_status="$(front_value "$path" status)"
    [[ ", $statuses," == *", $doc_status,"* ]] || fail "$type: status '$doc_status' is not one of: $statuses"
    for key in $(tr ',' ' ' <<<"$keys"); do
      frontmatter "$path" | grep -q "^$key: " || fail "$type: the front matter has no $key"
    done
    run grep -nE '\{\{(date|number|slug)\}\}' "$path"
    assert_failure 1
  done <<<"$(doc_types "$WORK/docs/README.md")"
  ((checked > 0)) || fail "the registry has no type that takes new documents"
}

@test "numbers plans and ADRs one past the largest number on any branch or in the working tree, in old and new names" {
  mkdir -p docs/plans/completed docs/decisions
  : >docs/plans/completed/2026-10-07-01-first.md
  : >docs/decisions/0006-old-name.md
  # A dated file in the ADR folder must not count as ADR 2026.
  : >docs/decisions/2026-10-01-draft.md
  git add -A
  git commit -q -m "docs: documents with old names"
  git switch -q -c plan/05-local
  mkdir -p docs/plans/backlog
  : >docs/plans/backlog/2026-10-13-05-local.md
  git add -A
  git commit -q -m "docs: plan 05 on a local branch"
  # Only a remote-tracking branch has plan 09, under a new name; 09 is not a valid octal number.
  git switch -q -c scratch
  : >docs/plans/plan-2026-10-14-09-remote.md
  git add -A
  git commit -q -m "docs: plan 09 pushed by another agent"
  git update-ref refs/remotes/origin/plan/09-remote HEAD
  git switch -q main
  git branch -q -D scratch
  run "$CREATE" plan next-plan
  assert_success
  assert_line "docs/plans/plan-$TODAY-10-next-plan.md"
  assert_output --partial "git fetch origin"
  # Running it again with the same slug the same day must not take another number.
  run "$CREATE" plan next-plan
  assert_failure
  # The first new plan is untracked; the working tree counts too.
  run "$CREATE" plan another-plan
  assert_success
  assert_line "docs/plans/plan-$TODAY-11-another-plan.md"
  run "$CREATE" adr next-adr
  assert_success
  assert_line "docs/decisions/adr-$TODAY-0007-next-adr.md"
}

@test "refuses an unknown type, a retired type whose template still exists, a slug that is not lowercase-hyphen and an existing file, and writes nothing" {
  local case args message
  # Retire research in this copy of the registry; its template stays, so only the 새 문서 check can refuse it.
  awk -F'|' 'BEGIN { OFS = "|" } $2 == " research " { $8 = " 금지 " } { print }' docs/README.md >"$BATS_TEST_TMPDIR/README.md"
  cp "$BATS_TEST_TMPDIR/README.md" docs/README.md
  [[ -f "$(doc_type_row docs/README.md research | cut -f8)" ]] || fail "the copy has no research template"
  git commit -q -m "docs: retire research" docs/README.md
  run "$CREATE" spec same-name
  assert_success
  printf 'edited\n' >>"docs/specs/spec-$TODAY-same-name.md"
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
  assert_output "?? docs/specs/spec-$TODAY-same-name.md"
  run tail -n 1 "docs/specs/spec-$TODAY-same-name.md"
  assert_output "edited"
}
