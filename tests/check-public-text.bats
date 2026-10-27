#!/usr/bin/env bats
load helpers

FIXTURES="$REPO_DIR/tests/fixtures/check-public-text"

setup() {
  SCRIPT="$REPO_DIR/scripts/check-public-text.sh"
}

# to_crlf FILE OUT: FILE with CRLF line ends, as GitHub sends a PR body.
to_crlf() {
  awk '{ printf "%s\r\n", $0 }' "$1" >"$2"
}

@test "flags every kind and prints no matched value" {
  local case name line kind value crlf cgnat near_host
  for case in \
    "ipv4|2|IPv4 address" \
    "ipv4|3|IPv4 address" \
    "tailnet-ipv6|2|tailnet IPv6 address" \
    "tailnet-ipv6|3|tailnet IPv6 address" \
    "ts-net|2|ts.net host name" \
    "ts-net|3|ts.net host name" \
    "session-link|2|session link" \
    "session-link|3|session link" \
    "session-link|4|session link" \
    "session-link|5|session link" \
    "generated-with|2|Generated with line" \
    "generated-with|3|Generated with line" \
    "generated-with|4|Generated with line" \
    "generated-with|5|Generated with line"; do
    (
      IFS='|' read -r name line kind <<<"$case" \
        && crlf="$BATS_TEST_TMPDIR/$name-crlf.txt" \
        && to_crlf "$FIXTURES/$name.txt" "$crlf" \
        && value="$(sed -n "${line}p" "$FIXTURES/$name.txt" | sed 's/^ *//')" \
        && run "$SCRIPT" "$FIXTURES/$name.txt" "$crlf" \
        && assert_failure \
        && assert_output --partial "$FIXTURES/$name.txt:$line: $kind" \
        && assert_output --partial "$crlf:$line: $kind" \
        && refute_output --partial "$value" || exit 1
    ) || fail "$case"
  done
  # A single CGNAT (tailnet range) address never sits in a repo file, so build it here; /32 is still one address,
  # a /30 network is too narrow to count as a range, and a non-address before a hit on the same line hides nothing.
  cgnat="$(printf '%s.%s' 100.101 102.103)"
  near_host="$(printf '%s.%s/30' 198.18 0.4)"
  run "$SCRIPT" --label commit-0fake00 - <<<"subject"$'\n'"reach $cgnat"$'\n'"route $cgnat/32"$'\n'"net $near_host"$'\n'"256.1.1.1 $cgnat"
  assert_failure
  assert_output --partial "commit-0fake00:2: IPv4 address"
  assert_output --partial "commit-0fake00:3: IPv4 address"
  assert_output --partial "commit-0fake00:4: IPv4 address"
  assert_output --partial "commit-0fake00:5: IPv4 address"
  refute_output --partial "$cgnat"
  refute_output --partial "$near_host"
}

@test "passes the allowed forms" {
  local crlf="$BATS_TEST_TMPDIR/pass-crlf.txt"
  to_crlf "$FIXTURES/pass.txt" "$crlf"
  run "$SCRIPT" "$FIXTURES/pass.txt" "$crlf"
  assert_success
  assert_output ""
}

@test "applies the exemption list only without arguments" {
  init_git_repo
  mkdir skills
  ln -s skills skill-link
  cp "$FIXTURES/ipv4.txt" notes.txt
  printf '# fixtures\n\nnotes.txt ipv4\n' >.public-text-exemptions
  git add notes.txt skill-link .public-text-exemptions
  git commit -q -m "test: add notes"
  cp "$FIXTURES/ipv4.txt" ignored.txt
  printf 'ignored.txt\n' >.gitignore
  {
    printf 'bin\0\n'
    cat "$FIXTURES/ipv4.txt"
  } >blob.bin

  run "$SCRIPT"
  assert_success

  run "$SCRIPT" notes.txt
  assert_failure
  assert_output --partial "notes.txt:2: IPv4 address"

  run "$SCRIPT" - <notes.txt
  assert_failure
  assert_output --partial ":2: IPv4 address"

  # The exemption covers its kind in its file only: a new kind there and a new file still fail.
  cat "$FIXTURES/ts-net.txt" >>notes.txt
  cp "$FIXTURES/ipv4.txt" new.txt
  run "$SCRIPT"
  assert_failure
  assert_output --partial "notes.txt:5: ts.net host name"
  assert_output --partial "new.txt:2: IPv4 address"
  refute_output --partial "notes.txt:2:"
  refute_output --partial "ignored.txt"
  refute_output --partial "blob.bin"

  # A malformed exemption line stops the scan instead of exempting nothing or everything.
  printf '# fixtures\n\nnotes.txt\n' >.public-text-exemptions
  run "$SCRIPT"
  assert_failure
  assert_output --partial "line 3 of .public-text-exemptions"
  refute_output --partial "$(sed -n 2p "$FIXTURES/ipv4.txt")"
}

@test "fails on an unreadable file instead of passing it" {
  [ "$(id -u)" -eq 0 ] && skip "root reads files of mode 000"
  init_git_repo
  cp "$FIXTURES/ipv4.txt" locked.txt
  chmod 000 locked.txt

  run "$SCRIPT" locked.txt
  assert_failure
  assert_output --partial "locked.txt"

  run "$SCRIPT"
  assert_failure
  assert_output --partial "locked.txt: unreadable"
}
