#!/usr/bin/env bash
# Download the VM container logs of every running service as one JSON Lines file in the main checkout's log-exports/:
# one {time, service, stream, msg, data?} object per line in time order, data being msg when msg is a JSON object.
# Prints only counts and the file path, never a log line: the lines can hold note titles and client addresses.
# Usage: make export-logs [SINCE=24h]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vm.sh
. "$SCRIPT_DIR/lib/vm.sh"

readonly LOG_EXPORTS_DIRNAME="log-exports"
readonly DEFAULT_LOG_SINCE="24h"
# docker logs --since also takes dates; only a whole number of seconds, minutes or hours goes into the remote command.
readonly LOG_SINCE_PATTERN='^[0-9]+[smh]$'
# Owner-only files: the umask applies to every file this script creates.
readonly EXPORT_UMASK=077
# One line of docker logs --timestamps to one record; ANSI colour codes are dropped from the message. docker starts every
# line with its RFC 3339 time, so a line without one is ssh's own (an IAP or host key notice) and gives no record.
# shellcheck disable=SC2016  # $service and $stream are jq variables
readonly TO_RECORD='capture("^(?<time>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z) ?(?<msg>.*)$")
  | {time, service: $service, stream: $stream, msg: (.msg | gsub("\u001b\\[[0-9;]*[A-Za-z]"; ""))}
  | (.msg | try fromjson catch null) as $data
  | if ($data | type) == "object" then . + {data: $data} else . end'

WORK_DIR=""
PARTIAL_FILE=""
# Lines that gave no record (ssh's own messages), over every service and stream.
SKIPPED_COUNT=0

cleanup() {
  [[ -z "$PARTIAL_FILE" ]] || rm -f "$PARTIAL_FILE"
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# resolve_export_dir -> absolute export directory (created). LOG_EXPORT_DIR from the environment wins; otherwise
# log-exports/ in the MAIN checkout, next to backups/, so a file exported from a worktree survives its removal.
resolve_export_dir() {
  local dir="${LOG_EXPORT_DIR:-}" root
  if [[ -z "$dir" ]]; then
    root="$(main_checkout_root)" \
      || die "cannot find the main checkout (is this a git checkout?): set LOG_EXPORT_DIR=<dir> and run 'make export-logs' again"
    dir="$root/$LOG_EXPORTS_DIRNAME"
  fi
  mkdir -p "$dir" || die "could not create the log export directory $dir"
  (cd "$dir" && pwd)
}

# fetch_service SERVICE SINCE -> the service's stdout and stderr lines since SINCE as records in $WORK_DIR/SERVICE.jsonl;
# adds the lines that gave no record to SKIPPED_COUNT
fetch_service() {
  local service="$1" since="$2" stream lines records
  remote "cd $BM_REMOTE_APP_DIR && docker logs --timestamps --since $since \$(docker compose ps -q $service)" \
    >"$WORK_DIR/$service.stdout" 2>"$WORK_DIR/$service.stderr" \
    || die "could not read the $service logs from $BM_VM_HOST: $(access_hint)"
  for stream in stdout stderr; do
    jq -Rc --arg service "$service" --arg stream "$stream" "$TO_RECORD" "$WORK_DIR/$service.$stream" \
      >"$WORK_DIR/$service.$stream.jsonl" || die "could not convert the $service $stream lines to JSON"
    lines="$(wc -l <"$WORK_DIR/$service.$stream")"
    records="$(wc -l <"$WORK_DIR/$service.$stream.jsonl")"
    SKIPPED_COUNT=$((SKIPPED_COUNT + lines - records))
  done
}

main() {
  local since="${1:-$DEFAULT_LOG_SINCE}" dir services service file count
  [[ "$since" =~ $LOG_SINCE_PATTERN ]] || die "SINCE must be a whole number of seconds, minutes or hours, such as 24h or 90m"
  require_vm jq
  umask "$EXPORT_UMASK"
  dir="$(resolve_export_dir)" || exit 1
  WORK_DIR="$(mktemp -d)" || die "could not create a temporary directory"
  trap cleanup EXIT
  services="$(remote_compose "ps --services --status running")" \
    || die "could not list the running services on $BM_VM_HOST: $(access_hint)"
  [[ -n "$services" ]] || die "no service runs on $BM_VM_HOST: check 'make status'"
  for service in $services; do
    step "reading the $service logs since $since"
    fetch_service "$service" "$since"
  done
  file="$dir/logs-$(utc_stamp).jsonl"
  PARTIAL_FILE="$file$PARTIAL_SUFFIX"
  # Records of one time keep their service and stream order: sort_by is stable.
  cat "$WORK_DIR"/*.jsonl | jq -sc 'sort_by(.time) | .[]' >"$PARTIAL_FILE" || die "could not sort the log records"
  mv "$PARTIAL_FILE" "$file" || die "could not move the export into place at $file"
  PARTIAL_FILE=""
  count="$(wc -l <"$file" | tr -d ' ')"
  log "wrote $count lines from $(printf '%s\n' "$services" | wc -l | tr -d ' ') services to $file" \
    "(skipped $SKIPPED_COUNT lines without a docker timestamp: ssh's own messages)"
}

main "$@"
