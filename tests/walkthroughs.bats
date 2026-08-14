HUNT="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/hunt/SKILL.md"
START="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/start/SKILL.md"

# The catalog's own rules live in catalog.bats (structural, globbed) and tests/shifts/<entry>.bats
# (one file per entry), so adding a shift never edits a test file someone else is also editing.

# Both entry points into a live shift must clear the same leftovers. They drifted once: start
# cleared three markers, hunt's cut cleared none, so a spent deadline or a leftover STOP from
# last night silently ended the next shift at its first stop attempt. Now only start cuts, so
# only start clears — and it must still name every marker.
@test "start clears every stale marker" {
  for m in STOP .stall .notified .ended deadline .session-end .shift-session .watchman-tick .watchman .lock.d; do
    grep -qF "$m" "$START" || { echo "start does not clear $m"; return 1; }
  done
}

# A spent deadline strands tonight's shift; a future one IS tonight's plan, and since start never
# asks for hours, deleting it would leave a walkthrough that can never be given a clock.
@test "start clears only a deadline that has already passed" {
  grep -qi 'deadline is cleared only if it has already passed' "$START"
  grep -qi 'still in the future is tonight' "$START"
}

# With work queued, start must be silent — that is what lets cron run it and the watchman revive
# it. It speaks only when there is nothing to work, where silence would be useless instead of safe.
@test "start is silent when the punch list has work" {
  grep -qi 'this command asks nothing' "$START"
  grep -qi 'never asked' "$START"         # the deadline is read, not requested
  grep -qi 'punch list is the shift' "$START"
  grep -qi 'promotes nothing on its own' "$START"
}

# A parked order is parked. start cutting it unasked would surprise an owner who deliberately
# said "later" — so the offer happens only when there is no other work.
@test "start promotes nothing unless the punch list is empty" {
  grep -qi 'do not promote, cut, or add anything' "$START"
  grep -qi 'only when the punch list is empty' "$START"
  grep -qi 'drafting-table.md' "$START"
}

# An item in two files is an item that gets worked twice, or ticked in the wrong place.
@test "a cut moves the item and never copies it" {
  grep -qi 'move, never copy' "$START"
  grep -qi 'never exists in two places' "$START"
  grep -qi 'never a copy' "$HUNT"
  grep -qi 'must not exist in two places' "$HUNT"
}

# The one thing start may still do is refuse — a walkthrough without a clock never ends.
@test "start refuses an open-ended item that has no deadline" {
  grep -qi 'refuse to start' "$START"
  grep -qi 'never invent a number' "$START"
}

@test "start writes the deadline from a cut order's recorded hours" {
  grep -q 'work-orders.md' "$START"
  grep -q 'hours\*3600' "$START"
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"
}

# Entries are files in a directory, so hunt must list it. Reciting from memory is how a shift that
# shipped last week never reaches the owner who could have used it tonight.
@test "hunt composes from the catalog directory and may pick more than one" {
  grep -qF 'references/shifts/' "$HUNT"
  grep -qi 'read every file in it' "$HUNT"
  grep -qi 'more than one may be chosen' "$HUNT"
  grep -qi 'read the directory rather than reciting from memory' "$HUNT"
}

# Hours are mandatory only where nothing else can end the shift. Where the work has a natural
# end, the owner gets a real either/or rather than a silent default.
@test "hunt asks for hours only where the ending needs them" {
  grep -qi 'hours are REQUIRED' "$HUNT"
  grep -qi 'explicit either/or' "$HUNT"
  grep -qi 'capped at N hours' "$HUNT"
}

# Owner scope is what turns a generic preset into a shift worth running — but it must never be
# able to rewrite the contract that keeps the shift honest.
@test "hunt takes owner instructions without overwriting the contract" {
  grep -qi 'scope or approach' "$HUNT"
  grep -qF 'Owner instructions:' "$HUNT"
  grep -qi 'never edit the entry' "$HUNT"
  grep -qi 'adds constraints rather than replacing them' "$HUNT"
}

@test "hunt shows the assembled shift before anything is written" {
  grep -qi 'exactly as they will be written' "$HUNT"
  grep -qi 'last look before anything is armed' "$HUNT"
}

@test "hunt writes the order and its hours to work-orders.md, and never clobbers" {
  grep -q 'work-orders.md' "$HUNT"
  grep -q 'Hours:' "$HUNT"
  grep -qi 'never clobber' "$HUNT"
  grep -qi 'clock starts only at the cut' "$HUNT"
}

# Work is composed in one command and started in another; duplicating the cut is how the two
# drifted apart the first time.
# Selecting a shift and saying "now" must start it — not print an instruction to run another
# command. The owner already answered the only question that mattered.
@test "hunt starts the shift itself on now, and parks it on later" {
  grep -qi 'start the shift yourself, here' "$HUNT"
  grep -qi 'without making the owner type another command' "$HUNT"
  grep -qi 'arm the watchman' "$HUNT"
  grep -qi 'park it for later' "$HUNT"
}

@test "hunt separates selection mode from launch mode" {
  grep -qi 'Guided' "$HUNT"
  grep -qi 'Automatic' "$HUNT"
  grep -qi 'review first, or run directly' "$HUNT"
  grep -qi 'independent from Guided or Automatic' "$HUNT"
}

@test "automatic hunt ranks evidence and uses one combined clock" {
  mode="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/execution-modes.md"
  grep -qi 'inspect the repository' "$mode"
  grep -qi 'user or production impact' "$mode"
  grep -qi 'Remove overlaps' "$mode"
  grep -qi 'Run finite entries first' "$mode"
  grep -qi 'at most one open-ended entry' "$mode"
  grep -qi 'one deadline governs' "$mode"
}

@test "review-first and run-direct clocks begin at different boundaries" {
  mode="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/execution-modes.md"
  grep -qi 'clock starts only after' "$mode"
  grep -qi 'Start the clock immediately' "$mode"
  grep -qi 'Guided + run directly' "$mode"
}

@test "run-direct has a bounded decision policy and leaves receipts" {
  mode="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/execution-modes.md"
  grep -qi 'production-quality default' "$mode"
  grep -qi 'parking-lot.md' "$mode"
  grep -qi 'rollback' "$mode"
  grep -qi 'publishing' "$mode"
  grep -qi 'legal or licensing policy' "$mode"
}

# The archive files finished paperwork only — the contract and open work are untouchable.
@test "the archive skill moves only finished records, never the contract or open items" {
  s="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/archive/SKILL.md"
  [ -f "$s" ]
  grep -qF 'stay exactly where they are' "$s"      # open items + contract stay
  grep -qF 'never ticks a box' "$s"                # files paperwork, does no work
  grep -qF 'archive/<YYYY-MM-DD>/' "$s"            # dated folders are the shape
  grep -qF 'unanswered stay' "$s"                  # open questions are not history
  grep -qF 'product-research.md' "$s"             # completed research is preserved
  grep -qF '`candidate`, `building`, and `parked`' "$s" # nonterminal opportunities stay live
}

@test "status surfaces the active product cycle without mutating it" {
  s="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/status/SKILL.md"
  grep -qF 'current phase' "$s"
  grep -qF 'exact Next action' "$s"
  grep -qF 'Verify remaining' "$s"
  grep -qF 'without changing them' "$s"
}
