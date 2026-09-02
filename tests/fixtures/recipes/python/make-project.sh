#!/usr/bin/env bash
# make-project.sh <project-dir> <case> [manager-exit-code]
#
# Copies one python fixture tree into an armed Nightshift project and installs the
# scripted package managers its lockfiles name. Exit code defaults to 0 (success);
# pass a non-zero value for the package-failure matrix.
set -euo pipefail
dest="${1:?usage: make-project.sh <project-dir> <case> [exit-code]}"
case_name="${2:?usage: make-project.sh <project-dir> <case> [exit-code]}"
exit_code="${3:-0}"
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/$case_name"
[ -d "$src" ] || {
  printf 'make-project: unknown case %s\n' "$case_name" >&2
  exit 1
}

while IFS= read -r -d '' item; do
  base="$(basename "$item")"
  cp -R "$item" "$dest/$base"
done < <(find "$src" -mindepth 1 -maxdepth 1 ! -name .git -print0)

python3 -m venv "$dest/.venv"
bindir="$dest/.venv/bin"
fake="$(mktemp "${TMPDIR:-/tmp}/ns-fake-mgr.XXXXXX")"
sed "s/@EXIT@/$exit_code/" "$here/fake-manager.sh" >"$fake"
chmod +x "$fake"

install_mgr() {
  cp "$fake" "$bindir/$1"
  chmod +x "$bindir/$1"
}

[ -f "$dest/uv.lock" ] && install_mgr uv
[ -f "$dest/poetry.lock" ] && install_mgr poetry
if [ -f "$dest/requirements.txt" ] || [ -f "$dest/pyproject.toml" ]; then
  install_mgr pip
  cat >"$bindir/pip3" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/pip" "$@"
EOF
  chmod +x "$bindir/pip3"
fi
rm -f "$fake"

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add python recipe fixture" || true
