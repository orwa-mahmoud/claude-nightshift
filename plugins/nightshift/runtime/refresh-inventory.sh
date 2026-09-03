#!/usr/bin/env bash
# refresh-inventory.sh — cache capability detection for the shift without mutating inventory items.
#
#   refresh-inventory.sh --project DIR [--host claude|codex|cursor]
#
# Runs the read-only detector and writes $NS/capability-detection.json. Provisioning inventory
# in capabilities.json is preserved; detection is re-probed each new shift or branch.
#
# Exit: 0 ok · 1 usage · 2 contract failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

die() {
  printf 'refresh-inventory: %s\n' "$1" >&2
  exit "$2"
}

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
HOST="${NIGHTSHIFT_HOST:-claude}"

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    --host)
      [ $# -ge 2 ] || usage
      HOST="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) die "unknown argument: $1" 1 ;;
  esac
done

WORKSPACE="$(ns_workspace_root "$PROJECT" 2>/dev/null)" || WORKSPACE="$PROJECT"
NS="$WORKSPACE/.nightshift"
DETECT="$_here/detect-capabilities.sh"
DEST="$(ns_evidence_detection_path "$WORKSPACE")"
[ -f "$DETECT" ] || die "runtime/detect-capabilities.sh is not installed" 2
mkdir -p "$NS" || die "cannot create $NS" 2
now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
tmp="$(mktemp "${TMPDIR:-/tmp}/ns-detect.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
bash "$DETECT" --project "$WORKSPACE" --host "$HOST" --normalize >"$tmp" || die "detection failed" 2
if command -v jq >/dev/null 2>&1; then
  jq -n --arg now "$now" --slurpfile det "$tmp" \
    '{schemaVersion:1, updatedAt:$now, source:"detect-capabilities", detection:$det[0]}' >"$DEST.tmp" \
    || die "cannot render $DEST" 2
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$now" "$tmp" "$DEST.tmp" <<'PY' || die "cannot render $DEST" 2
import json, sys
now, src, dest = sys.argv[1:4]
with open(src, encoding="utf-8") as fh:
    detection = json.load(fh)
doc = {"schemaVersion": 1, "updatedAt": now, "source": "detect-capabilities", "detection": detection}
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
else
  die "capability-detection cache unavailable (no JSON parser); inspect the repo in the skill" 2
fi
mv "$DEST.tmp" "$DEST" || die "cannot write $DEST" 2
printf '%s\n' "$DEST"
exit 0
