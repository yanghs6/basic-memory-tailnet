#!/usr/bin/env bash
# {{Topic}} helpers for scripts/*.sh: {{what the scripts that source it share}}. Sources common.sh.
# Must stay compatible with macOS bash 3.2.
#   {{function ARGS -> what it prints, returns or dies on; one line per function, in file order}}

[ -n "${_BM_LIB_NAME:-}" ] && return 0
readonly _BM_LIB_NAME=1

# shellcheck source=common.sh
. "${BASH_SOURCE[0]%/*}/common.sh"
