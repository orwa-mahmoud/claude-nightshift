#!/usr/bin/env bats
# Operational evidence — performance, incident, runbook, observability, toil, capacity.

ROOT="$BATS_TEST_DIRNAME/.."
OP="$ROOT/plugins/nightshift/runtime/operational-evidence.sh"
FIX="$ROOT/tests/fixtures/operational"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/operational-evidence.json"
PLANNER="$ROOT/plugins/nightshift/runtime/shift-planner.sh"

@test "operational-evidence script is executable" {
  [ -x "$OP" ]
}

@test "perf-compare detects regression from distributions not single runs" {
  run bash "$OP" perf-compare --input "$FIX/perf-regression.json"
  [ "$status" -eq 0 ]
  python3 "$SCHEMA_PY" "$SCHEMA" /dev/stdin <<<"$output"
  printf '%s' "$output" | jq -e '.verdict == "regression" and .regressionClaimAllowed == true' >/dev/null
  printf '%s' "$output" | jq -e '.baselineDistribution.count >= 2 and .candidateDistribution.count >= 2' >/dev/null
  printf '%s' "$output" | jq -e '.correctnessPreserved == true' >/dev/null
}

@test "perf-compare refuses faster or regression claims without baseline" {
  run bash "$OP" perf-compare --input "$FIX/perf-missing-baseline.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "unmeasured" and .fasterClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.regressionClaimAllowed == false and .action == "park"' >/dev/null
}

@test "perf-compare rejects single-run and correctness regression" {
  run bash "$OP" perf-compare --input "$FIX/perf-unstable-single-run.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.reasons[] | select(. == "single-run-not-a-distribution")] | length == 1' >/dev/null
  run bash "$OP" perf-compare --input "$FIX/perf-correctness-regression.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.reasons[] | select(. == "correctness-regression")] | length == 1' >/dev/null
}

@test "incident-actions separates repository owner and system actions" {
  run bash "$OP" incident-actions --input "$FIX/incident-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.inventedIncidentRefused == false' >/dev/null
  printf '%s' "$output" | jq -e '(.repositoryActions | length == 1) and (.ownerActions | length >= 1)' >/dev/null
  printf '%s' "$output" | jq -e '(.factors.root | length >= 1) and (.timelinePreserved == true)' >/dev/null
}

@test "incident-actions refuses invented incidents" {
  run bash "$OP" incident-actions --input "$FIX/incident-invented.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.inventedIncidentRefused == true and .action == "park"' >/dev/null
}

@test "runbook-verify parks production-only and refuses destructive steps" {
  run bash "$OP" runbook-verify --input "$FIX/runbook-mixed.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.destructiveEmergencyAllowed == false and .vendorImposed == false' >/dev/null
  printf '%s' "$output" | jq -e '.productionOnlySteps | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.refusedSteps[] | select(.reason=="destructive-emergency-step")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '.verifiedSteps | length >= 2' >/dev/null
}

@test "observability-surface records absent telemetry without assuming production" {
  run bash "$OP" observability-surface --input "$FIX/observability-mixed.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.telemetryInProductionAssumed == false' >/dev/null
  printf '%s' "$output" | jq -e '.absentCount >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.surfaces[] | select(.kind=="logs" and .measured==true)] | length == 1' >/dev/null
}

@test "toil-assess refuses one-time annoyances and false repetition" {
  run bash "$OP" toil-assess --input "$FIX/toil-mixed.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.oneTimeAutomateRefused == true and .falseRepetitionRefused == true' >/dev/null
  printf '%s' "$output" | jq -e '[.candidates[] | select(.action=="automate-bounded")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.candidates[] | select(.action=="refuse-automate")] | length == 1' >/dev/null
}

@test "capacity-guard refuses unsafe production load and budget exceedance" {
  run bash "$OP" capacity-guard --input "$FIX/capacity-unsafe.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.allowed == false and .productionLoadAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '[.reasons[] | select(. == "resource-budget-exceeded")] | length == 1' >/dev/null
  run bash "$OP" capacity-guard --input "$FIX/capacity-safe.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.allowed == true and .action == "proceed-bounded"' >/dev/null
}

@test "measured-summary states measured versus unmeasured rows" {
  run bash "$OP" measured-summary --input "$FIX/measured-summary.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.measuredCount == 1 and .unmeasuredCount == 2' >/dev/null
  printf '%s' "$output" | jq -e '.statesMeasuredVersusUnmeasured == true' >/dev/null
}

@test "planner rejects performance-regression when resource budget exceeded" {
  disc="$BATS_TEST_TMPDIR/operational-budget.json"
  cat >"$disc" <<'JSON'
{
  "schemaVersion": 1,
  "workMode": "repository",
  "workTarget": "/fixture/operational",
  "workspace": "/fixture/operational",
  "branch": "main",
  "toolingPolicy": "existing-tools",
  "authority": "owner-approved",
  "resourceBudgets": {"maxRps": 500},
  "overlaps": [],
  "candidates": [
    {
      "contractId": "performance-regression",
      "title": "Performance regression",
      "ending": "finite",
      "applicable": true,
      "evidence": ["owner supplied benchmark export"],
      "impact": 4,
      "evidenceStrength": 4,
      "confidence": 4,
      "effortMinutes": 120,
      "reversibility": 4,
      "dependencyValue": 2,
      "recurrence": 1,
      "priorResult": null,
      "prerequisites": [],
      "sharedRoots": [],
      "blockers": [],
      "capabilityStatus": "available-and-verified",
      "fallback": null,
      "resourceNeeds": {"maxRps": 5000},
      "risks": [],
      "unsupportedSurfaces": []
    }
  ]
}
JSON
  run bash "$PLANNER" --input "$disc" --hours 4 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.rejected[] | select(.contractId=="performance-regression" and .reason=="resource-budget")] | length == 1' >/dev/null
}

@test "operational contracts reference the helper" {
  for f in performance-regression incident-follow-up runbook-verification toil-reduction; do
    grep -qF 'runtime/operational-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/$f.md" \
      || { echo "missing helper reference: $f"; return 1; }
  done
}
