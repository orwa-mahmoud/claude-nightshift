#!/usr/bin/env bats
# Release-readiness evidence — baseline compare, public claims, verdict, unmeasured surfaces.

ROOT="$BATS_TEST_DIRNAME/.."
RR="$ROOT/plugins/nightshift/runtime/release-readiness-evidence.sh"
FIX="$ROOT/tests/fixtures/release-readiness"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/release-readiness-evidence.json"

@test "release-readiness script is executable" {
  [ -x "$RR" ]
}

@test "baseline compare detects regressions across tests API package install security" {
  run bash "$RR" baseline-compare --input "$FIX/baseline-compare-named.json"
  [ "$status" -eq 0 ]
  python3 "$SCHEMA_PY" "$SCHEMA" /dev/stdin <<<"$output"
  printf '%s' "$output" | jq -e '.baselinePresent == true and .baselineRef == "v1.2.0"' >/dev/null
  printf '%s' "$output" | jq -e '[.regressions[] | select(.reason=="test-regression")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.regressions[] | select(.reason=="breaking-api-change")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.regressions[] | select(.reason=="install-smoke-failed")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.regressions[] | select(.reason=="new-security-advisories")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '.provenancePreserved == true' >/dev/null
}

@test "baseline compare parks when baseline ref or artifacts are missing" {
  run bash "$RR" baseline-compare --input "$FIX/baseline-compare-missing.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.baselinePresent == false and .action == "park"' >/dev/null
  printf '%s' "$output" | jq -e '.error == "missing-baseline-ref"' >/dev/null
}

@test "baseline compare honors package exclusions and notes digest drift" {
  run bash "$RR" baseline-compare --input "$FIX/package-exclusion-drift.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.drift[] | select(.dimension=="package" and .digestChanged==true)] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.regressions[] | select(.dimension=="package")] | length == 0' >/dev/null
}

@test "public claims matrix repairs mechanical drift and parks positioning legal" {
  run bash "$RR" public-claims-matrix --input "$FIX/public-claims.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.parkPositioningLegal == true and .networkQueryAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '[.rows[] | select(.mechanicalDrift==true and .action=="repair")] | length >= 2' >/dev/null
  printf '%s' "$output" | jq -e '[.rows[] | select(.surfaceType=="positioning" and .action=="park")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.rows[] | select(.surfaceType=="privacy" and .action=="park")] | length == 1' >/dev/null
}

@test "verdict emits ready not-ready and conditionally-ready without human acceptance" {
  run bash "$RR" verdict --input "$FIX/verdict-ready.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "ready"' >/dev/null
  run bash "$RR" verdict --input "$FIX/verdict-not-ready.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "not-ready"' >/dev/null
  run bash "$RR" verdict --input "$FIX/verdict-conditionally-ready.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "conditionally-ready"' >/dev/null
  printf '%s' "$output" | jq -e '.neverPublish == true and .humanAcceptanceClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.greenCiIsCompleteEvidence == false and .nightshiftVerdictIsHumanAcceptance == false' >/dev/null
}

@test "unmeasured surfaces records environment provenance" {
  run bash "$RR" unmeasured-surfaces --input "$FIX/unmeasured-surfaces.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.count == 3' >/dev/null
  printf '%s' "$output" | jq -e '[.surfaces[] | select(.environment=="production")] | length == 1' >/dev/null
}

@test "release readiness contract references release-readiness helper" {
  grep -qF 'runtime/release-readiness-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/release-readiness.md"
}
