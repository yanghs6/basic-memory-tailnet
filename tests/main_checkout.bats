#!/usr/bin/env bats
load helpers

setup() {
  make_worktree_fixture
  cp "$REPO_DIR/Makefile" "$LINKED_WT/Makefile"
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

@test "make reads the main checkout .env, not the worktree .env, from a linked worktree" {
  printf 'BM_VM_HOST=main-host\n' >"$MAIN_REPO/.env"
  printf 'BM_VM_HOST=worktree-host\n' >"$LINKED_WT/.env"
  run make_host "$LINKED_WT"
  assert_success
  assert_output "[main-host]"

  rm "$MAIN_REPO/.env"
  run make_host "$LINKED_WT"
  assert_success
  assert_output "[]"
}

# make_in DIR TARGET -> run make TARGET in DIR (same kcov workaround as make_host).
make_in() {
  cd "$1"
  env -u SHELLOPTS -u PS4 -u BASH_ENV make --no-print-directory "$2"
}

@test "make local-up stops before any compose call when make cut SB_USER short while reading the main checkout .env" {
  setup_stubs docker
  cp -R "$REPO_DIR/scripts" "$REPO_DIR/silverbullet" "$LINKED_WT/"
  printf 'SB_USER=admin:Tr4mp#oline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_failure
  assert_output --partial "SB_USER in $MAIN_REPO/.env"
  refute_output --partial "Tr4mp"
  run grep -c '^docker ' "$STUB_LOG"
  assert_output 0

  printf 'SB_USER=admin:Tr4mpoline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_success
  refute_output --partial "Tr4mp"
  run grep -c '^docker compose -f compose.yaml up -d --wait$' "$STUB_LOG"
  assert_output 1
}

@test "make verify hands SB_USER and the env file path to the VM check; make probe hands neither" {
  unset SB_USER SB_ENV_FILE
  mkdir -p "$LINKED_WT/scripts"
  printf '#!/usr/bin/env bash\necho "[${SB_USER-unset}] [${SB_ENV_FILE-unset}] $*"\n' >"$LINKED_WT/scripts/verify-vm.sh"
  chmod +x "$LINKED_WT/scripts/verify-vm.sh"
  printf 'SB_USER=admin:Tr4mpoline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" verify
  assert_success
  assert_output --partial "[admin:Tr4mpoline] [$MAIN_REPO/.env] "
  run make_in "$LINKED_WT" probe
  assert_success
  assert_output --partial "[unset] [unset] --read-only"
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

# --- git-workflow skill ---

@test "git-workflow cleanup checks the worktree's backups before git worktree remove" {
  run grep -E 'ls <your worktree>/backups.*git worktree remove <your worktree>' \
    "$REPO_DIR/.agents/skills/git-workflow/references/review-and-merge.md"
  assert_success
}
