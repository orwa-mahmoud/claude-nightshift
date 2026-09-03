#!/usr/bin/env bash
# stop-shift.sh — issue a stop-work order. Hardhat stays until clock-out writes ENDED.
#
#   stop-shift.sh --project DIR [--reason TEXT]
#
# --project is required. Does not use the current working directory.
#
# Exit: 0 stopped · 1 usage/resolve · 2 watchman pid unverified (shift still disarmed)
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"
# shellcheck source=plugins/nightshift/lib/control.sh
. "$_here/../lib/control.sh"

PROJECT=""
REASON="stopped by owner"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'stop-shift: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    --reason)
      [ $# -ge 2 ] || { printf 'stop-shift: --reason needs a value\n' >&2; exit 1; }
      REASON="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'stop-shift: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] || { printf 'stop-shift: --project is required\n' >&2; exit 1; }

ns_control_stop "$PROJECT" "$REASON"
exit "$?"
