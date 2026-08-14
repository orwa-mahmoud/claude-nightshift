E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/todo-fixme-debt.md"

@test "TODO debt inventories tracked human-authored markers" {
  grep -qi 'tracked, human-authored' "$E"
  grep -qi 'TODO, FIXME, HACK, and XXX' "$E"
  grep -qi 'generated, vendored' "$E"
}

@test "TODO debt distinguishes actionable work from decisions" {
  grep -qi 'Actionable means' "$E"
  grep -qi 'Ambiguous means' "$E"
  grep -qi 'underlying work' "$E"
}

@test "TODO debt stages ambiguity and refuses invented features" {
  grep -qi 'drafting-table.md' "$E"
  grep -qi 'do not guess the answer' "$E"
  grep -qi 'Never invent a feature' "$E"
  grep -qi 'Never delete or reword a marker' "$E"
}

@test "TODO debt has a verifiable finite ending" {
  grep -qi 'Ends when every discovered marker' "$E"
  grep -qi 'item gate is green at every commit' "$E"
  grep -qi 'final scoped search' "$E"
}
