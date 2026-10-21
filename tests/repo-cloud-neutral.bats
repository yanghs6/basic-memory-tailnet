#!/usr/bin/env bats
load helpers

CLOUD_NAMES='oci|oracle|gcp|gcloud'
# The runbook's file name is the one allowed mention: scripts point to it instead of naming a provider.
ALLOWED_RUNBOOK='docs/runbooks/rbk-2026-10-12-gcp-vm\.md'

# cloud_scan DIR: fail with the lines under DIR that name a cloud provider (whole word, any case), comments included.
# It scans a copy of DIR without the allowed runbook path, so the lines it prints name files under
# $BATS_TEST_TMPDIR/scan/<the last part of DIR>.
cloud_scan() {
  local copy="$BATS_TEST_TMPDIR/scan/${1##*/}" files file
  rm -rf "$copy" && mkdir -p "$copy" && cp -R "$1/." "$copy" || return 1
  if ! files="$(find "$copy" -type f)"; then
    fail "find could not list the files copied from $1"
    return 1
  fi
  if [[ -z "$files" ]]; then
    fail "found no files under $1"
    return 1
  fi
  while IFS= read -r file; do
    sed "s#$ALLOWED_RUNBOOK##g" "$file" >"$file.tmp" && mv "$file.tmp" "$file" || return 1
  done <<<"$files"
  refute_matches "$copy" "$CLOUD_NAMES" -i -w
}

@test "the scan flags a provider name, and scripts and skills name none in their contents, comments included, or in their file names" {
  local sample="$BATS_TEST_TMPDIR/sample" names="$BATS_TEST_TMPDIR/names" dir
  mkdir -p "$sample"
  printf '# see docs/runbooks/rbk-2026-10-12-gcp-vm.md\n# use the OCI console\n# gcloud compute list\n' >"$sample/a.sh"
  # The first case checks the scan itself: it flags both names and skips only the runbook path.
  run cloud_scan "$sample"
  assert_failure
  assert_output --partial "use the OCI console"
  assert_output --partial "gcloud compute list"
  refute_output --partial "runbooks"
  for dir in scripts .agents/skills; do
    cloud_scan "$REPO_DIR/$dir" || fail "cloud provider names in $dir/ (point to the runbook section instead)"
  done
  # The file names (tracked and new) go through the same scan as the lines of one file.
  mkdir -p "$names"
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- scripts .agents/skills >"$names/paths" \
    || fail "git ls-files failed on scripts and .agents/skills"
  [[ -s "$names/paths" ]] || fail "git listed no file under scripts and .agents/skills"
  cloud_scan "$names" || fail "cloud provider names in file names under scripts/ or .agents/skills/ (git mv the file)"
}
