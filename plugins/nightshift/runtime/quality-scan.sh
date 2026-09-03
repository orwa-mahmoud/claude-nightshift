#!/usr/bin/env bash
# quality-scan.sh — read-only quality scan from a fixture manifest or project gates.
#
#   quality-scan.sh --manifest PATH
#
# Loads a scan manifest whose sources embed raw captures or reference raw files
# relative to the manifest directory. Prints scan-ready manifest JSON on stdout.
# Never mutates project scripts.
#
# Exit: 0 ok · 1 usage · 2 contract failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

MANIFEST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      [ $# -ge 2 ] || usage
      MANIFEST="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) printf 'quality-scan: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ -n "$MANIFEST" ] || usage
[ -f "$MANIFEST" ] || {
  printf 'quality-scan: manifest not found: %s\n' "$MANIFEST" >&2
  exit 2
}

dir="${MANIFEST%/*}"
if ! command -v python3 >/dev/null 2>&1; then
  printf 'quality-scan: unused; run the project tools in the skill\n' >&2
  exit 2
fi

python3 - "$MANIFEST" "$dir" <<'PY'
import json, sys
from pathlib import Path

manifest_path, base = sys.argv[1:3]
base = Path(base)
with open(manifest_path, encoding="utf-8") as fh:
    doc = json.load(fh)
for src in doc.get("sources") or []:
    if src.get("rawFile"):
        raw_path = base / src["rawFile"]
        src["raw"] = raw_path.read_text(encoding="utf-8")
        del src["rawFile"]
print(json.dumps(doc, indent=2, sort_keys=True))
PY
