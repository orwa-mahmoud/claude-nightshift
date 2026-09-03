#!/usr/bin/env bats
# SEO evidence — skill writes the receipt. Wrapper removed.

ROOT="$BATS_TEST_DIRNAME/.."
SEO="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/seo-audit.md"
TEMPLATES="$ROOT/plugins/nightshift/skills/nightshift/references/receipt-templates.md"

@test "seo-evidence python wrapper is gone" {
  [ ! -e "$ROOT/plugins/nightshift/runtime/seo-evidence.sh" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/seo-evidence.py" ]
}

@test "seo audit writes a receipt and refuses invented live-crawl" {
  grep -qF 'receipt-templates.md' "$SEO"
  ! grep -qF 'runtime/seo-evidence.sh' "$SEO"
  grep -qF '# seo' "$TEMPLATES"
  grep -qF 'Refuse live-crawl' "$TEMPLATES"
  grep -qF 'neverLeaveApprovedOrigins' "$TEMPLATES"
}
