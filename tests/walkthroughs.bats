WALK="$BATS_TEST_DIRNAME/../skills/nightshift/references/walkthrough-item.md"
HUNT="$BATS_TEST_DIRNAME/../commands/hunt.md"

@test "the template ships all three presets" {
  grep -q '^## Coverage hunt' "$WALK"
  grep -q '^## Defect hunt' "$WALK"
  grep -q '^## Standing loop' "$WALK"
}

@test "the standing loop ends only at the deadline, never by convergence" {
  grep -qi 'deadline is the ONLY thing' "$WALK"
  grep -qiE 'too shallow' "$WALK"
}

@test "the standing loop runs the quality tooling at site inspections" {
  grep -qi 'site inspection' "$WALK"
  grep -qi 'report mode' "$WALK"
}

@test "hunt stages to the drafting table and never clobbers existing drafts" {
  grep -q 'drafting-table.md' "$HUNT"
  grep -qi 'never clobber' "$HUNT"
  grep -qi 'stay untouched' "$HUNT"
}

@test "hunt promotes only on the owner's word" {
  grep -qi 'promote' "$HUNT"
  grep -qi 'explicit yes' "$HUNT"
  grep -q 'punch-list.md' "$HUNT"
}

@test "hunt points at the mandatory walkthrough deadline" {
  grep -qi 'demands hours' "$HUNT"
}
