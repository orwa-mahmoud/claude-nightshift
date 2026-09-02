#!/usr/bin/env bash
# plan-learning.sh — read or update the private plan-learning store.
#
#   plan-learning.sh --project DIR read
#   plan-learning.sh --project DIR update-from-receipt --receipt PATH
#
# Exit: 0 ok · 1 usage · 2 contract failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"
PY="$_here/plan-learning.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
CMD=""
RECEIPT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    --receipt)
      [ $# -ge 2 ] || usage
      RECEIPT="$2"
      shift 2
      ;;
    read | update-from-receipt)
      CMD="$1"
      shift
      ;;
    -h | --help) usage ;;
    *) printf 'plan-learning: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] || usage
WORKSPACE="$(ns_workspace_root "$PROJECT" 2>/dev/null)" || WORKSPACE="$PROJECT"
STORE="$WORKSPACE/.nightshift/plan-learning.json"
[ -f "$PY" ] || {
  printf 'plan-learning: runtime/plan-learning.py is not installed\n' >&2
  exit 2
}

case "$CMD" in
  read)
    exec python3 "$PY" read --path "$STORE"
    ;;
  update-from-receipt)
    [ -n "$RECEIPT" ] || usage
    [ -f "$RECEIPT" ] || {
      printf 'plan-learning: receipt not found: %s\n' "$RECEIPT" >&2
      exit 2
    }
    exec python3 "$PY" update-from-receipt --path "$STORE" --receipt "$RECEIPT"
    ;;
esac
