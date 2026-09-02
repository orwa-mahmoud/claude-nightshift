#!/usr/bin/env bash
# shift-planner.sh — deterministic shift planner (read-only).
#
#   shift-planner.sh --input PATH --hours H [--selection automatic|guided]
#     [--launch review-first|run-direct] [--learning PATH] [--selection-ids a,b]
#
# Prints canonical shift-plan JSON on stdout. Never writes inside the project.
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/shift-planner.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

INPUT=""
HOURS=""
SELECTION="automatic"
LAUNCH="review-first"
LEARNING=""
IDS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    --hours)
      [ $# -ge 2 ] || usage
      HOURS="$2"
      shift 2
      ;;
    --selection)
      [ $# -ge 2 ] || usage
      SELECTION="$2"
      shift 2
      ;;
    --launch)
      [ $# -ge 2 ] || usage
      LAUNCH="$2"
      shift 2
      ;;
    --learning)
      [ $# -ge 2 ] || usage
      LEARNING="$2"
      shift 2
      ;;
    --selection-ids)
      [ $# -ge 2 ] || usage
      IDS="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'shift-planner: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$INPUT" ] && [ -n "$HOURS" ] || usage
[ -f "$PY" ] || {
  printf 'shift-planner: runtime/shift-planner.py is not installed\n' >&2
  exit 2
}
[ -f "$INPUT" ] || {
  printf 'shift-planner: input not found: %s\n' "$INPUT" >&2
  exit 1
}

args=(--input "$INPUT" --hours "$HOURS" --selection "$SELECTION" --launch "$LAUNCH")
[ -n "$LEARNING" ] && args+=(--learning "$LEARNING")
[ -n "$IDS" ] && args+=(--selection-ids "$IDS")

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$PY" "${args[@]}"
fi
printf 'shift-planner: python3 is required\n' >&2
exit 2
