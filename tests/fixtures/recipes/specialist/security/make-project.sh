#!/usr/bin/env bash
# make-project.sh <project-dir> <case> [exit-code]
set -euo pipefail
dest="${1:?usage: make-project.sh <project-dir> <case> [exit-code]}"
case_name="${2:?usage: make-project.sh <project-dir> <case> [exit-code]}"
exit_code="${3:-0}"
here="$(cd "$(dirname "$0")" && pwd)"

if [ "$case_name" = go-minimal ]; then
  bash "$here/../../go/minimal-module.sh" "$dest"
else
  src="$here/$case_name"
  [ -d "$src" ] || { printf 'make-project: unknown case %s\n' "$case_name" >&2; exit 1; }
  while IFS= read -r -d '' item; do
    cp -R "$item" "$dest/$(basename "$item")"
  done < <(find "$src" -mindepth 1 -maxdepth 1 ! -name .git -print0)
fi

bindir="$dest/.fake-bin"
mkdir -p "$bindir"
case "$case_name" in
  minimal-npm | minimal-npm-knip) fake_src="$here/fake-npm.sh" ;;
  minimal-uv*) fake_src="$here/fake-pip.sh" ;;
  go-minimal) fake_src="$here/fake-go.sh" ;;
  *) fake_src="$here/fake-npm.sh" ;;
esac
fake="$(mktemp "${TMPDIR:-/tmp}/ns-fake-sec.XXXXXX")"
sed "s/@EXIT@/$exit_code/" "$fake_src" >"$fake"
chmod +x "$fake"
for tool in npm npx uv pip pip-audit vulture knip go govulncheck; do
  cp "$fake" "$bindir/$tool"
  chmod +x "$bindir/$tool"
done
rm -f "$fake"

if [ "$case_name" = minimal-uv ] || [ "$case_name" = minimal-uv-pip ] || [ "$case_name" = minimal-uv-vulture ]; then
  mkdir -p "$dest/.venv/bin"
  for tool in pip pip-audit vulture python python3 uv; do
    cp "$bindir/$tool" "$dest/.venv/bin/$tool" 2>/dev/null || true
    chmod +x "$dest/.venv/bin/$tool" 2>/dev/null || true
  done
fi

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add security recipe fixture" || true
