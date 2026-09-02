#!/usr/bin/env bash
# specialist-evidence.sh — product journey and evidence-gated specialist helpers.
#
#   specialist-evidence.sh journey-map|journey-gap|journey-retest|specialist-gate|
#     architecture-findings|data-quality-map|supply-chain-posture|
#     analytics-investigation|content-architecture|maintainer-health-preset --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/specialist-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    journey-map | journey-gap | journey-retest | specialist-gate | architecture-findings | data-quality-map | supply-chain-posture | analytics-investigation | content-architecture | maintainer-health-preset)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'specialist-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'specialist-evidence: runtime/specialist-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
