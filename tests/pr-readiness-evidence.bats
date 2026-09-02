#!/usr/bin/env bats
# Pull-request readiness evidence helpers.

ROOT="$BATS_TEST_DIRNAME/.."
PR="$ROOT/plugins/nightshift/runtime/pr-readiness-evidence.sh"
FIX="$ROOT/tests/fixtures/pr-readiness"

@test "pr-readiness script is executable" {
  [ -x "$PR" ]
}

@test "acceptance-map tracks unmet criteria" {
  run bash "$PR" acceptance-map --input "$FIX/acceptance-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.unmetCount == 1 and .ready == false' >/dev/null
}

@test "diff-scope parks unrelated files" {
  run bash "$PR" diff-scope --input "$FIX/diff-scope-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "park-unrelated" and .unrelatedFileCount == 1' >/dev/null
}

@test "review-map lists dispositions and reviewer decisions" {
  run bash "$PR" review-map --input "$FIX/review-map-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.openCount >= 1 and (.reviewerDecisionsRequired | length) >= 1' >/dev/null
}

@test "owner-action-refusal blocks merge push and approve" {
  run bash "$PR" owner-action-refusal --input "$FIX/owner-actions-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.mayMerge == false and .mayPush == false and .mayApproveReview == false' >/dev/null
  printf '%s' "$output" | jq -e '.refused | length >= 3' >/dev/null
}

@test "pull-request-readiness contract references helper" {
  grep -qF 'runtime/pr-readiness-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"
}
