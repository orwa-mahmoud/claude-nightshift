#!/usr/bin/env bash
# minimal-npm-audit.sh <project-dir> — npm lockfile project for security recipe fixtures.
set -euo pipefail
dest="${1:?usage: minimal-npm-audit.sh <project-dir>}"
cat >"$dest/package.json" <<'EOF'
{
  "name": "nightshift-fixture",
  "private": true,
  "version": "0.0.0",
  "dependencies": {
    "semver": "7.5.1"
  }
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
      "version": "0.0.0",
      "dependencies": {
        "semver": "7.5.1"
      }
    }
  }
}
EOF
git -C "$dest" add package.json package-lock.json
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add npm audit fixture"
