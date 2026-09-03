#!/usr/bin/env bats
# Deterministic shift planner — Automatic time-fit selection and explainable twins.

ROOT="$BATS_TEST_DIRNAME/.."
PLANNER="$ROOT/plugins/nightshift/runtime/shift-planner.sh"
PREVIEW="$ROOT/plugins/nightshift/runtime/shift-preview.sh"
LEARNING="$ROOT/plugins/nightshift/runtime/plan-learning.sh"
FIX="$ROOT/tests/fixtures/planning/automatic-10h"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
PLAN_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/shift-plan.json"
DISC_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/plan-discovery.json"
LEARN_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/plan-learning.json"

load helpers

plan_core() {
  jq 'del(.launchMode)' "$1"
}

@test "planner scripts are executable" {
  [ -x "$PLANNER" ]
  [ -x "$PREVIEW" ]
  [ -x "$LEARNING" ]
}

@test "discovery and plan fixtures validate against schemas" {
  python3 "$SCHEMA_PY" "$DISC_SCHEMA" "$FIX/discovery.json"
  python3 "$SCHEMA_PY" "$PLAN_SCHEMA" "$FIX/expected-plan.json"
}

@test "Automatic 10h review-first and run-direct share the same ordered plan" {
  rf="$BATS_TEST_TMPDIR/plan-rf.json"
  rd="$BATS_TEST_TMPDIR/plan-rd.json"
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  printf '%s' "$output" >"$rf"
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch run-direct
  [ "$status" -eq 0 ]
  printf '%s' "$output" >"$rd"
  diff -u <(plan_core "$rf") <(plan_core "$rd")
  jq -e '.launchMode == "review-first"' "$rf" >/dev/null
  jq -e '.launchMode == "run-direct"' "$rd" >/dev/null
}

@test "Automatic 10h plan matches the golden fixture" {
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  diff -u <(plan_core "$FIX/expected-plan.json") <(plan_core <(printf '%s' "$output"))
}

@test "Automatic plan explains overlaps, finite-first ordering, and verification reserve" {
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.overlapsRemoved | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '.orderedItems | map(.contractId) == ["clear-quality-debt","vulnerability-sweep","documentation-drift","defect-hunt"]' >/dev/null
  printf '%s' "$output" | jq -e '.orderedItems | map(select(.ending=="finite")) | length == 3' >/dev/null
  printf '%s' "$output" | jq -e '.orderedItems | map(select(.ending=="open-ended")) | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '.verificationReserveMinutes == 60' >/dev/null
  printf '%s' "$output" | jq -e '(.estimateTotalMinutes + .verificationReserveMinutes) <= (.hours * 60)' >/dev/null
  printf '%s' "$output" | jq -e '.rejected | map(select(.reason=="overlap")) | length >= 1' >/dev/null
}

@test "planner exposes visible scoring inputs on every ordered item" {
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .orderedItems[] | .scoring | has("impact") and has("evidenceStrength")
      and has("confidence") and has("effortMinutes") and has("timeFit")
      and has("reversibility")' >/dev/null
}

@test "planner is read-only and creates no project files" {
  p="$(mktemp -d "${BATS_TEST_TMPDIR}/planner-ro.XXXXXX")"
  mkdir -p "$p/.nightshift"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  before="$(find "$p/.nightshift" -type f 2>/dev/null | sort | md5 2>/dev/null || find "$p/.nightshift" -type f | sort | cksum)"
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  after="$(find "$p/.nightshift" -type f 2>/dev/null | sort | md5 2>/dev/null || find "$p/.nightshift" -type f | sort | cksum)"
  [ "$before" = "$after" ]
}

@test "preview renders an explainable simulation without writing" {
  p="$(new_project planner-preview)"
  plan="$BATS_TEST_TMPDIR/plan.json"
  bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first >"$plan"
  before="$(find "$p/.nightshift" -type f | sort | md5 2>/dev/null || find "$p/.nightshift" -type f | sort | cksum)"
  run bash "$PREVIEW" --input "$plan"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Shift preview (read-only simulation)'
  printf '%s\n' "$output" | grep -qF 'Rejected alternatives'
  printf '%s\n' "$output" | grep -qF 'verification reserve'
  printf '%s\n' "$output" | grep -qF 'clear-quality-debt'
  after="$(find "$p/.nightshift" -type f | sort | md5 2>/dev/null || find "$p/.nightshift" -type f | sort | cksum)"
  [ "$before" = "$after" ]
}

@test "plan-learning updates from a receipt and adjusts later plans" {
  p="$(new_project planner-learning)"
  receipt="$BATS_TEST_TMPDIR/receipt.json"
  cat >"$receipt" <<'JSON'
{
  "contracts": [
    {"contractId": "documentation-drift", "actualDurationMinutes": 45, "outcome": "success"}
  ],
  "rejectedFindings": ["lint-src-unused-imports"]
}
JSON
  run bash "$LEARNING" --project "$p" update-from-receipt --receipt "$receipt"
  [ "$status" -eq 0 ]
  [ -f "$p/.nightshift/plan-learning.json" ]
  python3 "$SCHEMA_PY" "$LEARN_SCHEMA" "$p/.nightshift/plan-learning.json"
  learn="$p/.nightshift/plan-learning.json"
  run bash "$PLANNER" --input "$FIX/discovery.json" --hours 10 --selection automatic --launch review-first --learning "$learn"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.learningApplied == true' >/dev/null
  printf '%s' "$output" | jq -e '
    (.orderedItems[] | select(.contractId=="documentation-drift") | .scoring.effortMinutes) == 45' >/dev/null
}

@test "Hunt Automatic does not require the planner or preview helpers" {
  hunt="$ROOT/plugins/nightshift/skills/hunt/SKILL.md"
  ! grep -qF 'runtime/shift-planner.sh' "$hunt"
  ! grep -qF 'runtime/shift-preview.sh' "$hunt"
  ! grep -qF 'runtime/plan-learning.sh' "$hunt"
  grep -qF 'Do not call `shift-planner.sh`' "$hunt"
}

@test "Quality Automatic does not require the planner or preview helpers" {
  quality="$ROOT/plugins/nightshift/skills/quality/SKILL.md"
  ! grep -qF 'runtime/shift-planner.sh' "$quality"
  ! grep -qF 'runtime/shift-preview.sh' "$quality"
  ! grep -qF 'runtime/plan-learning.sh' "$quality"
  grep -qF 'Do not call `shift-planner.sh`' "$quality"
}
