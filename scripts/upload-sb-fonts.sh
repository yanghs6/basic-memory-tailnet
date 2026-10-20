#!/usr/bin/env bash
# Convert the D2KodingLigature Nerd Font (Regular and Bold) to WOFF2 and write both files into the SilverBullet space,
# where the managed library page loads them with @font-face. The fonts stay out of git (4.7 MB, Nerd Fonts licenses).
# Usage: make sb-fonts [LOCAL=1]   (reads the TTFs from $SB_FONT_DIR, default ~/Library/Fonts)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sb.sh
. "$SCRIPT_DIR/lib/sb.sh"

readonly FONT_FILE_PREFIX=D2KodingLigatureNerdFont
readonly FONT_STYLES="Regular Bold"
readonly FONT_RELEASES_URL=https://github.com/ryanoasis/nerd-fonts/releases

WORK=""

main() {
  local local_dir font_dir="${SB_FONT_DIR:-$HOME/Library/Fonts}" style name
  local_dir="$(notes_dir_arg "make sb-fonts [LOCAL=1]" "$@")" || exit 1
  for style in $FONT_STYLES; do
    [[ -f "$font_dir/$FONT_FILE_PREFIX-$style.ttf" ]] \
      || die "missing $font_dir/$FONT_FILE_PREFIX-$style.ttf: install the D2Coding Nerd Font from $FONT_RELEASES_URL or point SB_FONT_DIR at the folder that has it"
  done
  require_cmd python3
  # Plain python3, not -I: -I drops the user site-packages, where the suggested pip install --user puts fontTools.
  python3 -c 'import fontTools.ttLib.woff2, brotli' 2>/dev/null \
    || die "python3 cannot write WOFF2 yet: python3 -m pip install --user fonttools brotli"

  WORK="$(mktemp -d)" || exit 1
  trap 'rm -rf "$WORK"' EXIT
  for style in $FONT_STYLES; do
    name="$FONT_FILE_PREFIX-$style.woff2"
    python3 -m fontTools.ttLib.woff2 compress -q -o "$WORK/$name" "$font_dir/$FONT_FILE_PREFIX-$style.ttf" \
      || die "could not convert $FONT_FILE_PREFIX-$style.ttf to WOFF2"
    write_notes_file "$local_dir" "$SB_FONTS_REL_DIR/$name" <"$WORK/$name" \
      || die "could not write $SB_FONTS_REL_DIR/$name into the notes folder"
    log "wrote $SB_FONTS_REL_DIR/$name"
  done
  log "done: reload SilverBullet in the browser"
}

main "$@"
