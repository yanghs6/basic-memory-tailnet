#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh sudo
  use_vm_env
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/notes"
  # shellcheck source=../scripts/lib/sb.sh
  . "$REPO_DIR/scripts/lib/sb.sh"
}

@test "the libraries load in any order and more than once, and common.sh alone holds no VM or SilverBullet settings" {
  # A script file, not bash -c: under make coverage, kcov's exported PS4 reads BASH_SOURCE, which bash -c leaves
  # unset at its top level, so set -u would stop it there.
  cat >"$BATS_TEST_TMPDIR/load.sh" <<'EOF'
set -euo pipefail
. "$1/scripts/lib/common.sh"
[[ -z "${BM_CONTAINER_UID+x}${SB_GITIGNORE_PENDING+x}" ]] || { echo "common.sh loaded VM settings"; exit 1; }
. "$1/scripts/lib/sb.sh"; . "$1/scripts/lib/vm.sh"; . "$1/scripts/lib/common.sh"; . "$1/scripts/lib/sb.sh"
printf '%s|%s\n' "$REPO_DIR" "$SB_REMOTE_NOTES_DIR"
EOF
  run env REPO_DIR=/nowhere bash "$BATS_TEST_TMPDIR/load.sh" "$REPO_DIR"
  assert_success
  assert_output "$REPO_DIR|$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
}
