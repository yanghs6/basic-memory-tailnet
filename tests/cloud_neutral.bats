#!/usr/bin/env bats
load helpers

CLOUD_NAMES='oci|oracle|gcp|gcloud'
# The runbook's file name is the one allowed mention: scripts point to it instead of naming a provider.
ALLOWED_RUNBOOK='docs/runbooks/gcp-vm\.md'

# cloud_name_matches DIR -> grep -rn lines under DIR that name a cloud provider (whole word, any case),
# after removing the allowed runbook path. Prints nothing when DIR is clean.
cloud_name_matches() {
  local matches rc=0
  matches="$(grep -rniwE "$CLOUD_NAMES" "$1")" || rc=$?
  ((rc <= 1)) || return "$rc"
  sed "s#${ALLOWED_RUNBOOK}##g" <<<"$matches" | grep -iwE "$CLOUD_NAMES" || true
}

@test "the scan flags a provider name and ignores only the runbook path" {
  mkdir -p "$BATS_TEST_TMPDIR/sample"
  printf '# see docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md\n# use the OCI console\n# gcloud compute list\n' >"$BATS_TEST_TMPDIR/sample/a.sh"
  run cloud_name_matches "$BATS_TEST_TMPDIR/sample"
  assert_success
  assert_output --partial "use the OCI console"
  assert_output --partial "gcloud compute list"
  refute_output --partial "runbooks"
}

@test "the scan passes a clean directory" {
  mkdir -p "$BATS_TEST_TMPDIR/clean"
  printf '# a firewall rule that opens port 22\n' >"$BATS_TEST_TMPDIR/clean/a.sh"
  run cloud_name_matches "$BATS_TEST_TMPDIR/clean"
  assert_success
  assert_output ""
}

@test "scripts name no cloud provider, comments included" {
  local leftover
  leftover="$(cloud_name_matches "$REPO_DIR/scripts")" || fail "the scan itself failed"
  [[ -z "$leftover" ]] || fail "cloud provider names in scripts/:"$'\n'"$leftover"
}
