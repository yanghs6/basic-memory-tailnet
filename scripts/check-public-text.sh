#!/usr/bin/env bash
# Check text that leaves the repo (files, commit messages, PR text, review reports) for IPv4 addresses outside the allowed
# ranges, tailnet IPv6 addresses, ts.net host names, Claude Code session links and Generated with lines. Prints only the
# place and kind of each hit, never the value, and exits 1 on a hit. Without arguments it scans the tracked and new text
# files of the current repository and applies the exemption list at its root; named files and stdin get no exemption.
# Usage: scripts/check-public-text.sh [--label NAME] [FILE|-]...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# IPv4 ranges that are no VM address: loopback, unspecified, the documentation ranges (RFC 5737), the IAP TCP
# forwarding range of the ssh access mode (docs/specs/spec-2026-10-15-jr59pvyf-access-modes.md), private (RFC 1918) and link-local.
readonly ALLOWED_IPV4_RANGES="127.0.0.0/8 0.0.0.0/32 192.0.2.0/24 198.51.100.0/24 203.0.113.0/24 35.235.240.0/20 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16"
# The longest prefix a network address in CIDR notation may have to pass as a range; longer ones are near-host
# addresses and are checked as addresses (the repo's documents use /24 at most).
readonly MAX_NETWORK_PREFIX=24
# A ts.net name holding one of these marks, with one of these labels, or with a label starting with the prefix is a
# placeholder.
readonly PLACEHOLDER_TS_MARKS="< * {"
readonly PLACEHOLDER_TS_LABELS="example tail1234 tailnet"
readonly PLACEHOLDER_TS_LABEL_PREFIX="example-"
# Exemption list at the repo root: lines '<repo-relative path> <kind id>', used only without arguments.
readonly EXEMPTIONS_FILE=".public-text-exemptions"
# Kind ids (exemption list) and the kind names printed for them, in the same order.
readonly KIND_IDS="ipv4 tailnet-ipv6 ts-net session-link generated-with"
readonly KIND_NAMES="IPv4 address|tailnet IPv6 address|ts.net host name|session link|Generated with line"
readonly STDIN_LABEL="stdin"
# Exit status of the scan: hits found, a bad exemption line, or a file it could not read (awk itself exits 2 on its
# own errors).
readonly STATUS_HITS=1
readonly STATUS_BAD_EXEMPTION=3
readonly STATUS_UNREADABLE=4
# xargs exits 123 when the command it runs exits 1 to 125 (for grep: no file listed, or an error).
readonly XARGS_COMMAND_FAILED=123
readonly MASK_HINT="replace the host with agent-hub, a tailnet IP with <agent-hub tailnet IP>, other addresses with a documentation-range address (203.0.113.10), and delete session links and Generated with lines; then run it again"

