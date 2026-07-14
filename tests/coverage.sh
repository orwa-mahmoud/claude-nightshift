#!/usr/bin/env bash
# Line coverage for the shipped bash (hooks/ + adapters/) — kcov over the bats suite.
# kcov's bash tracer is Linux-only: on Linux with kcov installed this runs natively,
# anywhere else it runs in a debian container (docker required).
# Output: coverage/ — kcov HTML + cobertura, plus coverage/sonar-generic.xml.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf coverage
mkdir -p coverage

if [ "$(uname -s)" = Linux ] && command -v kcov >/dev/null 2>&1; then
  kcov --include-path="$PWD/hooks,$PWD/adapters" coverage "$(command -v bats)" tests/
else
  docker run --rm -v "$PWD:/src" -w /src debian:stable-slim sh -c '
    apt-get update -qq >/dev/null && apt-get install -y -qq kcov bats git jq shellcheck >/dev/null
    git config --global user.email dev@example.com
    git config --global user.name dev
    git config --global --add safe.directory "*"
    kcov --include-path=/src/hooks,/src/adapters /src/coverage "$(command -v bats)" /src/tests'
fi

cob="$(find coverage -name cobertura.xml | head -n 1)"
python3 - "$cob" <<'PY'
import sys, xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
out = ['<coverage version="1">']
for cls in root.iter('class'):
    path, lines = cls.get('filename'), cls.find('lines')
    if not path or lines is None:
        continue
    out.append(f'  <file path="{path}">')
    for ln in lines.iter('line'):
        covered = 'true' if int(ln.get('hits', '0')) > 0 else 'false'
        out.append(f'    <lineToCover lineNumber="{ln.get("number")}" covered="{covered}"/>')
    out.append('  </file>')
out.append('</coverage>')
open('coverage/sonar-generic.xml', 'w').write('\n'.join(out) + '\n')
PY

jq -r '"coverage: " + .percent_covered + "% of " + (.total_lines|tostring) + " lines"' \
  "$(dirname "$cob")/coverage.json"
