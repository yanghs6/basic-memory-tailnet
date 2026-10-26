# shellcheck shell=bash
# Shared bats helpers. Every test file starts with: load helpers
bats_load_library bats-support
bats_load_library bats-assert

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_DIR

# setup_stubs NAME... : put tests/stubs/NAME first on PATH. Stubs log "<name> <args>" to $STUB_LOG.
setup_stubs() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUB_BIN"
  touch "$STUB_LOG"
  local name
  for name in "$@"; do
    ln -sf "$REPO_DIR/tests/stubs/$name" "$STUB_BIN/$name"
  done
  export STUB_BIN STUB_LOG PATH="$STUB_BIN:$PATH"
}

# use_vm_env: point scripts at a fake VM whose directories live in the test tmpdir.
use_vm_env() {
  export BM_VM_HOST=agent-hub BM_VM_USER=ubuntu BM_TAILNET_DOMAIN=example.ts.net BM_PORT=8737
  export SB_USER=admin:test-password SB_PORT=3000
  export BM_REMOTE_APP_DIR="$BATS_TEST_TMPDIR/opt/basic-memory"
  export BM_REMOTE_DATA_ROOT="$BATS_TEST_TMPDIR/srv/basic-memory"
  mkdir -p "$BM_REMOTE_APP_DIR" "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config"
}

# use_ssh_mode: the ssh access mode over an SSH alias, with 127.0.0.1 ports open only once the verify tunnel started and Tailscale on the VM
# logged out.
use_ssh_mode() {
  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap NC_STUB_OPEN_AFTER_TUNNEL=127.0.0.1 TS_STUB_BACKEND_STATE=NeedsLogin
  unset BM_TAILNET_DOMAIN
}

# use_provision_env: the fake VM of use_vm_env plus the etc, run and swap paths and the os-release that provision-vm.sh reads.
use_provision_env() {
  use_vm_env
  export ETC_DIR="$BATS_TEST_TMPDIR/etc" RUN_DIR="$BATS_TEST_TMPDIR/run"
  export OS_RELEASE="$REPO_DIR/tests/fixtures/remote-provision-vm/os-release" ADMIN_USER=root
  export SWAP_FILE="$BATS_TEST_TMPDIR/swapfile"
  mkdir -p "$RUN_DIR" "$ETC_DIR"
}

# make_worktree_fixture: MAIN_REPO (a main checkout) and LINKED_WT (a linked worktree of it), as real paths.
make_worktree_fixture() {
  MAIN_REPO="$BATS_TEST_TMPDIR/main"
  LINKED_WT="$BATS_TEST_TMPDIR/linked"
  git init -q -b main "$MAIN_REPO"
  git -C "$MAIN_REPO" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m "chore: init"
  git -C "$MAIN_REPO" worktree add -q "$LINKED_WT" -b work/fixture
  MAIN_REPO="$(cd "$MAIN_REPO" && pwd -P)"
  LINKED_WT="$(cd "$LINKED_WT" && pwd -P)"
  export MAIN_REPO LINKED_WT
}

# skill_dirs: the canonical skill directories under .agents/skills, one per line.
skill_dirs() {
  find "$REPO_DIR/.agents/skills" -mindepth 1 -maxdepth 1 -type d | sort
}

# frontmatter FILE: the YAML lines between the opening and closing --- of FILE.
frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1"
}

# front_value FILE KEY: the one-line value of KEY in the front matter of FILE; empty when FILE has no KEY.
front_value() {
  frontmatter "$1" | sed -n "s/^$2: *//p"
}

# outside_code FILE: the lines of FILE outside ``` fences.
outside_code() {
  awk '/^```/ { fence = !fence; next } !fence' "$1"
}

# markdown_files: the tracked and the new (untracked, not ignored) Markdown files, relative to the repo, one per line.
markdown_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.md'
}

# init_git_repo: a git repository on main in $BATS_TEST_TMPDIR/work with one empty commit by agent, and cd into it. Sets WORK.
init_git_repo() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b main "$WORK"
  cd "$WORK" || return
  git config user.email agent@example.com
  git config user.name agent
  git commit -q --allow-empty -m "chore: init"
}

