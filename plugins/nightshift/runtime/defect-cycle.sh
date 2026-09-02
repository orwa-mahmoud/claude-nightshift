#!/usr/bin/env bash
# defect-cycle.sh — defect hunt lens rotation and cycle state.
#
#   defect-cycle.sh init --project DIR --shift-id ID
#   defect-cycle.sh next-lens --project DIR
#   defect-cycle.sh record --project DIR --finding PATH
#   defect-cycle.sh reject --project DIR --id ID --reason TEXT
#   defect-cycle.sh fix --project DIR --id ID
#   defect-cycle.sh summary --project DIR
#
# Exit: 0 ok · 1 usage · 2 contract failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"
PY="$_here/defect-cycle.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
CMD=""
SHIFT_ID=""
FINDING=""
FID=""
REASON=""

while [ $# -gt 0 ]; do
  case "$1" in
    init | next-lens | record | reject | fix | summary)
      CMD="$1"
      shift
      ;;
    --project)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    --shift-id)
      [ $# -ge 2 ] || usage
      SHIFT_ID="$2"
      shift 2
      ;;
    --finding)
      [ $# -ge 2 ] || usage
      FINDING="$2"
      shift 2
      ;;
    --id)
      [ $# -ge 2 ] || usage
      FID="$2"
      shift 2
      ;;
    --reason)
      [ $# -ge 2 ] || usage
      REASON="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'defect-cycle: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] || usage
WORKSPACE="$(ns_workspace_root "$PROJECT" 2>/dev/null)" || WORKSPACE="$PROJECT"
STORE="$WORKSPACE/.nightshift/defect-cycle.json"
[ -f "$PY" ] || {
  printf 'defect-cycle: runtime/defect-cycle.py is not installed\n' >&2
  exit 2
}

case "$CMD" in
  init)
    [ -n "$SHIFT_ID" ] || usage
    mkdir -p "$WORKSPACE/.nightshift" || exit 2
    exec python3 "$PY" init --path "$STORE" --shift-id "$SHIFT_ID"
    ;;
  next-lens) exec python3 "$PY" next-lens --path "$STORE" ;;
  record)
    [ -n "$FINDING" ] || usage
    exec python3 "$PY" record --path "$STORE" --finding "$FINDING"
    ;;
  reject)
    [ -n "$FID" ] && [ -n "$REASON" ] || usage
    exec python3 "$PY" reject --path "$STORE" --id "$FID" --reason "$REASON"
    ;;
  fix)
    [ -n "$FID" ] || usage
    exec python3 "$PY" fix --path "$STORE" --id "$FID"
    ;;
  summary) exec python3 "$PY" summary --path "$STORE" ;;
esac
