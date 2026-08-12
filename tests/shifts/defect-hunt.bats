E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/defect-hunt.md"

@test "defect hunt deduplicates every finding against the snag log" {
  grep -qi 'snag-log.md' "$E"
  grep -qi 'ALL seen' "$E"
  grep -qi 'never re-reports' "$E"
}

@test "defect hunt fixes behind the gate and records dispositions" {
  grep -qi 'fix each behind the item gate' "$E"
  grep -qi 'append dispositions' "$E"
}

@test "defect hunt ends at convergence or quitting time" {
  grep -qi 'nothing NEW' "$E"
  grep -qi 'quitting time' "$E"
  grep -qi 'Zero new findings is success' "$E"
}

@test "defect hunt verifies every commit" {
  grep -qi 'item gate is green at every commit' "$E"
}
