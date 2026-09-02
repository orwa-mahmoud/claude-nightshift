#!/usr/bin/env bats
# Specialist and product journey evidence — journey modes, gates, and specialist fixtures.

ROOT="$BATS_TEST_DIRNAME/.."
SE="$ROOT/plugins/nightshift/runtime/specialist-evidence.sh"
FIX="$ROOT/tests/fixtures/specialist-evidence"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/specialist-evidence.json"

@test "specialist-evidence script is executable" {
  [ -x "$SE" ]
}

@test "journey-map validates a complete journey with browser evidence" {
  run bash "$SE" journey-map --input "$FIX/journey-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "journey-map" and .ready == true' >/dev/null
  printf '%s' "$output" | jq -e '.wholeProductCertificationAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '(.steps | length) == 3' >/dev/null
}

@test "journey-map records unavailable browser for responsive mode" {
  run bash "$SE" journey-map --input "$FIX/journey-no-browser.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ready == false and .platformClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '[.unavailableSurfaces[] | select(.surface | startswith("browser"))] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="browser")] | length == 1' >/dev/null
}

@test "journey-map accepts error-experience mode with recovery states" {
  run bash "$SE" journey-map --input "$FIX/journey-error-mode.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.evidenceMode == "error-experience" and .ready == true' >/dev/null
}

@test "journey-gap separates actionable from parked gaps" {
  run bash "$SE" journey-gap --input "$FIX/journey-gaps.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.actionableCount == 1' >/dev/null
  printf '%s' "$output" | jq -e '.wholeProductCertificationAllowed == false' >/dev/null
}

@test "journey-retest reports finite ending when all gaps pass" {
  run bash "$SE" journey-retest --input "$FIX/journey-retest-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.journeyComplete == true and .openCount == 0' >/dev/null
  printf '%s' "$output" | jq -e '.shiftLogLine | test("2/2 passed")' >/dev/null
}

@test "specialist-gate refuses automatic backup-restore without authority" {
  run bash "$SE" specialist-gate --input "$FIX/gate-backup-refused.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.selectable == false and .automaticAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.missingEvidence | index("disposableEnvironment")' >/dev/null
}

@test "specialist-gate allows guided product analytics with export scope" {
  run bash "$SE" specialist-gate --input "$FIX/gate-analytics-ok.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.selectable == true and .causalClaimAllowed == false' >/dev/null
}

@test "architecture-findings rejects taste-only rows and blocks direct edit in review-first" {
  run bash "$SE" architecture-findings --input "$FIX/architecture-findings.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.acceptedCount == 1 and .directEditAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.architecturalTastePresentedAsProof == false' >/dev/null
}

@test "data-quality-map rejects business rules inferred from types" {
  run bash "$SE" data-quality-map --input "$FIX/data-quality.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ready == false and .businessRuleInferenceAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="inference")] | length == 1' >/dev/null
}

@test "supply-chain-posture inventories evidence without legal conclusions" {
  run bash "$SE" supply-chain-posture --input "$FIX/supply-chain.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.legalConclusionAllowed == false and .ready == true' >/dev/null
}

@test "analytics-investigation defines metrics and forbids causal claims" {
  run bash "$SE" analytics-investigation --input "$FIX/analytics-investigation.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ready == true and .causalClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.dashboardBuildingAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '(.confounders | length) == 2' >/dev/null
}

@test "content-architecture routes under documentation drift parent" {
  run bash "$SE" content-architecture --input "$FIX/content-architecture.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.parentContract == "documentation-drift"' >/dev/null
  printf '%s' "$output" | jq -e '(.staleOrOrphan | length) == 1' >/dev/null
}

@test "maintainer-health-preset composes existing contracts without catalog sprawl" {
  run bash "$SE" maintainer-health-preset --input "$FIX/maintainer-health.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.selectable == true and .catalogSprawl == false' >/dev/null
  printf '%s' "$output" | jq -e '(.presetContracts | length) == 4' >/dev/null
}

@test "specialist-evidence outputs validate against schema" {
  for pair in \
    "journey-map:$FIX/journey-complete.json" \
    "journey-gap:$FIX/journey-gaps.json" \
    "specialist-gate:$FIX/gate-analytics-ok.json" \
    "architecture-findings:$FIX/architecture-findings.json" \
    "analytics-investigation:$FIX/analytics-investigation.json" \
    "maintainer-health-preset:$FIX/maintainer-health.json"; do
    cmd="${pair%%:*}"
    f="${pair#*:}"
    out="$BATS_TEST_TMPDIR/$cmd-$(basename "$f").json"
    bash "$SE" "$cmd" --input "$f" >"$out"
    python3 "$SCHEMA_PY" "$SCHEMA" "$out" \
      || { echo "schema failed: $cmd $f"; return 1; }
  done
}

@test "product journey contract references journey helpers and modes" {
  grep -qF 'runtime/specialist-evidence.sh journey-map' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
  grep -qF 'runtime/specialist-evidence.sh journey-gap' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
  grep -qF 'runtime/specialist-evidence.sh journey-retest' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
  grep -qi 'Error experience' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
  grep -qi 'Responsive / cross-browser' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
  grep -qi 'Accessibility journey' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/product-journey.md"
}

@test "parent contracts reference specialist modes without new menu entries" {
  grep -qF 'runtime/specialist-evidence.sh content-architecture' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/documentation-drift.md"
  grep -qF 'runtime/specialist-evidence.sh analytics-investigation' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/research-synthesis.md"
  grep -qF 'runtime/specialist-evidence.sh data-quality-map' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/clear-quality-debt.md"
  grep -qF 'runtime/specialist-evidence.sh supply-chain-posture' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/vulnerability-sweep.md"
}