# agent_commit TOOL SUBJECT [GIT_COMMIT_ARG...]: an empty commit with the trailers the git policy requires (Assisted-by TOOL,
# Plan $PLAN_TRAILER, default 02).
agent_commit() {
  local tool="$1" subject="$2"
  shift 2
  git commit -q --allow-empty -m "$subject" \
    --trailer "Assisted-by: $tool model-x" --trailer "Plan: ${PLAN_TRAILER:-02}" --trailer "Task: 1" "$@"
}

# use_mcp_fixtures sse|json: copy tests/fixtures/verify-mcp/<kind> to the test tmpdir and point the curl stub at the copy.
use_mcp_fixtures() {
  local kind="$1"
  cp -R "$REPO_DIR/tests/fixtures/verify-mcp/$kind" "$BATS_TEST_TMPDIR/mcp-$kind"
  export CURL_FIXTURES="$BATS_TEST_TMPDIR/mcp-$kind"
}

# fake_cmd NAME BODY: a new executable $STUB_BIN/NAME running BODY. Call after setup_stubs. The old file is removed first
# because NAME may be a symlink to a stub in tests/stubs and writing through it would overwrite the stub.
fake_cmd() {
  rm -f "$STUB_BIN/$1"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# assert_stub_called GREP_ARG...: succeed when grep GREP_ARG... finds a line in $STUB_LOG; fail when it finds none or grep errors.
assert_stub_called() {
  local status=0
  grep "$@" "$STUB_LOG" >/dev/null || status=$?
  if [[ "$status" -eq 0 ]]; then
    return 0
  fi
  if [[ "$status" -eq 1 ]]; then
    fail "expected a stub log line matching: $*"$'\n'"stub log:"$'\n'"$(cat "$STUB_LOG")"
    return 1
  fi
  fail "grep failed with exit $status on the stub log: $*"
  return 1
}

# refute_stub_called GREP_ARG...: succeed when grep GREP_ARG... finds no line in $STUB_LOG; fail when it finds one or grep errors.
refute_stub_called() {
  local status=0 found
  found="$(grep "$@" "$STUB_LOG")" || status=$?
  if [[ "$status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$status" -eq 0 ]]; then
    fail "expected no stub log line matching: $*"$'\n'"found:"$'\n'"$found"
    return 1
  fi
  fail "grep failed with exit $status on the stub log: $*"
  return 1
}

# assert_log_order TEXT...: the first $STUB_LOG line containing each TEXT (fixed string) comes after the one of the previous TEXT.
assert_log_order() {
  local text line previous=0
  for text in "$@"; do
    line="$(grep -nF -m1 -- "$text" "$STUB_LOG" | cut -d: -f1)"
    if [[ -z "$line" ]]; then
      fail "no stub log line contains: $text"$'\n'"stub log:"$'\n'"$(cat "$STUB_LOG")"
      return 1
    fi
    if [[ "$line" -le "$previous" ]]; then
      fail "stub log line $line ($text) does not come after line $previous"$'\n'"stub log:"$'\n'"$(cat "$STUB_LOG")"
      return 1
    fi
    previous="$line"
  done
}

# assert_same_file EXPECTED ACTUAL: fail with the diff when the two files differ or either is missing.
assert_same_file() {
  local difference status=0
  difference="$(diff "$1" "$2" 2>&1)" || status=$?
  if [[ "$status" -ne 0 ]]; then
    fail "files differ: $1 $2"$'\n'"$difference"
    return 1
  fi
}

# refute_matches DIR ERE [GREP_FLAG...]: succeed when grep -rnE ERE [GREP_FLAG...] finds no line under DIR; fail with the
# matching lines when it finds one, and when grep errors.
refute_matches() {
  local dir="$1" pattern="$2" status=0 found
  shift 2
  found="$(grep -rnE "$@" -e "$pattern" -- "$dir")" || status=$?
  if [[ "$status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$status" -eq 0 ]]; then
    fail "expected no line under $dir matching: $pattern"$'\n'"found:"$'\n'"$found"
    return 1
  fi
  fail "grep failed with exit $status under $dir: $pattern"
  return 1
}
