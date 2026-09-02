#!/usr/bin/env bats
# Product-truth evidence helpers — API, a11y, l10n, documentation.

ROOT="$BATS_TEST_DIRNAME/.."
PT="$ROOT/plugins/nightshift/runtime/product-truth-evidence.sh"
FIX="$ROOT/tests/fixtures/product-truth"

@test "product-truth script is executable" {
  [ -x "$PT" ]
}

@test "api classify separates breaking from additive drift" {
  run bash "$PT" api-classify --input "$FIX/api-drift.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.items[] | select(.classification=="breaking") | .action] | all == "park"' >/dev/null
  printf '%s' "$output" | jq -e '.items[0].authoritativeSource == "openapi.yaml"' >/dev/null
}

@test "a11y report never certifies compliance from automation alone" {
  run bash "$PT" a11y-report --input "$FIX/a11y-violations.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.certificationClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.humanOnly | length >= 1 and .automated | length >= 1' >/dev/null
}

@test "l10n validate parks translation gaps without certifying quality" {
  run bash "$PT" l10n-validate --input "$FIX/l10n-catalog.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.translationQualityCertified == false' >/dev/null
  printf '%s' "$output" | jq -e '[.issues[] | select(.issue=="missing-key")] | length >= 1' >/dev/null
}

@test "doc claim matrix traces authority for each claim" {
  run bash "$PT" doc-claim-matrix --input "$FIX/doc-claims.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.rows[] | select(.verifiedLocally==false)] | length >= 1' >/dev/null
}

@test "doc outline requires fresh-reader pass" {
  run bash "$PT" doc-outline --input "$FIX/doc-brief.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.freshReaderPassRequired == true' >/dev/null
}

@test "all five product-truth contracts reference the helper" {
  for f in api-contract-drift accessibility-repair localization-parity documentation-drift documentation-writing; do
    grep -qF 'runtime/product-truth-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/$f.md" \
      || { echo "missing: $f"; return 1; }
  done
}
