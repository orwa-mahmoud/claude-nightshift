E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/maintainer-health.md"

@test "maintainer health resolves a preset without catalog sprawl" {
  grep -qF 'runtime/specialist-evidence.sh maintainer-health-preset' "$E"
  grep -qi 'preset composes existing catalog contracts' "$E"
  grep -qi 'Never add new catalog entries' "$E"
}

@test "maintainer health wires onboarding docs CI and release helpers" {
  grep -qF 'runtime/build-onboarding-evidence.sh onboarding-journey' "$E"
  grep -qF 'runtime/product-truth-evidence.sh doc-claim-matrix' "$E"
  grep -qF 'runtime/engineering-evidence.sh ci-warnings' "$E"
  grep -qF 'runtime/release-readiness-evidence.sh public-claims-matrix' "$E"
}

@test "maintainer health never claims release authority" {
  grep -qi 'never publishes, merges, or claims human release acceptance' "$E"
  grep -qi 'Never select this entry when work mode is artifact' "$E"
}

@test "maintainer health is finite and gates commits" {
  grep -qi 'Ends when every available preset segment' "$E"
  grep -qi 'item gate is green at every commit' "$E"
}
