#!/usr/bin/env bash
# reset-shift.sh — abandon current runtime mechanics. Preserves punch list, rules, and history.
#
#   reset-shift.sh --project DIR
#
# Performs Stop, then removes the deadline and leftover STOP/reason markers.
# --project is required. Does not use the current working directory.
#
# Exit: 0 reset · 1 usage/resolve · 2 watchman pid unverified (runtime still reset)
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"
# shellcheck source=plugins/nightshift/lib/control.sh
. "$_here/../lib/control.sh"

PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'reset-shift: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'reset-shift: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] || { printf 'reset-shift: --project is required\n' >&2; exit 1; }

ns_control_reset "$PROJECT"
exit "$?"
