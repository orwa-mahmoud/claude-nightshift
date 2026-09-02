#!/usr/bin/env bash
# migration-evidence.sh — guarded migration, config parity, and data safety evidence helpers.
#
#   migration-evidence.sh migration-inventory|compatibility-assess|config-parity|data-safety|recovery-plan|verdict --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/migration-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    migration-inventory | compatibility-assess | config-parity | data-safety | production-refusal | recovery-plan | verdict)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'migration-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'migration-evidence: runtime/migration-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
