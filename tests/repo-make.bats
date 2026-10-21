#!/usr/bin/env bats
load helpers

@test "every Make target has a ## description and is declared .PHONY" {
  local line phony target missing_desc="" missing_phony=""
  phony=" $(grep -E '^\.PHONY:' "$REPO_DIR/Makefile" | cut -d: -f2 | tr '\n' ' ') "
  while IFS= read -r line; do
    target="${line%%:*}"
    [[ "$line" == *"## "* ]] || missing_desc="$missing_desc $target"
    [[ "$phony" == *" $target "* ]] || missing_phony="$missing_phony $target"
  done < <(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile")
  [[ -z "$missing_desc" ]] || fail "add '## <description>' to these Makefile targets:$missing_desc"
  [[ -z "$missing_phony" ]] || fail "add these targets to .PHONY in the Makefile:$missing_phony"
}

@test "no Make target is defined twice" {
  local dupes
  dupes="$(grep -oE '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | cut -d: -f1 | sort | uniq -d)"
  [[ -z "$dupes" ]] || fail "these Make targets are defined more than once (make keeps only the last recipe): $dupes"
}

setup() {
  make_worktree_fixture
  cp "$REPO_DIR/Makefile" "$LINKED_WT/Makefile"
}

# make_host DIR -> the BM_VM_HOST value make sees when it runs in DIR, printed as [value].
make_host() {
  cd "$1" || return
  # make coverage runs bats under kcov, which exports xtrace settings (SHELLOPTS, PS4, BASH_ENV) that break make's
  # `bash -u` shell, so every make call here drops them.
  # shellcheck disable=SC2016 # $(BM_VM_HOST) is make syntax, not shell
  env -u SHELLOPTS -u PS4 -u BASH_ENV make --no-print-directory --eval='show-host: ; @echo "[$(BM_VM_HOST)]"' show-host
}

# make_in DIR TARGET -> run make TARGET in DIR, dropping the kcov xtrace settings for the reason given at make_host.
make_in() {
  cd "$1" || return
  env -u SHELLOPTS -u PS4 -u BASH_ENV make --no-print-directory "$2"
}

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

@test "make local-up stops before any compose call on an SB_USER that require_sb_user rejects, without printing it" {
  setup_stubs docker
  cp -R "$REPO_DIR/scripts" "$REPO_DIR/silverbullet" "$LINKED_WT/"
  # make reads .env as makefile text, so # starts a comment and it passes on admin:Tr4mp.
  printf 'SB_USER=admin:Tr4mp#oline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_failure
  refute_output --partial "Tr4mp"
  refute_stub_called '^docker '
}

@test "make verify hands SB_USER and the env file path to the VM check; make probe hands neither" {
  unset SB_USER SB_ENV_FILE
  mkdir -p "$LINKED_WT/scripts"
  # shellcheck disable=SC2016 # the generated script must keep ${SB_USER-unset} literal
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
