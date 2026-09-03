#!/usr/bin/env bash
# shift-preview.sh — explainable Review-first preview from a shift plan (read-only).
#
#   shift-preview.sh [--input PLAN.json]
#
# Reads plan JSON from --input or stdin; prints Markdown on stdout. Never writes.
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/shift-preview.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'shift-preview: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -f "$PY" ] || {
  printf 'shift-preview: runtime/shift-preview.py is not installed\n' >&2
  exit 2
}

if [ -n "$INPUT" ]; then
  [ -f "$INPUT" ] || {
    printf 'shift-preview: input not found: %s\n' "$INPUT" >&2
    exit 1
  }
  exec python3 "$PY" --input "$INPUT"
fi

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$PY"
fi
printf 'shift-preview: unused; Hunt and Quality preview in the skill\n' >&2
exit 2
