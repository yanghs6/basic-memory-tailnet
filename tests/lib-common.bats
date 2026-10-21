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