# The scan reads LIST (lines '<path><TAB><label>') and prints '<label>:<line>: <kind>' once per line and kind. EXEMPTIONS
# is the exemption list or empty; the path in LIST is what it matches.
# shellcheck disable=SC2016  # the awk program is single-quoted on purpose
readonly SCAN_PROGRAM='
function octets(text, o,   i) {
  split(text, o, ".")
  for (i = 1; i <= 4; i++) {
    if (length(o[i]) > 3 || o[i] + 0 > 255) return 0
    o[i] = o[i] + 0
  }
  return 1
}
function number(o) { return ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4] }
function is_allowed(ip,   i, size) {
  for (i = 1; i <= range_count; i++) {
    size = 2 ^ (32 - range_bits[i])
    if (int(ip / size) == int(range_net[i] / size)) return 1
  }
  return 0
}
# A network address in CIDR notation (host bits zero) with a prefix up to max_prefix is a range, not a host; a longer
# prefix (up to /32, one host) is checked as an address.
function is_network(line, stop, ip,   bits) {
  if (substr(line, stop, 1) != "/" || !match(substr(line, stop + 1), /^[0-9]+/)) return 0
  bits = substr(line, stop + 1, RLENGTH) + 0
  return RLENGTH <= 2 && bits <= max_prefix && ip % (2 ^ (32 - bits)) == 0
}
function has_ipv4(line,   offset, start, stop, text, o, ip) {
  offset = 0
  while (match(substr(line, offset + 1), /[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+/)) {
    start = offset + RSTART
    stop = start + RLENGTH
    text = substr(line, start, RLENGTH)
    offset = stop - 1
    if (substr(line, start - 1, 1) == "." && substr(line, start - 2, 1) ~ /[0-9]/) continue
    if (substr(line, stop, 1) == "." && substr(line, stop + 1, 1) ~ /[0-9]/) continue
    if (!octets(text, o)) continue
    ip = number(o)
    if (is_network(line, stop, ip) || is_allowed(ip)) continue
    return 1
  }
  return 0
}
function has_tailnet_ipv6(line,   rest) {
  rest = tolower(line)
  while (match(rest, /fd7a[:]115c[:]a1e0[:]/)) {
    rest = substr(rest, RSTART + RLENGTH)
    if (rest ~ /^[:]?[0-9a-f]/) return 1
  }
  return 0
}
function is_placeholder(name,   i, labels, n) {
  for (i = 1; i <= mark_count; i++) if (index(name, marks[i])) return 1
  n = split(name, labels, ".")
  for (i = 1; i <= n; i++) {
    if (labels[i] in placeholder_labels) return 1
    if (index(labels[i], placeholder_label_prefix) == 1) return 1
  }
  return 0
}
function has_ts_net(line,   rest, name, after) {
  rest = tolower(line)
  while (match(rest, /[a-z0-9_*<>{}-]+([.][a-z0-9_*<>{}-]+)*[.]ts[.]net/)) {
    name = substr(rest, RSTART, RLENGTH)
    after = substr(rest, RSTART + RLENGTH, 1)
    rest = substr(rest, RSTART + RLENGTH)
    if (after !~ /[a-z0-9_-]/ && !is_placeholder(name)) return 1
  }
  return 0
}
function has_session_link(line) {
  line = tolower(line)
  return line ~ /claude[.]ai\/code\/session_[a-z0-9]/ || line ~ /^[+-]?[ \t]*claude-session[:]/
}
# Only a diff mark (git log -p), whitespace, list and quote marks and non-ASCII symbols (emoji) may come before it.
function has_generated_with(line) { return line ~ /^[+-]?([ \t>*-]|[0-9]+[.]|[^ -~])*Generated with/ }
function report(path, label, line_no, id) {
  if ((path, id) in exempt) return
  print label ":" line_no ": " kind_name[id]
  hits = 1
}
BEGIN {
  range_count = split(ranges, range_list, " ")
  for (i = 1; i <= range_count; i++) {
    split(range_list[i], parts, "/")
    octets(parts[1], o)
    range_net[i] = number(o)
    range_bits[i] = parts[2] + 0
  }
  mark_count = split(placeholder_marks, marks, " ")
  n = split(placeholder_label_list, label_list, " ")
  for (i = 1; i <= n; i++) placeholder_labels[label_list[i]] = 1
  n = split(kind_ids, ids, " ")
  split(kind_names, names, "|")
  for (i = 1; i <= n; i++) kind_name[ids[i]] = names[i]
  if (exemptions != "") {
    number_in_list = 0
    while ((got = (getline entry < exemptions)) > 0) {
      number_in_list++
      sub(/\r$/, "", entry)
      if (entry ~ /^[ \t]*(#|$)/) continue
      if (split(entry, fields, " ") != 2 || !(fields[2] in kind_name)) {
        print number_in_list
        exit bad_exemption
      }
      exempt[fields[1], fields[2]] = 1
    }
    if (got < 0) {
      print exemptions ": unreadable"
      exit status_unreadable
    }
    close(exemptions)
  }
  while ((getline entry < list) > 0) {
    split(entry, fields, "\t")
    line_number = 0
    while ((got = (getline line < fields[1])) > 0) {
      line_number++
      sub(/\r$/, "", line)
      if (has_ipv4(line)) report(fields[1], fields[2], line_number, "ipv4")
      if (has_tailnet_ipv6(line)) report(fields[1], fields[2], line_number, "tailnet-ipv6")
      if (has_ts_net(line)) report(fields[1], fields[2], line_number, "ts-net")
      if (has_session_link(line)) report(fields[1], fields[2], line_number, "session-link")
      if (has_generated_with(line)) report(fields[1], fields[2], line_number, "generated-with")
    }
    # getline returns -1, not 0, on a file it cannot read: fail instead of passing it unread.
    if (got < 0) {
      print fields[2] ": unreadable"
      unreadable = 1
    }
    close(fields[1])
  }
  if (unreadable) exit status_unreadable
  exit hits ? status_hits : 0
}'

# repo_text_files LIST -> writes the tracked and new (not ignored) regular text files of the repo at the current
# directory to LIST as scan lines ('<path><TAB><path>'). Symlinks (also the .claude/skills directory links), deleted
# files and binary files are left out; dies on a file it cannot read.
repo_text_files() {
  local list="$1" path regular errors status=0 unreadable=0
  regular="$(mktemp)" || exit 1
  errors="$(mktemp)" || exit 1
  while IFS= read -r -d '' path; do
    if [[ -f "$path" && ! -L "$path" ]]; then
      if [[ -r "$path" ]]; then
        printf '%s\0' "$path"
      else
        printf '%s: unreadable\n' "$path" >&2
        unreadable=1
      fi
    fi
  done < <(git ls-files -z -co --exclude-standard) >"$regular"
  # grep -I leaves out binary files; /dev/null keeps grep off stdin when no file is left. xargs turns any grep exit
  # from 1 to 125 into 123, so "no file listed" and a read error differ only in what grep wrote to stderr.
  LC_ALL=C xargs -0 grep -Il -e '' /dev/null <"$regular" 2>"$errors" | awk '{ printf "%s\t%s\n", $0, $0 }' >"$list" \
    || status=$?
  cat "$errors" >&2
  if [[ -s "$errors" ]] || ((status != 0 && status != XARGS_COMMAND_FAILED)); then
    unreadable=1
  fi
  rm -f "$regular" "$errors"
  ((unreadable == 0)) || die "some repo files cannot be read (listed above): fix their permissions and run it again"
}

main() {
  local label="" list exemptions="" input arg status=0 hits top
  require_cmd awk git
  if [[ "${1:-}" == --label ]]; then
    [[ -n "${2:-}" ]] || die "--label needs a name: --label NAME [FILE|-]..."
    label="$2"
    shift 2
  fi
  list="$(mktemp)" || exit 1
  input="$(mktemp)" || exit 1
  # shellcheck disable=SC2064  # expand now: the locals are gone when the EXIT trap runs
  trap "rm -f '$list' '$input'" EXIT
  if (($# == 0)); then
    top="$(git rev-parse --show-toplevel 2>/dev/null)" \
      || die "not inside a git repository: run it in the repo, or name the files to check (- for stdin)"
    cd "$top"
    [[ -f "$EXEMPTIONS_FILE" ]] && exemptions="$EXEMPTIONS_FILE"
    repo_text_files "$list"
  fi
  for arg in "$@"; do
    if [[ "$arg" == - ]]; then
      cat >"$input"
      printf '%s\t%s\n' "$input" "${label:-$STDIN_LABEL}" >>"$list"
    else
      [[ -f "$arg" ]] || die "no such file: $arg"
      [[ -r "$arg" ]] || die "cannot read $arg: fix its permissions and run it again"
      printf '%s\t%s\n' "$arg" "${label:-$arg}" >>"$list"
    fi
  done
  hits="$(LC_ALL=C awk -v list="$list" -v exemptions="$exemptions" -v ranges="$ALLOWED_IPV4_RANGES" \
    -v max_prefix="$MAX_NETWORK_PREFIX" -v placeholder_marks="$PLACEHOLDER_TS_MARKS" \
    -v placeholder_label_list="$PLACEHOLDER_TS_LABELS" -v placeholder_label_prefix="$PLACEHOLDER_TS_LABEL_PREFIX" \
    -v kind_ids="$KIND_IDS" -v kind_names="$KIND_NAMES" -v status_hits="$STATUS_HITS" \
    -v bad_exemption="$STATUS_BAD_EXEMPTION" -v status_unreadable="$STATUS_UNREADABLE" "$SCAN_PROGRAM" </dev/null)" \
    || status=$?
  if ((status == STATUS_BAD_EXEMPTION)); then
    die "line $hits of $EXEMPTIONS_FILE must be '<repo-relative path> <kind id>' with a kind id out of: $KIND_IDS"
  fi
  if ((status == STATUS_UNREADABLE)); then
    printf '%s\n' "$hits" >&2
    die "some files cannot be read (marked unreadable above): fix their permissions and run it again"
  fi
  if ((status == STATUS_HITS)); then
    printf '%s\n' "$hits" >&2
    printf 'hint: %s\n' "$MASK_HINT" >&2
    exit 1
  fi
  ((status == 0)) || die "the public text scan failed (awk exit $status)"
}

main "$@"
