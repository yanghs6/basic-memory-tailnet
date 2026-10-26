#!/usr/bin/env bats
load helpers

EXEMPTIONS=".public-text-exemptions"

@test "tracked and new files carry no public text outside the exemption list, and every exemption names an existing file" {
  local path kind
  cd "$REPO_DIR" || fail "cannot cd into $REPO_DIR"
  run scripts/check-public-text.sh
  assert_success
  [[ -f "$EXEMPTIONS" ]] || fail "$EXEMPTIONS is missing at the repo root"
  while read -r path kind; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ -f "$path" && ! -L "$path" ]] || fail "$EXEMPTIONS names $path ($kind), which is no regular file: remove the line"
  done <"$EXEMPTIONS"
}
