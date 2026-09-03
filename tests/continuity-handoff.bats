#!/usr/bin/env bats
# Continuity handoff — cross-host packages, fencing, campaigns.

load helpers

ROOT="$BATS_TEST_DIRNAME/.."
CH="$ROOT/plugins/nightshift/runtime/continuity-handoff.sh"
FIX="$ROOT/tests/fixtures/continuity"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
STATUS="$ROOT/plugins/nightshift/skills/status/SKILL.md"
DOCTOR="$ROOT/plugins/nightshift/skills/doctor/SKILL.md"
LIB="$ROOT/plugins/nightshift/lib/lib.sh"

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

@test "fence-check without a lease refuses and ignores model JSON flags" {
  run bash "$CH" fence-check --input "$FIX/fence-ok.json"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == false and .action == "refuse"' >/dev/null
  run bash "$CH" fence-check --input "$FIX/fence-refused.json"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == false' >/dev/null

  p="$(new_project)"
  punch_open "$p"
  run bash "$CH" fence-check --project "$p"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == false and .action == "refuse"' >/dev/null
}

@test "fence-check allows takeover only when the on-disk lease is fenced" {
  p="$(new_project)"
  punch_open "$p"
  bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" shift-session claude' \
    nightshift "$LIB" "$p" >/dev/null
  run bash "$CH" fence-check --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == true and .priorOwnerFenced == true and .twoActiveWorkersAllowed == false' >/dev/null

  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'shift-session\nclaude\n1\n\n%s\n%s\n' "$$" "$start" >"$p/.nightshift/.shift-lease"
  run bash "$CH" fence-check --project "$p" --input "$FIX/fence-ok.json"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e '.takeoverAllowed == false and .priorWorkerActive == true' >/dev/null
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
  grep -qF 'runtime/continuity-handoff.sh" fence-check --project' "$START"
  grep -qF 'continuity-handoff.sh handoff-package' "$START"
  grep -qF 'runtime/continuity-handoff.sh" transition-history' "$STATUS"
  grep -qF 'continuity-handoff.sh transition-history' "$DOCTOR"
}
