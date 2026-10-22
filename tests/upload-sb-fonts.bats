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

@test "converts Regular and Bold to WOFF2 and writes them into the VM notes folder" {
  run "$SB_FONTS"
  assert_success
  run cat "$FONTS/D2KodingLigatureNerdFont-Regular.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Regular.ttf"
  run cat "$FONTS/D2KodingLigatureNerdFont-Bold.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Bold.ttf"
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
  refute_stub_called '^ssh '
  [[ ! -e "$FONTS" ]] || fail "nothing may be written when a check fails: $FONTS exists"
}

@test "--local writes the WOFF2 files into the local notes folder without ssh and leaves the VM notes folder alone" {
  local local_fonts="$BATS_TEST_TMPDIR/local-notes/Library/agent-hub/fonts"
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/local-notes"
  run "$SB_FONTS" --local
  assert_success
  run cat "$local_fonts/D2KodingLigatureNerdFont-Regular.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Regular.ttf"
  run cat "$local_fonts/D2KodingLigatureNerdFont-Bold.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Bold.ttf"
  refute_stub_called -E '^(ssh|sudo) '
  [[ ! -e "$FONTS" ]] || fail "--local must leave the VM notes folder alone: $FONTS exists"
}
