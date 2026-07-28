WALK="$BATS_TEST_DIRNAME/../skills/nightshift/references/walkthrough-item.md"
HUNT="$BATS_TEST_DIRNAME/../skills/hunt/SKILL.md"

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

# Both entry points into a live shift must clear the same leftovers. They drifted once: start
# cleared three markers, hunt's cut cleared none, so a spent deadline or a leftover STOP from
# last night silently ended the next shift at its first stop attempt.
@test "every path that starts a shift clears all five stale markers" {
  for f in start hunt; do
    for m in STOP .stall .notified .ended deadline; do
      grep -qF "$m" "$BATS_TEST_DIRNAME/../skills/$f/SKILL.md" \
        || { echo "skills/$f/SKILL.md does not clear $m"; return 1; }
    done
  done
}

@test "start clears the markers before anything writes a new deadline" {
  f="$BATS_TEST_DIRNAME/../skills/start/SKILL.md"
  clear_at="$(grep -n 'stale run-control marker' "$f" | head -n1 | cut -d: -f1)"
  write_at="$(grep -n 'write .*deadline.* from the order' "$f" | head -n1 | cut -d: -f1)"
  [ -n "$clear_at" ] && [ -n "$write_at" ] && [ "$clear_at" -lt "$write_at" ]
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
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../skills/start/SKILL.md"
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../skills/setup/SKILL.md"
}
