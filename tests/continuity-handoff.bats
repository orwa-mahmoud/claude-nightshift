#!/usr/bin/env bats
# Continuity handoff — cross-host packages, fencing, campaigns.

ROOT="$BATS_TEST_DIRNAME/.."
CH="$ROOT/plugins/nightshift/runtime/continuity-handoff.sh"
FIX="$ROOT/tests/fixtures/continuity"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
STATUS="$ROOT/plugins/nightshift/skills/status/SKILL.md"
DOCTOR="$ROOT/plugins/nightshift/skills/doctor/SKILL.md"

@test "continuity-handoff script is executable" {
  [ -x "$CH" ]
}

@test "handoff-package includes required continuity fields" {
  run bash "$CH" handoff-package --input "$FIX/handoff-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.complete == true and .priorHost == "claude"' >/dev/null
  printf '%s' "$output" | jq -e '.evidenceLocators | length >= 1' >/dev/null
}

@test "handoff-package reports missing fields honestly" {
  run bash "$CH" handoff-package --input "$FIX/handoff-incomplete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.complete == false and (.missingFields | length) >= 3' >/dev/null
}

@test "fence-check allows takeover only after prior owner fenced" {
  run bash "$CH" fence-check --input "$FIX/fence-ok.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == true and .twoActiveWorkersAllowed == false' >/dev/null
  run bash "$CH" fence-check --input "$FIX/fence-refused.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == false and .duplicateWorkerRejected == true' >/dev/null
}

@test "campaign-sequence requires prior night archived before next begins" {
  run bash "$CH" campaign-sequence --input "$FIX/campaign-pending.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.valid == false and .nextMayBegin == false' >/dev/null
  run bash "$CH" campaign-sequence --input "$FIX/campaign-valid.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.valid == true and .dispatcherRuntime == false' >/dev/null
}

@test "transition-history redacts secrets for status and doctor" {
  run bash "$CH" transition-history --input "$FIX/transition-history.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.exposeSecrets == false and (.events | length) == 2' >/dev/null
}

@test "start status and doctor skills reference continuity handoff" {
  grep -qF 'continuity-handoff.sh handoff-package' "$START"
  grep -qF 'continuity-handoff.sh fence-check' "$START"
  grep -qF 'continuity-handoff.sh transition-history' "$STATUS"
  grep -qF 'continuity-handoff.sh transition-history' "$DOCTOR"
}
