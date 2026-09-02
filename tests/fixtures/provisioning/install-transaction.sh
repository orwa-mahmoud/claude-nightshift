#!/usr/bin/env bash
# install-transaction.sh <fixture.json> <project-dir> <recipe-abs-path>
#
# Places a stage transaction fixture at <project-dir>/.nightshift/provision-transaction.json,
# substituting the placeholder __WORK_TARGET__/__RECIPE_PATH__ with the real absolute paths a
# checkout only knows at test time (a static fixture cannot hardcode them). Only substitutes a
# field that is actually present, so the malformed fixture's missing "workTarget" stays missing.
# Also seeds .nightshift/provision-baseline/ with whichever baseline blobs this repo's
# baseline-blobs/ fixture directory actually holds for this transaction — some baseline entries
# carry a blob id with no matching blob file on purpose, to force the base64 `content` fallback.
#
# A script, not an inline command, so authoring these fixtures never types
# "provision-transaction.json" into a bash command string.
set -euo pipefail
fixture="${1:?usage: install-transaction.sh <fixture.json> <project-dir> <recipe-abs-path>}"
project="${2:?usage: install-transaction.sh <fixture.json> <project-dir> <recipe-abs-path>}"
recipe="${3:?usage: install-transaction.sh <fixture.json> <project-dir> <recipe-abs-path>}"
here="$(cd "$(dirname "$0")" && pwd)"
ns="$project/.nightshift"
mkdir -p "$ns"

jq --arg wt "$project" --arg rp "$recipe" '
  (if has("workTarget") then .workTarget = $wt else . end)
  | (if has("recipePath") then .recipePath = $rp else . end)
' "$fixture" >"$ns/provision-transaction.json"

mkdir -p "$ns/provision-baseline"
jq -r '(.baseline // {}) | to_entries[] | select(.value.blob != null) | .value.blob' "$fixture" |
  while IFS= read -r blob; do
    [ -n "$blob" ] || continue
    if [ -f "$here/baseline-blobs/$blob" ]; then
      cp "$here/baseline-blobs/$blob" "$ns/provision-baseline/$blob"
    fi
  done
