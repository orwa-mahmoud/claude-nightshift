#!/bin/sh
# fake-pip.sh — uv/pip/pip-audit/vulture stand-in for security recipe fixtures.
set -u
code=@EXIT@
name="$(basename "$0")"
bin="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$bin/.." && pwd)"

printf '%s %s\n' "$name" "$*"

if [ "$code" -ne 0 ]; then
  printf '%s: could not reach the index\n' "$name" >&2
  exit "$code"
fi

case "$name" in
  uv)
    case "$1" in
      add) [ ! -f "$root/uv.lock" ] || printf '# dev dependency recorded\n' >>"$root/uv.lock" ;;
      remove) ;;
    esac
    ;;
  pip)
    case "$*" in
      *install*) ;;
    esac
    ;;
  pip-audit)
    printf '{"dependencies":[]}\n'
    exit 0
    ;;
  vulture)
    printf 'src/nightshift_fixture/__init__.py:3: unused function (fixture)\n'
    exit 0
    ;;
esac

exit 0
