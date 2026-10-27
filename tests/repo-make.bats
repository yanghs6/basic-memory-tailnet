#!/usr/bin/env bats
load helpers

# linked_worktree_with_makefile -> MAIN_REPO and LINKED_WT (make_worktree_fixture), with this repo's Makefile in
# LINKED_WT. The tests that run make call it first.
linked_worktree_with_makefile() {
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

@test "every Make target is defined once, has a ## description and is declared .PHONY" {
  local lines line phony target bad=""
  lines="$(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile")" || fail "found no targets in the Makefile"
  phony=" $(grep -E '^\.PHONY:' "$REPO_DIR/Makefile" | cut -d: -f2 | tr '\n' ' ') "
  while IFS= read -r line; do
    target="${line%%:*}"
    [[ "$line" == *"## "* ]] || bad="$bad"$'\n'"  $target: add '## <description>'"
    [[ "$phony" == *" $target "* ]] || bad="$bad"$'\n'"  $target: add it to .PHONY"
  done <<<"$lines"
  for target in $(cut -d: -f1 <<<"$lines" | sort | uniq -d); do
    bad="$bad"$'\n'"  $target: defined more than once (make keeps only the last recipe)"
  done
  [[ -z "$bad" ]] || fail "fix these Makefile targets:$bad"
}

@test "make reads the main checkout .env, not the worktree .env, from a linked worktree" {
  linked_worktree_with_makefile
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

@test "make local-up stops before any compose call on an SB_USER that require_sb_user rejects, without printing it, and starts the stack with a valid one" {
  linked_worktree_with_makefile
  setup_stubs docker
  cp -R "$REPO_DIR/scripts" "$REPO_DIR/silverbullet" "$LINKED_WT/"
  # make reads .env as makefile text, so # starts a comment and it passes on admin:Tr4mp.
  printf 'SB_USER=admin:Tr4mp#oline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_failure
  refute_output --partial "Tr4mp"
  refute_stub_called '^docker '

  printf 'SB_USER=admin:Tr4mpoline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_success
  refute_output --partial "Tr4mp"
  run grep -c '^docker compose -f compose.yaml up -d --wait$' "$STUB_LOG"
  assert_output 1
}

@test "make verify hands SB_USER and the env file path to the VM check; make probe hands neither" {
  linked_worktree_with_makefile
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

@test "make secret-scan runs the digest-pinned gitleaks image over all refs with the git common dir mounted read-only" {
  linked_worktree_with_makefile
  setup_stubs docker
  run make_in "$LINKED_WT" secret-scan
  assert_success
  run grep -cE "^docker run --rm -v $LINKED_WT:/repo -v $MAIN_REPO/\.git:$MAIN_REPO/\.git:ro -w /repo zricethezav/gitleaks:v[0-9.]+@sha256:[0-9a-f]{64} git --redact --log-opts=--all /repo$" "$STUB_LOG"
  assert_output 1
}
