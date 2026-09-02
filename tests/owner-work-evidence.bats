#!/usr/bin/env bats
# Owner-defined work evidence — imported issues, walkthrough planning, evolution hypotheses.

ROOT="$BATS_TEST_DIRNAME/.."
OW="$ROOT/plugins/nightshift/runtime/owner-work-evidence.sh"
FIX="$ROOT/tests/fixtures/owner-work"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/owner-work-evidence.json"

@test "owner-work script is executable" {
  [ -x "$OW" ]
}

@test "issue graph orders dependencies, groups shared roots, and rejects out-of-scope issues" {
  run bash "$OW" issue-graph --input "$FIX/issue-graph.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "issue-graph"' >/dev/null
  printf '%s' "$output" | jq -e '.importedOnly == true and .writeBackAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '
    .orderedIssues
    | index("https://github.com/acme/widgets/issues/20")
    < index("https://github.com/acme/widgets/issues/21")' >/dev/null
  printf '%s' "$output" | jq -e '[.orderedGroups[] | select(.sharedRoots | index("src/config"))] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.rejected[] | select(.reason=="flagged")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.rejected[] | select(.reason=="repo-mismatch")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.conflicts[] | select(.kind=="duplicate")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.selectedIssues[] | select(test("/issues/30$"))] | length == 0' >/dev/null
}

@test "walkthrough plan derives acceptance, checkpoints, and reversible defaults before cutting" {
  run bash "$OW" walkthrough-plan --input "$FIX/walkthrough-brief.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "walkthrough-plan"' >/dev/null
  printf '%s' "$output" | jq -e '.planBeforeCutting == true' >/dev/null
  printf '%s' "$output" | jq -e '.objective | test("payment webhook")' >/dev/null
  printf '%s' "$output" | jq -e '.acceptanceCriteria | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '.checkpoints | length >= 3' >/dev/null
  printf '%s' "$output" | jq -e '.reversibleDefaults | length >= 2' >/dev/null
  printf '%s' "$output" | jq -e '.timeFitPlan.units | length >= 1' >/dev/null
}

@test "evolution hypothesis records slices, rejected alternatives, and disproved areas" {
  run bash "$OW" evolution-hypothesis --input "$FIX/evolution-opportunity.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "evolution-hypothesis"' >/dev/null
  printf '%s' "$output" | jq -e '.hypothesis.user == "checkout operator"' >/dev/null
  printf '%s' "$output" | jq -e '.validatedSlice.maxMinutes == 45' >/dev/null
  printf '%s' "$output" | jq -e '.rejectedAlternatives | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.avoidAreas[] | select(.area | test("blocking retry"))] | length >= 1' >/dev/null
}

@test "receipt link ties issue to commit and verification without write-back" {
  run bash "$OW" receipt-link --input "$FIX/receipt-link.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "receipt-link"' >/dev/null
  printf '%s' "$output" | jq -e '.writeBackAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.traceability.closesHint == "Closes #12"' >/dev/null
  printf '%s' "$output" | jq -e '.shiftLogLine | test("issue #12")' >/dev/null
}

@test "owner-work outputs validate against schema" {
  for cmd in issue-graph walkthrough-plan evolution-hypothesis receipt-link; do
    case "$cmd" in
      issue-graph) f="$FIX/issue-graph.json" ;;
      walkthrough-plan) f="$FIX/walkthrough-brief.json" ;;
      evolution-hypothesis) f="$FIX/evolution-opportunity.json" ;;
      receipt-link) f="$FIX/receipt-link.json" ;;
    esac
    out="$BATS_TEST_TMPDIR/$cmd.json"
    bash "$OW" "$cmd" --input "$f" >"$out"
    python3 "$SCHEMA_PY" "$SCHEMA" "$out" \
      || { echo "schema failed: $cmd"; return 1; }
  done
}

@test "owner-defined shift contracts reference the helper" {
  grep -qF 'runtime/owner-work-evidence.sh issue-graph' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/github-issue-hunt.md"
  grep -qF 'runtime/owner-work-evidence.sh receipt-link' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/github-issue-hunt.md"
  grep -qF 'runtime/owner-work-evidence.sh walkthrough-plan' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/owner-walkthrough.md"
  grep -qF 'runtime/owner-work-evidence.sh evolution-hypothesis' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/standing-loop.md"
}
