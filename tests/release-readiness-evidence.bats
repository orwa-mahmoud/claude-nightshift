#!/usr/bin/env bats
# Release readiness — skill writes the receipt. Wrapper removed.

ROOT="$BATS_TEST_DIRNAME/.."
RR="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/release-readiness.md"
TEMPLATES="$ROOT/plugins/nightshift/skills/nightshift/references/receipt-templates.md"

@test "release-readiness-evidence python wrapper is gone" {
  [ ! -e "$ROOT/plugins/nightshift/runtime/release-readiness-evidence.sh" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/release-readiness-evidence.py" ]
}

@test "release-readiness writes a receipt from the template" {
  grep -qF 'receipt-templates.md' "$RR"
  if grep -qF 'runtime/release-readiness-evidence.sh' "$RR"; then
    return 1
  fi
  grep -qF '# build-onboarding / pr-readiness / release-readiness' "$TEMPLATES"
}
