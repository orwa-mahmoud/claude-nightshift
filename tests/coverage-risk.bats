#!/usr/bin/env bats
# Coverage hunt — skill writes the receipt. Wrapper removed.

ROOT="$BATS_TEST_DIRNAME/.."
COVERAGE="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/coverage-hunt.md"
TEMPLATES="$ROOT/plugins/nightshift/skills/nightshift/references/receipt-templates.md"

@test "coverage-risk python wrapper is gone" {
  [ ! -e "$ROOT/plugins/nightshift/runtime/coverage-risk.sh" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/coverage-risk.py" ]
}

@test "coverage hunt writes a risk receipt without the wrapper" {
  grep -qF 'receipt-templates.md' "$COVERAGE"
  ! grep -qF 'runtime/coverage-risk.sh' "$COVERAGE"
  grep -qi 'behavior-protecting' "$COVERAGE"
  grep -qi 'misleading high coverage' "$COVERAGE"
  grep -qi 'mutation/property/fuzz' "$COVERAGE"
  grep -qi 'receipt line' "$COVERAGE"
  grep -qF '# coverage-risk' "$TEMPLATES"
}
