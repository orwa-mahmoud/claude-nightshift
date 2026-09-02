#!/usr/bin/env bats
# Coverage risk mapping — behavior-protecting clusters and test adequacy.

ROOT="$BATS_TEST_DIRNAME/.."
CR="$ROOT/plugins/nightshift/runtime/coverage-risk.sh"
FIX="$ROOT/tests/fixtures/testing/coverage-risk"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
MAP_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/coverage-risk-map.json"
COVERAGE="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/coverage-hunt.md"

@test "coverage-risk scripts are executable" {
  [ -x "$CR" ]
}

@test "risk map ranks auth and changed-code above padding targets" {
  run bash "$CR" map --input "$FIX/manifest.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.clusters[0].riskCategory == "auth"' >/dev/null
  printf '%s' "$output" | jq -e '.clusters | map(.misleadingCoverage) | all == false' >/dev/null
  printf '%s' "$output" | jq -e '.misleadingCoverageRejected == true' >/dev/null
}

@test "risk map validates against schema and rejects mutation without policy" {
  map="$BATS_TEST_TMPDIR/map.json"
  bash "$CR" map --input "$FIX/manifest.json" >"$map"
  python3 "$SCHEMA_PY" "$MAP_SCHEMA" "$map"
  jq -e '.unsupportedSurfaces | index("mutation/property/fuzz checks detected but not allowed by shift policy")' "$map" >/dev/null
}

@test "misleading high coverage alone produces no valid clusters" {
  run bash "$CR" map --input "$FIX/misleading.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.clusters | length == 0' >/dev/null
  printf '%s' "$output" | jq -e '.misleadingCoverageRejected == true' >/dev/null
}

@test "receipt line names behavior protected not percentage" {
  map="$BATS_TEST_TMPDIR/map.json"
  bash "$CR" map --input "$FIX/manifest.json" >"$map"
  run bash "$CR" receipt-line --input "$map" --cluster 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'protected:'
  printf '%s\n' "$output" | grep -qF 'regression:'
  ! printf '%s\n' "$output" | grep -qE '[0-9]{2,}%'
}

@test "red-state helper records demonstrated failure" {
  map="$BATS_TEST_TMPDIR/map.json"
  bash "$CR" map --input "$FIX/manifest.json" >"$map"
  cid="$(jq -r '.clusters[0].id' "$map")"
  run bash "$CR" red-state --input "$map" --cluster "$cid" --observed fail
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.redStateDemonstrated == true' >/dev/null
}

@test "coverage hunt contract references risk mapping helpers" {
  grep -qF 'runtime/coverage-risk.sh map' "$COVERAGE"
  grep -qi 'behavior-protecting' "$COVERAGE"
  grep -qi 'misleading high coverage' "$COVERAGE"
  grep -qi 'mutation/property/fuzz' "$COVERAGE"
  grep -qi 'receipt line' "$COVERAGE"
}
