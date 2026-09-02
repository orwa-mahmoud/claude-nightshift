#!/usr/bin/env bash
# seo-evidence.sh — Local, Live, and Connected SEO evidence helpers.
#
#   seo-evidence.sh local-inventory|live-crawl|connected-export|rank-blockers|receipt-summary --input PATH
#
# Exit: 0 ok · 1 usage · 2 missing runtime
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
PY="$_here/seo-evidence.py"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

CMD=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    local-inventory | live-crawl | connected-export | rank-blockers | receipt-summary)
      CMD="$1"
      shift
      ;;
    --input)
      [ $# -ge 2 ] || usage
      INPUT="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'seo-evidence: unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done

[ -n "$CMD" ] && [ -n "$INPUT" ] || usage
[ -f "$PY" ] || {
  printf 'seo-evidence: runtime/seo-evidence.py is not installed\n' >&2
  exit 2
}

exec python3 "$PY" "$CMD" --input "$INPUT"
