#!/usr/bin/env bash
# make-static-site.sh <project-dir> [variant]
# variant: minimal (default) | red-baseline
set -euo pipefail
dest="${1:?usage: make-static-site.sh <project-dir> [variant]}"
variant="${2:-minimal}"
root="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$dest"
cp "$root/static-site/index.html" "$dest/"
cp "$root/static-site/about.html" "$dest/"
cp "$root/static-site/styles.css" "$dest/"
cp "$root/static-site/main.js" "$dest/"

if [ "$variant" = red-baseline ]; then
  cp "$root/red-baseline/index.html" "$dest/index.html"
fi

cat >"$dest/package.json" <<'EOF'
{
  "name": "nightshift-seo-perf-fixture",
  "private": true,
  "version": "0.0.0"
}
EOF

cat >"$dest/package-lock.json" <<'EOF'
{
  "name": "nightshift-seo-perf-fixture",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "nightshift-seo-perf-fixture",
      "version": "0.0.0"
    }
  }
}
EOF

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add static seo-perf fixture"
