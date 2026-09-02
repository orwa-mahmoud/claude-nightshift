#!/usr/bin/env bash
# minimal-knip.sh <project-dir> — npm project with a reachable entry for dead-code fixtures.
set -euo pipefail
dest="${1:?usage: minimal-knip.sh <project-dir>}"
cat >"$dest/package.json" <<'EOF'
{
  "name": "nightshift-fixture",
  "private": true,
  "version": "0.0.0",
  "type": "module"
}
EOF
cat >"$dest/package-lock.json" <<'EOF'
{
  "name": "nightshift-fixture",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "nightshift-fixture",
      "version": "0.0.0"
    }
  }
}
EOF
cat >"$dest/index.js" <<'EOF'
export function used() {
  return 1;
}
EOF
cat >"$dest/orphan.js" <<'EOF'
export function unusedExport() {
  return 2;
}
EOF
git -C "$dest" add package.json package-lock.json index.js orphan.js
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add knip fixture"
