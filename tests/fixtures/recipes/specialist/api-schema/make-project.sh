#!/usr/bin/env bash
# make-project.sh <project-dir> <case> [manager-exit-code]
#
# Copies one api-schema fixture tree into an armed Nightshift project. When manager-exit-code is
# non-zero, the fake npm/pnpm/yarn stand-ins on PATH report an unreachable package index.
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

if [ "$exit_code" != "0" ]; then
  fake="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/fake-npm-$$"
  mkdir -p "$fake"
  for mgr in npm npx pnpm yarn; do
    sed "s/@EXIT@/$exit_code/" "$here/fake-npm.sh" >"$fake/$mgr"
    chmod +x "$fake/$mgr"
  done
  export PATH="$fake:$PATH"
fi

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add api-schema recipe fixture" || true
