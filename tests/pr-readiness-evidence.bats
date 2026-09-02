#!/usr/bin/env bats
# Pull-request readiness evidence — acceptance map, diff scope, review map, owner refusals.

ROOT="$BATS_TEST_DIRNAME/.."
PR="$ROOT/plugins/nightshift/runtime/pr-readiness-evidence.sh"
FIX="$ROOT/tests/fixtures/pr-readiness"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/pr-readiness-evidence.json"

@test "pr-readiness script is executable" {
  [ -x "$PR" ]
}

@test "acceptance-map marks ready branch with met criteria and no agent approval" {
  run bash "$PR" acceptance-map --input "$FIX/acceptance-ready.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "acceptance-map"' >/dev/null
  printf '%s' "$output" | jq -e '.verdict == "ready-for-human-review"' >/dev/null
  printf '%s' "$output" | jq -e '.agentApprovalAllowed == false and .humanDecisionSurface == true' >/dev/null
  printf '%s' "$output" | jq -e '.acceptanceCriteria | map(select(.met)) | length == 2' >/dev/null
}

@test "acceptance-map blocks missing issue, failed CI, and unresolved review comments" {
  run bash "$PR" acceptance-map --input "$FIX/acceptance-blocked.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "not-ready"' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="issue")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="ci")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="review-comment")] | length == 1' >/dev/null
}

@test "acceptance-map routes artifact mode and ambiguous criteria elsewhere" {
  run bash "$PR" acceptance-map --input "$FIX/acceptance-artifact-route.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.routes[] | select(.route=="artifact-review")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.routes[] | select(.route=="ambiguous-criterion")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="work-mode")] | length == 1' >/dev/null
}

@test "diff-scope separates in-scope changes from unrelated and dirty work" {
  run bash "$PR" diff-scope --input "$FIX/diff-scope-clean.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.scopedClean == true and (.inScope | length) == 3' >/dev/null
  printf '%s' "$output" | jq -e '(.outOfScope | length) == 0' >/dev/null

  run bash "$PR" diff-scope --input "$FIX/diff-scope-dirty.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.scopedClean == false and .dirtyWorktree == true' >/dev/null
  printf '%s' "$output" | jq -e '[.outOfScope[] | select(. == "docs/unrelated-refactor.md")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="unrelated")] | length == 1' >/dev/null
}

@test "review-map records changed areas, risks, commits, and finite ending" {
  run bash "$PR" review-map --input "$FIX/review-map-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "review-map"' >/dev/null
  printf '%s' "$output" | jq -e '.finiteEndingReached == true and .openFindings == 0' >/dev/null
  printf '%s' "$output" | jq -e '(.changedAreas | length) == 3 and (.commits | length) == 2' >/dev/null
  printf '%s' "$output" | jq -e '(.remainingRisks | length) == 1 and (.unsupportedSurfaces | length) == 1' >/dev/null
  printf '%s' "$output" | jq -e '.shiftLogLine | test("branch feat/add-webhook-retries")' >/dev/null
  printf '%s' "$output" | jq -e '.agentApprovalAllowed == false' >/dev/null
}

@test "review-map stays open when findings or containing checks fail" {
  run bash "$PR" review-map --input "$FIX/review-map-open.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.finiteEndingReached == false and .openFindings >= 1' >/dev/null
  printf '%s' "$output" | jq -e '.containingChecksGreen == false' >/dev/null
}

@test "owner-action-refusal blocks approve and push without authority" {
  run bash "$PR" owner-action-refusal --input "$FIX/refusal-approve.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.refused == true and .requestedAction == "approve"' >/dev/null
  printf '%s' "$output" | jq -e '.reason | test("never approves")' >/dev/null
  printf '%s' "$output" | jq -e '.writeBackAllowed == false' >/dev/null

  run bash "$PR" owner-action-refusal --input "$FIX/refusal-push.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.refused == true and .requestedAction == "push"' >/dev/null
}

@test "pr-readiness outputs validate against schema" {
  for pair in \
    "acceptance-map:$FIX/acceptance-ready.json" \
    "acceptance-map:$FIX/acceptance-blocked.json" \
    "diff-scope:$FIX/diff-scope-clean.json" \
    "review-map:$FIX/review-map-complete.json" \
    "owner-action-refusal:$FIX/refusal-approve.json"; do
    cmd="${pair%%:*}"
    f="${pair#*:}"
    out="$BATS_TEST_TMPDIR/$cmd-$(basename "$f").json"
    bash "$PR" "$cmd" --input "$f" >"$out"
    python3 "$SCHEMA_PY" "$SCHEMA" "$out" \
      || { echo "schema failed: $cmd $f"; return 1; }
  done
}

@test "pull-request readiness contract references the helper" {
  grep -qF 'runtime/pr-readiness-evidence.sh acceptance-map' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"
  grep -qF 'runtime/pr-readiness-evidence.sh review-map' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"
  grep -qF 'runtime/pr-readiness-evidence.sh diff-scope' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"
  grep -qF 'runtime/pr-readiness-evidence.sh owner-action-refusal' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"
}
