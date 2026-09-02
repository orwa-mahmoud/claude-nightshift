#!/usr/bin/env bats
# History context — receipt index, comparison, presets, adapters.

ROOT="$BATS_TEST_DIRNAME/.."
HC="$ROOT/plugins/nightshift/runtime/history-context.sh"
FIX="$ROOT/tests/fixtures/history"
ARCHIVE="$ROOT/plugins/nightshift/skills/archive/SKILL.md"
SETUP="$ROOT/plugins/nightshift/skills/setup/SKILL.md"

@test "history-context script is executable" {
  [ -x "$HC" ]
}

@test "index-archive builds lightweight shift index without replay" {
  run bash "$HC" index-archive --input "$FIX/archive-index-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.entryCount == 2 and .replaySideEffects == false' >/dev/null
  printf '%s' "$output" | jq -e '.entries[0].contracts | index("clear-quality-debt")' >/dev/null
}

@test "index-archive degrades honestly on corrupt entries" {
  run bash "$HC" index-archive --input "$FIX/archive-corrupt.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.degradesHonestly == true and (.corruptEntries | length) == 1' >/dev/null
}

@test "compare-prior reuses locators without replaying side effects" {
  run bash "$HC" compare-prior --input "$FIX/compare-prior.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.replaySideEffects == false and .replayPlansOnly == true' >/dev/null
  printf '%s' "$output" | jq -e '.recurringFailures | index("no-console in tests")' >/dev/null
}

@test "preset-compose resolves rules and defaults with owner authority" {
  run bash "$HC" preset-compose --input "$FIX/preset-compose.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ownerRulesAuthoritative == true' >/dev/null
  printf '%s' "$output" | jq -e '.resolved.verificationProfile == "balanced"' >/dev/null
}

@test "preset-compose refuses hidden policy capture" {
  run bash "$HC" preset-compose --input "$FIX/preset-hidden-refused.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.presetNeverCapturesHiddenPolicy == false' >/dev/null
}

@test "audience-render produces reviewer handoff from one evidence truth" {
  run bash "$HC" audience-render --input "$FIX/audience-reviewer.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.audience == "reviewer" and .singleEvidenceTruth == true' >/dev/null
  printf '%s' "$output" | jq -e '.sections.reviewMap.open == 1' >/dev/null
}

@test "adapter-boundary keeps scope from silently broadening" {
  run bash "$HC" adapter-boundary --input "$FIX/adapter-boundary.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.scopeBroadeningAllowed == false and .mandatoryConnector == false' >/dev/null
  printf '%s' "$output" | jq -e '.optionalIntegration == true' >/dev/null
}

@test "archive and setup skills reference history-context helper" {
  grep -qF 'history-context.sh index-archive' "$ARCHIVE"
  grep -qF 'history-context.sh preset-compose' "$SETUP"
}
