#!/usr/bin/env bats
load helpers

setup() {
  make_worktree_fixture
  cp "$REPO_DIR/Makefile" "$MAIN_REPO/Makefile"
  cp "$REPO_DIR/Makefile" "$LINKED_WT/Makefile"
  # Keep git from finding a repository above the fixtures (the plain-directory tests).
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
}

# make_host DIR -> the BM_VM_HOST value make sees when it runs in DIR, printed as [value].
make_host() {
  cd "$1"
  # make coverage runs bats under kcov, which exports xtrace settings that break make's `bash -u` shell
  # (same reason as tests/repo.bats:65-66), so every make call here drops them.
  env -u SHELLOPTS -u PS4 -u BASH_ENV make --no-print-directory --eval='show-host: ; @echo "[$(BM_VM_HOST)]"' show-host
}

# use_backup_env: stubs and a fake VM for backup.sh. BACKUP_DIR stays unset: the default location is under test.
use_backup_env() {
  setup_stubs ssh docker sudo
  use_vm_env
  unset BACKUP_DIR
  echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
}

# --- Makefile ---

@test "make reads .env from the main checkout when run there" {
  printf 'BM_VM_HOST=main-host\n' >"$MAIN_REPO/.env"
  run make_host "$MAIN_REPO"
  assert_success
  assert_output "[main-host]"
}

@test "make reads the main checkout .env, not the worktree .env, from a linked worktree" {
  printf 'BM_VM_HOST=main-host\n' >"$MAIN_REPO/.env"
  printf 'BM_VM_HOST=worktree-host\n' >"$LINKED_WT/.env"
  run make_host "$LINKED_WT"
  assert_success
  assert_output "[main-host]"
}

@test "make ignores a worktree .env when the main checkout has none" {
  printf 'BM_VM_HOST=worktree-host\n' >"$LINKED_WT/.env"
  run make_host "$LINKED_WT"
  assert_success
  assert_output "[]"
}

@test "make falls back to ./.env outside a git repository without git noise" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  cp "$REPO_DIR/Makefile" "$BATS_TEST_TMPDIR/plain/Makefile"
  printf 'BM_VM_HOST=plain-host\n' >"$BATS_TEST_TMPDIR/plain/.env"
  run make_host "$BATS_TEST_TMPDIR/plain"
  assert_success
  assert_output "[plain-host]"
}

@test "make help still lists the targets from a linked worktree" {
  cd "$LINKED_WT"
  run env -u SHELLOPTS -u PS4 -u BASH_ENV make help
  assert_success
  assert_output --partial "backup"
  assert_output --partial "restore"
}

# --- backup ---

@test "backup from a linked worktree saves into the main checkout's backups/" {
  use_backup_env
  cp -R "$REPO_DIR/scripts" "$LINKED_WT/scripts"
  cd "$LINKED_WT"
  run "$LINKED_WT/scripts/backup.sh"
  assert_success
  assert_output --partial "backup saved: $MAIN_REPO/backups/bm-"
  run ls "$MAIN_REPO/backups"
  assert_success
  assert_output --partial ".tgz.sha256"
  [[ ! -e "$LINKED_WT/backups" ]]
}

@test "backup prints an absolute path when BACKUP_DIR is relative" {
  use_backup_env
  cd "$BATS_TEST_TMPDIR"
  BACKUP_DIR=relative-backups run "$REPO_DIR/scripts/backup.sh"
  assert_success
  assert_output --partial "backup saved: $BATS_TEST_TMPDIR/relative-backups/bm-"
}

@test "backup defaults to backups/ in the main checkout that git reports" {
  use_backup_env
  GIT_DIR="$MAIN_REPO/.git" run "$REPO_DIR/scripts/backup.sh"
  assert_success
  assert_output --partial "backup saved: $MAIN_REPO/backups/bm-"
  run ls "$MAIN_REPO/backups"
  assert_output --partial ".tgz.manifest"
}

@test "backup fails with an actionable message when the main checkout cannot be found" {
  use_backup_env
  GIT_DIR="$BATS_TEST_TMPDIR/missing-repo" run "$REPO_DIR/scripts/backup.sh"
  assert_failure
  assert_output --partial "cannot find the main checkout"
  assert_output --partial "set BACKUP_DIR"
  run grep -F 'docker compose' "$STUB_LOG"
  assert_failure
}

# --- restore ---

@test "restore names the main checkout's backups/ when the archive is not found" {
  run "$REPO_DIR/scripts/restore.sh" backups/bm-missing.tgz
  assert_failure
  assert_output --partial "backup not found: backups/bm-missing.tgz"
  assert_output --partial "<main checkout>/backups/"
}

# --- git-workflow skill ---

@test "git-workflow cleanup checks the worktree's backups before git worktree remove" {
  run grep -E 'ls <your worktree>/backups.*git worktree remove <your worktree>' \
    "$REPO_DIR/.agents/skills/git-workflow/SKILL.md"
  assert_success
}
