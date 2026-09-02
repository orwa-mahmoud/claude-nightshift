#!/usr/bin/env bats
# Evidence-ranked quality workflow — scan, normalize, dedupe, rank, compose.

ROOT="$BATS_TEST_DIRNAME/.."
SCAN="$ROOT/plugins/nightshift/runtime/quality-scan.sh"
WORKFLOW="$ROOT/plugins/nightshift/runtime/quality-workflow.sh"
PLANNER="$ROOT/plugins/nightshift/runtime/shift-planner.sh"
EV="$ROOT/plugins/nightshift/runtime/evidence.sh"
EC="$ROOT/plugins/nightshift/runtime/evidence-compare.sh"
FIX="$ROOT/tests/fixtures/quality/monorepo-dedupe"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
Q_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/quality-scan.json"
QUALITY_SKILL="$ROOT/plugins/nightshift/skills/quality/SKILL.md"
CLEAR="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/clear-quality-debt.md"

load helpers

@test "quality workflow scripts are executable" {
  [ -x "$SCAN" ]
  [ -x "$WORKFLOW" ]
}

@test "monorepo fixture pipeline dedupes cross-tool root causes" {
  run bash "$WORKFLOW" pipeline --manifest "$FIX/manifest.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.dedupeSummary.inputCount == 3 and .dedupeSummary.outputCount == 2' >/dev/null
  printf '%s' "$output" | jq -e '.dedupeSummary.groups | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '.queue[0].sources | index("eslint") and index("check-imports")' >/dev/null
  printf '%s' "$output" | jq -e '.sources | map(select(.unavailable==true)) | length == 1' >/dev/null
}

@test "quality scan result validates against schema" {
  scan="$BATS_TEST_TMPDIR/scan.json"
  bash "$WORKFLOW" pipeline --manifest "$FIX/manifest.json" >"$scan"
  python3 "$SCHEMA_PY" "$Q_SCHEMA" "$scan"
}

@test "ranked queue orders higher severity first" {
  run bash "$WORKFLOW" pipeline --manifest "$FIX/manifest.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.queue[0].severity == "high"' >/dev/null
  printf '%s' "$output" | jq -e '.queue[1].severity == "medium"' >/dev/null
}

@test "compose-discovery feeds the shift planner" {
  scan="$BATS_TEST_TMPDIR/scan.json"
  disc="$BATS_TEST_TMPDIR/discovery.json"
  bash "$WORKFLOW" pipeline --manifest "$FIX/manifest.json" >"$scan"
  bash "$WORKFLOW" compose-discovery --scan "$scan" --hours 4 >"$disc"
  run bash "$PLANNER" --input "$disc" --hours 4 --selection automatic --launch review-first
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.orderedItems[0].contractId == "clear-quality-debt"' >/dev/null
}

@test "findings append to the evidence ledger" {
  p="$(new_project quality-evidence)"
  mkdir -p "$p/.nightshift/evidence"
  scan="$BATS_TEST_TMPDIR/scan.json"
  bash "$WORKFLOW" pipeline --manifest "$FIX/manifest.json" >"$scan"
  n=0
  jq -c '.findings[]' "$scan" | while read -r rec; do
    run bash "$EV" --project "$p" append --record "$rec"
    [ "$status" -eq 0 ] || return 1
    n=$((n + 1))
  done
  [ "$(wc -l <"$p/.nightshift/evidence/findings.jsonl" | tr -d ' ')" -eq 2 ]
}

@test "Quality skill references the workflow helpers" {
  grep -qF 'runtime/quality-workflow.sh' "$QUALITY_SKILL"
  grep -qF 'runtime/quality-scan.sh' "$QUALITY_SKILL"
}

@test "clear-quality-debt contract mentions evidence-ranked workflow" {
  grep -qi 'evidence' "$CLEAR"
  grep -qi 'baseline' "$CLEAR"
  grep -qi 'dedupe' "$CLEAR"
}
