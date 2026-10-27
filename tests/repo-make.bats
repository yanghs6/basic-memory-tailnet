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

@test "make local-up stops before any compose call on an SB_USER that require_sb_user rejects, without printing it, and starts the stack with a valid one; local-up and local-down refuse a stack another worktree started" {
  linked_worktree_with_makefile
  setup_stubs docker
  cp -R "$REPO_DIR/scripts" "$REPO_DIR/silverbullet" "$REPO_DIR/compose.yaml" "$LINKED_WT/"
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

  : >"$STUB_LOG"
  mkdir -p "$BATS_TEST_TMPDIR/other-worktree"
  export DOCKER_STUB_STACK_DIRS="$BATS_TEST_TMPDIR/other-worktree"
  local target
  for target in local-up local-down; do
    run make_in "$LINKED_WT" "$target"
    assert_failure
    assert_output --partial "make local-down"
  done
  refute_stub_called '^docker compose'
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

@test "make local-up with BM_WEB=on hands COMPOSE_PROFILES=web to compose and runs the same compose command" {
  linked_worktree_with_makefile
  setup_stubs docker
  # The docker stub logs only its arguments; this one also logs the profiles and the gateway base URL compose sees.
  # shellcheck disable=SC2016 # the fake command expands its variables when it runs
  fake_cmd docker 'printf "docker %s\n" "$*" >>"$STUB_LOG"
printf "env [%s] [%s]\n" "${COMPOSE_PROFILES-unset}" "${BM_WEB_BASE_URL-unset}" >>"$STUB_LOG"'
  cp -R "$REPO_DIR/scripts" "$REPO_DIR/silverbullet" "$REPO_DIR/compose.yaml" "$LINKED_WT/"
  printf 'SB_USER=admin:Tr4mpoline\nBM_WEB=on\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_success
  run grep -c '^docker compose -f compose.yaml up -d --wait$' "$STUB_LOG"
  assert_output 1
  assert_stub_called -Fx 'env [web] [http://127.0.0.1:8738]'
  refute_stub_called -F 'env [unset]'
  [[ -d "$LINKED_WT/.local-data/gateway" ]] || fail "make local-up must create .local-data/gateway for the gateway store"

  : >"$STUB_LOG"
  printf 'SB_USER=admin:Tr4mpoline\nBM_WEB=yes\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-up
  assert_failure
  assert_output --partial "BM_WEB must be on or off (got 'yes')"
  refute_stub_called '^docker '
}

@test "make local-verify with BM_WEB=on runs the gateway unit tests as uid 1000, and without it touches no container" {
  linked_worktree_with_makefile
  setup_stubs docker
  mkdir -p "$LINKED_WT/scripts"
  local name
  for name in verify-mcp verify-sb verify-web; do
    # shellcheck disable=SC2016 # the generated script expands $* and $STUB_LOG when it runs
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUB_LOG"\n' "$name" >"$LINKED_WT/scripts/$name.sh"
    chmod +x "$LINKED_WT/scripts/$name.sh"
  done
  printf 'SB_USER=admin:Tr4mpoline\nBM_WEB=on\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-verify
  assert_success
  assert_stub_called -Fx 'verify-web http://127.0.0.1:8738'
  # The gateway serves the public path as uid 1000; its tests run as the same user, never as root.
  assert_stub_called -Fx 'docker compose -f compose.yaml exec -T --user 1000:1000 gateway python -m unittest -v test_gateway'

  : >"$STUB_LOG"
  printf 'SB_USER=admin:Tr4mpoline\n' >"$MAIN_REPO/.env"
  run make_in "$LINKED_WT" local-verify
  assert_success
  refute_stub_called '^verify-web '
  refute_stub_called '^docker '
}

@test "make secret-scan runs the digest-pinned gitleaks image over all refs with the git common dir mounted read-only" {
  linked_worktree_with_makefile
  setup_stubs docker
  run make_in "$LINKED_WT" secret-scan
  assert_success
  run grep -cE "^docker run --rm -v $LINKED_WT:/repo -v $MAIN_REPO/\.git:$MAIN_REPO/\.git:ro -w /repo zricethezav/gitleaks:v[0-9.]+@sha256:[0-9a-f]{64} git --redact --verbose --log-opts=--all /repo$" "$STUB_LOG"
  assert_output 1
}

@test "make help prints each target with its ## description" {
  local description line
  linked_worktree_with_makefile
  description="$(sed -n 's/^check:.*## //p' "$REPO_DIR/Makefile")"
  run make_in "$LINKED_WT" help
  assert_success
  line="$(grep -E '^ +check ' <<<"$output")" || fail "make help printed no check line:"$'\n'"$output"
  [[ "$line" == *" $description" ]] || fail "make help printed '$line'; expected the description from the Makefile check line: '$description'"
}

@test "make fmt, test, local-down and local-logs run their docker command in the checkout they run from" {
  local target shfmt_image tools_image
  shfmt_image="$(sed -n 's/^SHFMT_IMAGE := //p' "$REPO_DIR/Makefile")"
  tools_image="$(sed -n 's/^TOOLS_IMAGE := //p' "$REPO_DIR/Makefile")"
  for target in fmt test local-down local-logs; do
    (
      rm -rf "$BATS_TEST_TMPDIR/main" "$BATS_TEST_TMPDIR/linked" && linked_worktree_with_makefile \
        && setup_stubs docker && : >"$STUB_LOG" || exit 1
      # docker is the stub and the mount is the fixture, so make fmt rewrites nothing in this repo.
      if [[ "$target" == fmt ]]; then
        touch "$LINKED_WT/probe.sh" || exit 1
      fi
      # local-down first runs scripts/check-local-stack.sh, which reads compose.yaml; the stub reports no stack.
      if [[ "$target" == local-down ]]; then
        cp -R "$REPO_DIR/scripts" "$REPO_DIR/compose.yaml" "$LINKED_WT/" || exit 1
      fi
      run make_in "$LINKED_WT" "$target"
      assert_success || exit 1
      case "$target" in
        fmt) assert_stub_called -Fx "docker run --rm -v $LINKED_WT:/repo -v $MAIN_REPO/.git:$MAIN_REPO/.git:ro -w /repo $shfmt_image -w probe.sh" ;;
        test) assert_log_order "docker build -q -t $tools_image tools" "$tools_image bats tests" ;;
        local-down) assert_stub_called -Fx 'docker compose -f compose.yaml down' ;;
        local-logs) assert_stub_called -Fx 'docker compose -f compose.yaml logs --tail=200' ;;
      esac
    ) || fail "make $target did not run its docker command in the linked worktree it ran from"
  done
}
