#!/usr/bin/env bats
load helpers

setup() {
  SCRIPT="$REPO_DIR/scripts/show-backup.sh"
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  mkdir -p "$BACKUP_DIR"
}

# make_backup NAME [MODE]: a fake archive with a .sha256 and a .manifest; MODE bad-sum writes a wrong checksum,
# no-sum and no-manifest leave that file out.
make_backup() {
  local archive="$BACKUP_DIR/$1.tgz" mode="${2:-ok}"
  printf 'SECRET-ARCHIVE-BYTES %s' "$1" >"$archive"
  case "$mode" in
    bad-sum) printf '%s  %s\n' "$(printf 'x' | shasum -a 256 | awk '{ print $1 }')" "$1.tgz" >"$archive.sha256" ;;
    no-sum) ;;
    *) printf '%s  %s\n' "$(shasum -a 256 "$archive" | awk '{ print $1 }')" "$1.tgz" >"$archive.sha256" ;;
  esac
  [ "$mode" = no-manifest ] || printf 'SECRET-MANIFEST-LINE %s\n' "$1" >"$archive.manifest"
}

@test "prints the newest archive with a matching checksum and its manifest, and never its contents" {
  make_backup bm-20261001T000000Z
  make_backup bm-20261002T000000Z
  # The newer stamp gets the OLDER mtime (a copy or restore can reorder mtimes): the name decides.
  touch -t 202601010000 "$BACKUP_DIR/bm-20261002T000000Z.tgz"
  run "$SCRIPT"
  assert_success
  assert_output --partial "$BACKUP_DIR/bm-20261002T000000Z.tgz"
  refute_output --partial "bm-20261001T000000Z"
  assert_output --partial "checksum: match"
  assert_output --partial "manifest: present"
  refute_output --partial SECRET
}

@test "reports a mismatched checksum, a missing checksum and a missing manifest" {
  local mode expected
  for mode in "bad-sum|checksum: MISMATCH|manifest: present" "no-sum|checksum: missing|manifest: present" "no-manifest|checksum: match|manifest: missing"; do
    (
      rm -f "$BACKUP_DIR"/* || exit 1
      make_backup bm-20261003T000000Z "${mode%%|*}" || exit 1
      expected="${mode#*|}"
      run "$SCRIPT"
      assert_success && assert_output --partial "${expected%%|*}" && assert_output --partial "${expected#*|}" \
        && assert_output --partial "not restorable" && refute_output --partial SECRET
    ) || fail "case ${mode%%|*}"
  done
}

@test "fails with a fix when no archive exists and creates nothing" {
  run "$SCRIPT"
  assert_failure
  assert_output --partial "no bm-*.tgz"
  assert_output --partial "make backup"
  assert_equal "$(find "$BACKUP_DIR" -type f | wc -l | tr -d ' ')" 0
}
