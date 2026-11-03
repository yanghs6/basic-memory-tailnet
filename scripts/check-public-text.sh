#!/usr/bin/env bash
# Check text that leaves the repo (files, commit messages, PR text, review reports) for IPv4 addresses outside the allowed
# ranges, tailnet IPv6 addresses, ts.net host names, local home and temp folder paths, Claude Code session links and
# Generated with lines. Prints only the place and kind of each hit, never the value, and exits 1 on a hit. Without arguments it scans the tracked and new text
# files of the current repository and applies the exemption list at its root; it fails when git cannot list the files
# or none is left to scan. Named files and stdin get no exemption. With --diff it reads git log -p output on stdin
# (scripts/check-git.sh), checks only the added lines, prints '<sha> <path>:<line in the new file>: <kind>' and applies
# the exemption list FILE by the path of each line.
# Usage: scripts/check-public-text.sh [--label NAME] [FILE|-]...
#        git log -p --unified=0 --format='commit %h' ... | scripts/check-public-text.sh --diff [--exemptions FILE] -
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
# Folder names under /home/ that are no local account: the Basic Memory container user (compose.yaml).
readonly CONTAINER_HOME_USERS="appuser"
# Exemption list at the repo root: lines '<repo-relative path> <kind id>', used only without arguments.
readonly EXEMPTIONS_FILE=".public-text-exemptions"
# Kind ids (exemption list) and the kind names printed for them, in the same order.
readonly KIND_IDS="ipv4 tailnet-ipv6 ts-net session-link generated-with local-path"
readonly KIND_NAMES="IPv4 address|tailnet IPv6 address|ts.net host name|session link|Generated with line|local path"
readonly STDIN_LABEL="stdin"
# Exit status of the scan: hits found, a bad exemption line, or a file it could not read (awk itself exits 2 on its
# own errors).
readonly STATUS_HITS=1
readonly STATUS_BAD_EXEMPTION=3
readonly STATUS_UNREADABLE=4
# xargs exits 123 when the command it runs exits 1 to 125 (for grep: no file listed, or an error).
readonly XARGS_COMMAND_FAILED=123
readonly MASK_HINT="replace the host with agent-hub, a tailnet IP with <agent-hub tailnet IP>, other addresses with a documentation-range address (203.0.113.10), write repo-relative paths instead of home and temp folder paths, and delete session links and Generated with lines; then run it again"

