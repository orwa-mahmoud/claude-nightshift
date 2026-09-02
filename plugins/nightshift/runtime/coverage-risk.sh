#!/usr/bin/env bash
# coverage-risk.sh — explainable coverage risk mapping (read-only).
#
#   coverage-risk.sh map --input MANIFEST.json
#   coverage-risk.sh receipt-line --input MAP.json [--cluster N]
#   coverage-risk.sh red-state --input MAP.json --cluster ID --observed fail|pass
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/coverage-risk.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""
CLUSTER="1"
CLUSTER_ID=""
OBSERVED=""

while [ $# -gt 0 ]; do
  case "$1" in
    map | receipt-line | red-state)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    --cluster)
      [ $# -ge 2 ] || usage
      if [ "$CMD" = red-state ]; then
        CLUSTER_ID="$2"
      else
        CLUSTER="$2"
      fi
      shift 2
      ;;
    --observed)
      [ $# -ge 2 ] || usage
      OBSERVED="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'coverage-risk: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'coverage-risk: runtime/coverage-risk.py is not installed\n' >&2
  exit 2
}

case "$CMD" in
  map) exec python3 "$PY" map --input "$INPUT" ;;
  receipt-line) exec python3 "$PY" receipt-line --input "$INPUT" --cluster "$CLUSTER" ;;
  red-state) exec python3 "$PY" red-state --input "$INPUT" --cluster "$CLUSTER_ID" --observed "$OBSERVED" ;;
esac
