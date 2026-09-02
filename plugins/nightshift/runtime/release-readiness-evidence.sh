#!/usr/bin/env bash
# release-readiness-evidence.sh — baseline comparison and public-claims evidence helpers.
#
#   release-readiness-evidence.sh baseline-compare|public-claims-matrix|verdict|unmeasured-surfaces --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/release-readiness-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    baseline-compare | public-claims-matrix | verdict | unmeasured-surfaces)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'release-readiness-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'release-readiness-evidence: runtime/release-readiness-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
