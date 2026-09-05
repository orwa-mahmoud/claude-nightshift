#!/usr/bin/env bash
# continuity-handoff.sh — cross-host handoff and campaign sequencing helpers.
#
#   continuity-handoff.sh fence-check --project DIR
#   continuity-handoff.sh handoff-package|campaign-sequence|transition-history --input PATH
#
# fence-check reads the on-disk lease / session / pid. --input JSON flags cannot grant
# takeover. Missing or unreadable fence refuses (non-zero).
#
# Exit: 0 ok · 1 refuse/usage · 2 unavailable/missing runtime
set -u

_here="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]//\\//}")" && pwd)" || exit 2
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

ns_handoff_resolve_ns() { # <host-or-workspace>
  local host workspace
  [ -n "$1" ] || return 1
  host="$(cd -P "$1" 2>/dev/null && pwd)" || return 1
  workspace="$(ns_workspace_root "$host" 2>/dev/null)" || return 1
  [ -d "$workspace/.nightshift" ] && [ ! -L "$workspace/.nightshift" ] || return 1
  printf '%s' "$workspace/.nightshift"
}

CMD=""
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    handoff-package | fence-check | campaign-sequence | transition-history)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      shift 2
      ;;
    --project)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'continuity-handoff: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] || usage

if [ "$CMD" = "fence-check" ]; then
  ns=""
  if [ -n "$PROJECT" ]; then
    ns="$(ns_handoff_resolve_ns "$PROJECT")" || {
      ns_fence_print refuse 0 0 0 0
      exit 2
    }
  fi
  # --input is accepted so old call sites fail closed; its flags never grant takeover.
  if [ -z "$ns" ]; then
    ns_fence_print refuse 0 0 0 0
    exit 2
  fi
  ns_fence_check "$ns"
  exit "$?"
fi

# Leftover commands are folded into Status/Start. Do not require Python.
printf 'continuity-handoff: %s is unused; summarize from shift-log.md in the skill\n' "$CMD" >&2
exit 2