# The scan reads LIST (lines '<path><TAB><label>'), or with DIFF set that git log -p output, and prints
# '<label>:<line>: <kind>' once per line and kind. EXEMPTIONS is the exemption list or empty; the path in LIST, or
# the path of the diff's file, is what it matches.
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
# A home folder with a real name (/Users/<name>/, or /home/<name>/ unless it is a container user) or a macOS temp
# folder (/var/folders/<dir>/, also under /private). Placeholders such as /Users/<you>/ and a bare /var/folders/ pass.
function has_local_path(line,   rest, parts) {
  rest = line
  while (match(rest, /\/(Users|home)\/[A-Za-z0-9._-]+\//)) {
    split(substr(rest, RSTART + 1, RLENGTH - 2), parts, "/")
    rest = substr(rest, RSTART + RLENGTH - 1)
    if (!(parts[1] == "home" && (parts[2] in container_users))) return 1
  }
  return line ~ /\/var\/folders\/[A-Za-z0-9_+-]+\//
}
function report(path, label, line_no, id) {
  if ((path, id) in exempt) return
  print label ":" line_no ": " kind_name[id]
  hits = 1
}
function check_line(path, label, line_no, line) {
  if (has_ipv4(line)) report(path, label, line_no, "ipv4")
  if (has_tailnet_ipv6(line)) report(path, label, line_no, "tailnet-ipv6")
  if (has_ts_net(line)) report(path, label, line_no, "ts-net")
  if (has_session_link(line)) report(path, label, line_no, "session-link")
  if (has_generated_with(line)) report(path, label, line_no, "generated-with")
  if (has_local_path(line)) report(path, label, line_no, "local-path")
}
# scan_files: every line of each file in LIST.
function scan_files(   entry, fields, line_number, got, line) {
  while ((getline entry < list) > 0) {
    split(entry, fields, "\t")
    line_number = 0
    while ((got = (getline line < fields[1])) > 0) {
      line_number++
      sub(/\r$/, "", line)
      check_line(fields[1], fields[2], line_number, line)
    }
    # getline returns -1, not 0, on a file it cannot read: fail instead of passing it unread.
    if (got < 0) {
      print fields[2] ": unreadable"
      unreadable = 1
    }
    close(fields[1])
  }
}
# hunk_count RANGE -> the line count of a hunk range (-a,b or +c,d); git leaves out a count of 1.
function hunk_count(range) { return index(range, ",") ? substr(range, index(range, ",") + 1) + 0 : 1 }
# scan_diff: the added lines of the git log -p output in DIFF, by the path of their file and their line number in the
# new file. A hunk header (@@ -a,b +c,d @@) counts the removed and added lines after it, and only outside a hunk is a
# line a header: inside one an added line whose text starts with "++ " reads "+++ ". +++ /dev/null (a deleted file)
# names no path; a quoted path keeps its quotes, so no exemption matches it.
function scan_diff(   line, got, mark, sha, path, old_left, new_left, new_line, ranges) {
  while ((got = (getline line < diff)) > 0) {
    sub(/\r$/, "", line)
    mark = substr(line, 1, 1)
    if (mark == "\\") continue
    if (old_left > 0 && mark == "-") {
      old_left--
    } else if (new_left > 0 && mark == "+") {
      new_left--
      new_line++
      if (path != "") check_line(path, sha " " path, new_line, substr(line, 2))
    } else if (old_left > 0 && new_left > 0 && mark == " ") {
      old_left--
      new_left--
      new_line++
    } else {
      old_left = new_left = 0
      if (line ~ /^commit /) {
        sha = substr(line, 8)
        path = ""
      } else if (line ~ /^diff --git /) {
        path = ""
      } else if (line ~ /^[+][+][+] /) {
        path = substr(line, 5)
        sub(/\t$/, "", path)
        if (path == "/dev/null") path = ""
        else if (substr(path, 1, 2) == "b/") path = substr(path, 3)
      } else if (line ~ /^@@ -[0-9]+(,[0-9]+)? [+][0-9]+(,[0-9]+)? @@/) {
        split(line, ranges, " ")
        old_left = hunk_count(ranges[2])
        new_left = hunk_count(ranges[3])
        new_line = substr(ranges[3], 2) - 1
      }
    }
  }
  if (got < 0) {
    print "stdin: unreadable"
    unreadable = 1
  }
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
  n = split(container_user_list, user_list, " ")
  for (i = 1; i <= n; i++) container_users[user_list[i]] = 1
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
  if (diff != "") scan_diff()
  else scan_files()
  if (unreadable) exit status_unreadable
  exit hits ? status_hits : 0
}'

# repo_text_files LIST -> writes the tracked and new (not ignored) regular text files of the repo at the current
# directory to LIST as scan lines ('<path><TAB><path>'). Symlinks (also the .claude/skills directory links), deleted
# files and binary files are left out; dies when git cannot list the files, on a file it cannot read, and when no text
# file is left, so a scan of nothing never passes.
repo_text_files() {
  local list="$1" files path regular errors status=0 unreadable=0
  files="$(new_temp check-public-text)" || exit 1
  regular="$(new_temp check-public-text)" || exit 1
  errors="$(new_temp check-public-text)" || exit 1
  # A file, not a process substitution: that loses git's exit status and leaves an empty list.
  git ls-files -z -co --exclude-standard >"$files" || {
    rm -f "$files" "$regular" "$errors"
    die "git cannot list the repo files (its error is above): repair the repository until git status works, then run it again"
  }
  while IFS= read -r -d '' path; do
    if [[ -f "$path" && ! -L "$path" ]]; then
      if [[ -r "$path" ]]; then
        printf '%s\0' "$path"
      else
        printf '%s: unreadable\n' "$path" >&2
        unreadable=1
      fi
    fi
  done <"$files" >"$regular"
  # grep -I leaves out binary files; /dev/null keeps grep off stdin when no file is left. xargs turns any grep exit
  # from 1 to 125 into 123, so "no file listed" and a read error differ only in what grep wrote to stderr.
  LC_ALL=C xargs -0 grep -Il -e '' /dev/null <"$regular" 2>"$errors" | awk '{ printf "%s\t%s\n", $0, $0 }' >"$list" \
    || status=$?
  cat "$errors" >&2
  if [[ -s "$errors" ]] || ((status != 0 && status != XARGS_COMMAND_FAILED)); then
    unreadable=1
  fi
  rm -f "$files" "$regular" "$errors"
  ((unreadable == 0)) || die "some repo files cannot be read (listed above): fix their permissions and run it again"
  [[ -s "$list" ]] \
    || die "no text files to check in this repository: run it in the repo, or name the files to check (- for stdin)"
}

# scan LIST DIFF EXEMPTIONS: run the scan program on the files in LIST, or with DIFF set on that git log -p output, and
# report its result: exit 1 with the hits and the hint on stderr, die on a bad exemption line or an unreadable file.
scan() {
  local hits status=0
  hits="$(LC_ALL=C awk -v list="$1" -v diff="$2" -v exemptions="$3" -v ranges="$ALLOWED_IPV4_RANGES" \
    -v max_prefix="$MAX_NETWORK_PREFIX" -v placeholder_marks="$PLACEHOLDER_TS_MARKS" \
    -v placeholder_label_list="$PLACEHOLDER_TS_LABELS" -v placeholder_label_prefix="$PLACEHOLDER_TS_LABEL_PREFIX" \
    -v container_user_list="$CONTAINER_HOME_USERS" \
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

# scan_diff_input [--exemptions FILE] -: the --diff mode; stdin goes to INPUT first.
scan_diff_input() {
  local input="$1" exemptions=""
  shift
  if [[ "${1:-}" == --exemptions ]]; then
    [[ -f "${2:-}" ]] || die "--exemptions needs an exemption list file: --diff [--exemptions FILE] -"
    exemptions="$2"
    shift 2
  fi
  [[ $# -eq 1 && "$1" == - ]] || die "--diff reads git log -p output on stdin only: --diff [--exemptions FILE] -"
  cat >"$input"
  scan "" "$input" "$exemptions"
}

main() {
  local label="" list exemptions="" input arg top
  require_cmd awk git
  list="$(new_temp check-public-text)" || exit 1
  input="$(new_temp check-public-text)" || exit 1
  # shellcheck disable=SC2064  # expand now: the locals are gone when the EXIT trap runs
  trap "rm -f '$list' '$input'" EXIT
  if [[ "${1:-}" == --diff ]]; then
    shift
    scan_diff_input "$input" "$@"
    return 0
  fi
  if [[ "${1:-}" == --label ]]; then
    [[ -n "${2:-}" ]] || die "--label needs a name: --label NAME [FILE|-]..."
    label="$2"
    shift 2
  fi
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
  scan "$list" "" "$exemptions"
}

main "$@"
