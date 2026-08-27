HUNT="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/hunt/SKILL.md"
QUALITY="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/quality/SKILL.md"
MODES="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/execution-modes.md"
SHIFTS="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts"

@test "tooling quality-debt entries are skipped in artifact mode" {
  for name in flaky-test-repair ci-warning-cleanup vulnerability-sweep \
    dead-code-cleanup dependency-upgrade-sweep api-contract-drift \
    accessibility-repair localization-parity; do
    e="$SHIFTS/${name}.md"
    grep -qi 'Never select this entry in artifact mode' "$e" \
      || { echo "missing artifact skip: $name"; return 1; }
    grep -qi 'Never select this entry when work mode is artifact' "$e" \
      || { echo "missing item skip: $name"; return 1; }
    grep -qF 'Do not `git init` a notes folder' "$e" \
      || { echo "missing git-init refusal: $name"; return 1; }
  done
  grep -qi 'Never select tooling quality-debt entries when work mode is artifact' "$HUNT"
  grep -qi 'Skip tooling quality-debt entries when work mode is artifact' "$QUALITY"
  grep -qi 'Skip tooling quality-debt entries when work mode is artifact' "$MODES"
}
