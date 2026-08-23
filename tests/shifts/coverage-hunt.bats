E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/coverage-hunt.md"

@test "coverage hunt chooses valuable untested behaviour" {
  grep -qi 'highest-value untested behaviour' "$E"
  grep -qi 'behavior-protecting tests' "$E"
}

@test "coverage hunt refuses padding and unexplained exclusions" {
  grep -qi 'tripwire, never a target' "$E"
  grep -qi 'no padding tests' "$E"
  grep -qi 'exclusion needs a written reason' "$E"
}

@test "coverage hunt is clock-bounded and leaves cycle receipts" {
  grep -qi 'Log one line per cycle' "$E"
  grep -qi 'Stop only at quitting time' "$E"
  grep -qi 'clock out orderly' "$E"
}

@test "coverage hunt gates every commit" {
  grep -qi 'item gate is green at every commit' "$E"
}
