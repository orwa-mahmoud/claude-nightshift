#!/usr/bin/env bash
# minimal-npm.sh <project-dir> — package.json with a single npm lockfile.
set -euo pipefail
dest="${1:?usage: minimal-npm.sh <project-dir>}"
cat >"$dest/package.json" <<'EOF'
{
  "name": "nightshift-fixture",
  "private": true,
  "version": "0.0.0"
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
git -C "$dest" add package.json package-lock.json
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add npm fixture"
