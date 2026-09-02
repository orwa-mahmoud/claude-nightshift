E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/pull-request-readiness.md"

@test "PR readiness uses pr-readiness evidence helpers" {
  grep -qF 'pr-readiness-evidence.sh acceptance-map' "$E"
  grep -qF 'review-map' "$E"
  grep -qF 'owner-action-refusal' "$E"
}

@test "PR readiness refuses owner-only git actions" {
  grep -qi 'Never' "$E" || grep -qi 'never submit' "$E"
  grep -qi 'push' "$E"
  grep -qi 'merge' "$E"
  grep -qi 'approve' "$E"
}

@test "PR readiness is finite and repository scoped" {
  grep -qi 'Ends when every scoped gap' "$E"
  grep -qi 'repository mode' "$E"
  grep -qi 'review map' "$E"
}

@test "PR readiness gates every commit" {
  grep -qi 'item gate' "$E"
}
