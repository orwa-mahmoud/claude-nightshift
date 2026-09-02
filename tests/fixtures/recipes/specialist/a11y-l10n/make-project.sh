#!/usr/bin/env bash
# make-project.sh <project-dir> <case> [manager-exit-code]
#
# Copies one a11y/l10n fixture tree into an armed Nightshift project and installs
# the scripted npm stand-in its lockfile names. Exit code defaults to 0; pass a
# non-zero value for the package-failure matrix.
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

bindir="$dest/.fake-bin"
mkdir -p "$bindir"
fake="$(mktemp "${TMPDIR:-/tmp}/ns-fake-npm.XXXXXX")"
sed "s/@EXIT@/$exit_code/" "$here/fake-npm.sh" >"$fake"
chmod +x "$fake"
cp "$fake" "$bindir/npm"
cp "$fake" "$bindir/npx"
chmod +x "$bindir/npm" "$bindir/npx"
rm -f "$fake"

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add a11y-l10n recipe fixture" || true
