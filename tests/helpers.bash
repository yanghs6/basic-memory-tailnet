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
