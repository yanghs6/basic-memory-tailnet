#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh sudo python3
  use_vm_env
  export SB_FONT_DIR="$BATS_TEST_TMPDIR/fonts"
  mkdir -p "$SB_FONT_DIR"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Regular.ttf"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  SB_FONTS="$REPO_DIR/scripts/upload-sb-fonts.sh"
  FONTS="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/fonts"
}

@test "converts Regular and Bold to WOFF2 and writes them into the VM notes folder as the container user" {
  run "$SB_FONTS"
  assert_success
  run cat "$FONTS/D2KodingLigatureNerdFont-Regular.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Regular.ttf"
  run cat "$FONTS/D2KodingLigatureNerdFont-Bold.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Bold.ttf"
  run grep -F 'sudo -n -u #1000 sh -c' "$STUB_LOG"
  assert_success
}

@test "writes nothing when a font file or fontTools is missing" {
  rm "$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  run "$SB_FONTS"
  assert_failure
  assert_output --partial "SB_FONT_DIR"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  PYTHON3_STUB_NO_MODULES=1 run "$SB_FONTS"
  assert_failure
  assert_output --partial "pip install --user fonttools brotli"
  run grep -c '^ssh ' "$STUB_LOG"
  assert_output 0
  [[ ! -e "$FONTS" ]] || fail "nothing may be written when a check fails: $FONTS exists"
}
