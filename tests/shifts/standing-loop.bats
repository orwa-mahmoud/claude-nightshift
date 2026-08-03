E="$BATS_TEST_DIRNAME/../../skills/nightshift/references/shifts/standing-loop.md"

@test "the standing loop ends only at the deadline, never by convergence" {
  grep -qi 'deadline is the ONLY thing' "$E"
  grep -qiE 'too shallow' "$E"
}

@test "the standing loop runs the quality tooling at site inspections" {
  grep -qi 'site inspection' "$E"
  grep -qi 'report mode' "$E"
}
