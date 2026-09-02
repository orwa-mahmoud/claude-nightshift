#!/usr/bin/env bash
# owner-work-evidence.sh — owner-defined work evidence helpers.
#
#   owner-work-evidence.sh issue-graph|walkthrough-plan|evolution-hypothesis|receipt-link --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/owner-work-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    issue-graph | walkthrough-plan | evolution-hypothesis | receipt-link)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'owner-work-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'owner-work-evidence: runtime/owner-work-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
