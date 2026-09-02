#!/usr/bin/env bats
# Build and onboarding evidence — reproducibility, journey, prerequisites.

ROOT="$BATS_TEST_DIRNAME/.."
BO="$ROOT/plugins/nightshift/runtime/build-onboarding-evidence.sh"
FIX="$ROOT/tests/fixtures/build-onboarding"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/build-onboarding-evidence.json"

@test "build-onboarding script is executable" {
  [ -x "$BO" ]
}

@test "repro-compare marks clean cold runs reproducible" {
  run bash "$BO" repro-compare --input "$FIX/repro-clean.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "repro-compare" and .verdict == "reproducible"' >/dev/null
  printf '%s' "$output" | jq -e '.cleanRoomClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '[.comparisons[] | select(.match == false)] | length == 0' >/dev/null
}

@test "repro-compare detects cache-dependent digests" {
  run bash "$BO" repro-compare --input "$FIX/repro-cache-dependent.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "cache-dependent"' >/dev/null
  printf '%s' "$output" | jq -e '[.hiddenAssumptions[] | select(.kind=="cache")] | length >= 1' >/dev/null
}

@test "repro-compare skips generated outputs and flags package gaps" {
  run bash "$BO" repro-compare --input "$FIX/repro-monorepo.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.comparisons[] | select(.path | test("bundle.map")) | .action] | first == "skip-compare"' >/dev/null
  printf '%s' "$output" | jq -e '.verdict == "package-gap"' >/dev/null
  printf '%s' "$output" | jq -e '[.missingFromPackage[] | select(. == "packages/api/dist/server.js")] | length == 1' >/dev/null
}

@test "repro-compare refuses imposed stack and owner-only installs" {
  run bash "$BO" repro-compare --input "$FIX/repro-owner-only.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.imposedStackRefused == true' >/dev/null
  printf '%s' "$output" | jq -e '[.ownerOnlyActions[] | select(.action=="refuse")] | length >= 1' >/dev/null
}

@test "onboarding journey completes with fresh-reader pass required" {
  run bash "$BO" onboarding-journey --input "$FIX/onboarding-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "onboarding-journey" and .journeyComplete == true' >/dev/null
  printf '%s' "$output" | jq -e '.freshReaderPassRequired == true and .cleanRoomClaimAllowed == false' >/dev/null
}

@test "onboarding journey records broken commands and fresh-reader issues" {
  run bash "$BO" onboarding-journey --input "$FIX/onboarding-broken-command.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.journeyComplete == false and .ending == "repair-needed"' >/dev/null
  printf '%s' "$output" | jq -e '[.brokenCommands[] | select(.action=="document-prerequisite")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.freshReaderIssues[] | select(.issue | test("secret file"))] | length >= 1' >/dev/null
}

@test "onboarding journey stops on exact environmental blockers" {
  run bash "$BO" onboarding-journey --input "$FIX/onboarding-blocked-platform.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ending == "blocked" and .humanDecisionRequired == true' >/dev/null
  printf '%s' "$output" | jq -e '[.environmentalBlockers[] | select(.reason=="unsupported platform")] | length >= 1' >/dev/null
}

@test "prerequisite map documents missing prerequisites and broken commands" {
  run bash "$BO" prerequisite-map --input "$FIX/prerequisite-missing.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "prerequisite-map" and .neverImposeStack == true' >/dev/null
  printf '%s' "$output" | jq -e '[.missingPrerequisites[] | select(.name=="libpq")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.brokenCommands[] | select(.command=="npm run setup")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.ownerOnlyInstalls[] | select(.name=="docker")] | length >= 1' >/dev/null
}

@test "prerequisite map parks unsupported platforms" {
  run bash "$BO" prerequisite-map --input "$FIX/prerequisite-unsupported-platform.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.platformSupport.supported == false' >/dev/null
  printf '%s' "$output" | jq -e '.humanDecisionRequired == true' >/dev/null
}

@test "build-onboarding outputs validate against schema" {
  for pair in \
    "repro-compare:$FIX/repro-clean.json" \
    "onboarding-journey:$FIX/onboarding-complete.json" \
    "prerequisite-map:$FIX/prerequisite-missing.json"; do
    cmd="${pair%%:*}"
    f="${pair#*:}"
    out="$BATS_TEST_TMPDIR/$cmd.json"
    bash "$BO" "$cmd" --input "$f" >"$out"
    python3 "$SCHEMA_PY" "$SCHEMA" "$out" \
      || { echo "schema failed: $cmd"; return 1; }
  done
}

@test "build and onboarding contracts reference the helper" {
  grep -qF 'runtime/build-onboarding-evidence.sh repro-compare' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/build-reproducibility.md"
  grep -qF 'runtime/build-onboarding-evidence.sh onboarding-journey' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/developer-onboarding.md"
  grep -qF 'runtime/build-onboarding-evidence.sh prerequisite-map' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/developer-onboarding.md"
}
