#!/usr/bin/env bash
# Run the bats suite under kcov and enforce a minimum line coverage for scripts/.
# Usage (inside the tools image, repo mounted at /repo): tools/coverage.sh MIN_PERCENT
set -euo pipefail

readonly MIN_PERCENT="${1:?usage: tools/coverage.sh MIN_PERCENT}"
readonly REPO_DIR=/repo
readonly OUT_DIR="$REPO_DIR/.coverage"

rm -rf "$OUT_DIR"
kcov --include-path="$REPO_DIR/scripts" "$OUT_DIR" bats "$REPO_DIR/tests"

report="$(find "$OUT_DIR" -path '*/bats.*/coverage.json' | head -n 1)"
[[ -n "$report" ]] || {
  echo "kcov produced no coverage.json under $OUT_DIR" >&2
  exit 1
}
jq -r '.files[] | "\(.percent_covered)%\t\(.file)"' "$report"

missing=""
while IFS= read -r script; do
  if ! jq -e --arg f "$script" 'any(.files[]; .file == $f)' "$report" >/dev/null; then
    missing="$missing $script"
  fi
done < <(find "$REPO_DIR/scripts" -name '*.sh' -not -path '*/lib/*' | sort)
if [[ -n "$missing" ]]; then
  echo "never executed by any test (add bats tests):$missing" >&2
  exit 1
fi

total="$(jq -r '.percent_covered' "$report")"
echo "total line coverage: ${total}% (minimum ${MIN_PERCENT}%)"
if awk -v total="$total" -v min="$MIN_PERCENT" 'BEGIN { exit !(total + 0 < min + 0) }'; then
  echo "coverage below ${MIN_PERCENT}%: add tests for the uncovered lines (open .coverage/index.html)" >&2
  exit 1
fi
