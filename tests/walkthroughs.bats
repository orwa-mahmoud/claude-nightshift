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

@test "hunt writes the order and its hours to work-orders.md" {
  grep -q 'work-orders.md' "$HUNT"
  grep -q 'Hours:' "$HUNT"
  grep -qi 'never clobber' "$HUNT"
}

@test "hunt cuts into the punch list only on a yes" {
  grep -qi 'start now' "$HUNT"
  grep -qi 'cut' "$HUNT"
  grep -q 'punch-list.md' "$HUNT"
  grep -qi 'explicit yes' "$HUNT"
}

@test "the cut arms the deadline from the recorded hours" {
  grep -q 'hours\*3600' "$HUNT"
  grep -qi 'clock starts only at the cut' "$HUNT"
}

@test "start offers pending work orders and setup scaffolds the file" {
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../commands/start.md"
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../commands/setup.md"
}
