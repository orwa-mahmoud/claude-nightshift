#!/usr/bin/env bash
# Docs-only CI: the bats files that grep README, docs/, examples/, or GitHub templates.
# Runtime changes still run the full shard matrix, which already includes these files.
set -euo pipefail
cd "$(dirname "$0")/.."

bats \
  tests/artifact-receipts.bats \
  tests/bad-night-template.bats \
  tests/contribution-map.bats \
  tests/cursor/honesty.bats \
  tests/doc-refs.bats \
  tests/first-night-checklist.bats \
  tests/github-templates.bats \
  tests/morning-receipt-docs.bats \
  tests/rule-profiles.bats \
  tests/schedule.bats \
  tests/shift-modes.bats \
  tests/skill-refs.bats \
  tests/troubleshooting.bats
