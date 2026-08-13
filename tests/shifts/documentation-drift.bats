E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/documentation-drift.md"

@test "documentation drift discovers local references against the tree" {
  grep -qi 'Discovery' "$E"
  grep -qi 'relative links' "$E"
  grep -qi 'Do not query the network' "$E"
}

@test "documentation drift refuses to invent commands or change product behaviour" {
  grep -qi 'Never invent a command' "$E"
  grep -qi 'Never change product behaviour' "$E"
  grep -qi 'Never rewrite positioning' "$E"
}

@test "documentation drift is finite and parks unverifiable third-party URLs" {
  grep -qi 'Ends when a full local pass' "$E"
  grep -qi 'third-party URL' "$E"
  grep -qi 'snag-log.md' "$E"
}

@test "documentation drift gates every commit" {
  grep -qi 'item gate is green at every commit' "$E"
}
