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
  export BM_VM_HOST=bm-node BM_VM_USER=ubuntu BM_TAILNET_DOMAIN=example.ts.net BM_PORT=8737
  export BM_REMOTE_APP_DIR="$BATS_TEST_TMPDIR/opt/basic-memory"
  export BM_REMOTE_DATA_ROOT="$BATS_TEST_TMPDIR/srv/basic-memory"
  mkdir -p "$BM_REMOTE_APP_DIR" "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config"
}
