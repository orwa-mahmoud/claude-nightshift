#!/usr/bin/env bash
# already-configured.sh <project-dir> — htmlhint present before provisioning runs.
set -euo pipefail
dest="${1:?usage: already-configured.sh <project-dir>}"
root="$(cd "$(dirname "$0")" && pwd)"

bash "$root/make-static-site.sh" "$dest"

cat >"$dest/.htmlhintrc" <<'EOF'
{
  "tagname-lowercase": true,
  "title-require": true
}
EOF

node -e '
const fs = require("fs");
const path = require("path").join(process.argv[1], "package.json");
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.devDependencies = Object.assign({}, pkg.devDependencies, {
  htmlhint: "^1.1.4",
  serve: "^14.0.0"
});
fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
' "$dest"

git -C "$dest" add -A
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "chore(tooling): seo-performance"
