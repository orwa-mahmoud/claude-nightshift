#!/usr/bin/env bash
# pr-readiness-evidence.sh — pull-request readiness evidence helpers.
#
#   pr-readiness-evidence.sh acceptance-map|review-map|diff-scope|owner-action-refusal --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/pr-readiness-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    acceptance-map | review-map | diff-scope | owner-action-refusal)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'pr-readiness-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'pr-readiness-evidence: runtime/pr-readiness-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
