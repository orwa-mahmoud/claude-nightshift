#!/usr/bin/env bash
# already-configured.sh <project-dir> — openapi fixture whose history already carries the setup
# commit for api-schema-openapi.
set -euo pipefail
dir="${1:?usage: already-configured.sh <project-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/make-project.sh" "$dir" already-configured
git -C "$dir" commit -q --allow-empty -m "chore(tooling): api-schema"
