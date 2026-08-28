#!/usr/bin/env bash
# purge-workspace.sh — delete this project's Nightshift state. Does not uninstall the plugin.
#
#   purge-workspace.sh --project DIR --confirm-path /canonical/.nightshift
#
# Prints the canonical .nightshift path. Refuses without an exact --confirm-path match.
# --project is required. Does not use the current working directory.
#
# Exit: 0 purged · 1 usage/refuse
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"
# shellcheck source=plugins/nightshift/lib/control.sh
. "$_here/../lib/control.sh"

PROJECT=""
CONFIRM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'purge-workspace: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    --confirm-path)
      [ $# -ge 2 ] || { printf 'purge-workspace: --confirm-path needs a value\n' >&2; exit 1; }
      CONFIRM="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'purge-workspace: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] || { printf 'purge-workspace: --project is required\n' >&2; exit 1; }
if [ -z "$CONFIRM" ]; then
  if ns_control_resolve "$PROJECT"; then
    printf 'purge-workspace: refusing without --confirm-path %s\n' "$NS_CONTROL_WORKSPACE/.nightshift" >&2
  else
    printf 'purge-workspace: --confirm-path is required\n' >&2
  fi
  exit 1
fi

ns_control_purge "$PROJECT" "$CONFIRM"
exit "$?"
