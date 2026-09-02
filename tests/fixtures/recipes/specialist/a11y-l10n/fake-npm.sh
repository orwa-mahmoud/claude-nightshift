#!/bin/sh
# fake-npm.sh — the npm/npx stand-in for a11y-l10n recipe fixtures.
#
# make-project.sh installs this as npm and npx under .fake-bin/. @EXIT@ is replaced
# with the exit code the case wants. Successful installs append to package-lock.json
# and write axe or node stubs when the package name matches.
set -u
code=@EXIT@
name="$(basename "$0")"
bin="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$bin/.." && pwd)"

printf '%s %s\n' "$name" "$*"

if [ "$name" = "npx" ]; then
  shift
  tool="${1:-}"
  case "$tool" in
    axe)
      exec "$bin/axe" "$@"
      ;;
    node)
      exec "$bin/node" "$@"
      ;;
  esac
  printf 'npx: unknown tool %s\n' "$tool" >&2
  exit 127
fi

if [ "$code" -ne 0 ]; then
  printf 'npm: could not reach the registry\n' >&2
  exit "$code"
fi

case "$1" in
  install)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --save-dev|--save|--save-prod|--save-optional|-D|-S|-O) shift ;;
        @axe-core/cli*)
          cat >"$bin/axe" <<'STUB'
#!/bin/sh
printf 'automated checks; not WCAG or user conformance\n'
printf 'axe: 0 violations (fixture)\n'
exit 0
STUB
          chmod +x "$bin/axe"
          ;;
        i18next-parser*)
          :
          ;;
        *) ;;
      esac
      shift
    done
    [ ! -f "$root/package-lock.json" ] || printf '# dev dependency recorded by the fixture manager\n' >>"$root/package-lock.json"
    ;;
  exec)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --no|--yes|-y|-n) shift ;;
        axe)
          shift
          exec "$bin/axe" "$@"
          ;;
        *) shift ;;
      esac
    done
    ;;
  uninstall|remove)
    rm -f "$bin/axe"
    ;;
esac

if [ ! -x "$bin/node" ]; then
  cat >"$bin/node" <<'NODE'
#!/bin/sh
self="$(cd "$(dirname "$0")" && pwd)"
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$self" | tr '\n' ':' | sed 's/:$//')"
real="$(command -v node 2>/dev/null || true)"
if [ -n "$real" ] && [ "$real" != "$0" ]; then
  exec "$real" "$@"
fi
for candidate in /usr/local/bin/node /opt/homebrew/bin/node /usr/bin/node; do
  if [ -x "$candidate" ]; then
    exec "$candidate" "$@"
  fi
done
printf 'node: fixture runtime unavailable\n' >&2
exit 127
NODE
  chmod +x "$bin/node"
fi

exit 0
