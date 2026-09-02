#!/bin/sh
# fake-manager.sh — the package manager stand-in for the python recipe fixtures.
#
# Installed into a fixture's .venv/bin by make-project.sh under whichever manager names the
# case's lockfiles imply; it reads its own name to know which one it is. make-project.sh
# replaces @EXIT@ with the exit code the case wants: 0 installs, anything else reports an index
# it cannot reach, which is how the package-failure case is read without a network.
#
# A successful install writes the console-script stub for each package it was handed, when one
# is not already there, and appends a line to the lockfile it owns — so a recipe's additions,
# smoke, and rollback are all readable against the same touched files a real manager leaves.
set -u
code=@EXIT@
name="$(basename "$0")"
bin="$(cd "$(dirname "$0")" && pwd)"

printf '%s %s\n' "$name" "$*"

if [ "$code" -ne 0 ]; then
  printf '%s: could not reach the package index\n' "$name" >&2
  exit "$code"
fi

case "$name" in
  uv) [ ! -f uv.lock ] || printf '# development dependency recorded by the fixture manager\n' >>uv.lock ;;
  poetry) [ ! -f poetry.lock ] || printf '# development dependency recorded by the fixture manager\n' >>poetry.lock ;;
esac

for arg in "$@"; do
  case "$arg" in
    pytest-cov*) scripts='pytest coverage' ;;
    pytest*) scripts=pytest ;;
    ruff*) scripts=ruff ;;
    mypy*) scripts=mypy ;;
    sphinx*) scripts='sphinx-build' ;;
    *) continue ;;
  esac
  for script in $scripts; do
    [ ! -e "$bin/$script" ] || continue
    cat >"$bin/$script" <<'STUB'
#!/bin/sh
printf '%s: no findings\n' "$(basename "$0")"
exit 0
STUB
    chmod +x "$bin/$script"
  done
done

exit 0
