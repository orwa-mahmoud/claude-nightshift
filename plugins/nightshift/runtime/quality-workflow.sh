#!/usr/bin/env bash
# quality-workflow.sh — normalize, dedupe, and rank quality findings.
#
#   quality-workflow.sh pipeline --manifest PATH [--established FINDINGS.jsonl]
#   quality-workflow.sh compose-discovery --scan PATH [--hours H]
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/quality-workflow.py"
SCAN="$_here/quality-scan.sh"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
MANIFEST=""
SCAN_IN=""
HOURS="4"
EST=""

while [ $# -gt 0 ]; do
  case "$1" in
    pipeline | compose-discovery)
      CMD="$1"
      shift
      ;;
    --manifest)
      [ $# -ge 2 ] || usage
      MANIFEST="$2"
      shift 2
      ;;
    --scan)
      [ $# -ge 2 ] || usage
      SCAN_IN="$2"
      shift 2
      ;;
    --hours)
      [ $# -ge 2 ] || usage
      HOURS="$2"
      shift 2
      ;;
    --established)
      [ $# -ge 2 ] || usage
      EST="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'quality-workflow: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] || usage
[ -f "$PY" ] || {
  printf 'quality-workflow: runtime/quality-workflow.py is not installed\n' >&2
  exit 2
}

case "$CMD" in
  pipeline)
    [ -n "$MANIFEST" ] || usage
    tmp="$(mktemp "${TMPDIR:-/tmp}/ns-qscan.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    bash "$SCAN" --manifest "$MANIFEST" >"$tmp" || exit 2
    args=(pipeline --input "$tmp")
    [ -n "$EST" ] && args+=(--established "$EST")
    exec python3 "$PY" "${args[@]}"
    ;;
  compose-discovery)
    [ -n "$SCAN_IN" ] || usage
    exec python3 "$PY" compose-discovery --input "$SCAN_IN" --hours "$HOURS"
    ;;
esac
