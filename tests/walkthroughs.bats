CAT="$BATS_TEST_DIRNAME/../skills/nightshift/references/shift-catalog.md"
RECIPE="$BATS_TEST_DIRNAME/../skills/nightshift/references/catalog-recipe.md"
HUNT="$BATS_TEST_DIRNAME/../skills/hunt/SKILL.md"
START="$BATS_TEST_DIRNAME/../skills/start/SKILL.md"

@test "the catalog ships the three open-ended shifts and the finite one" {
  grep -q '^## Coverage hunt' "$CAT"
  grep -q '^## Defect hunt' "$CAT"
  grep -q '^## Standing loop' "$CAT"
  grep -q '^## Clear quality debt' "$CAT"
}

# The ending decides whether hunt asks for hours at all, so every entry must state it in the
# heading where both a reader and the skill can see it without parsing the body.
@test "every catalog entry declares its ending in the heading" {
  while IFS= read -r h; do
    printf '%s' "$h" | grep -qE '^## .+ — (finite|open-ended) — ' \
      || { echo "catalog entry does not declare its ending: $h"; return 1; }
  done < <(grep '^## ' "$CAT" | grep -v '^## Shift catalog')
}

@test "the standing loop ends only at the deadline, never by convergence" {
  grep -qi 'deadline is the ONLY thing' "$CAT"
  grep -qiE 'too shallow' "$CAT"
}

@test "the standing loop runs the quality tooling at site inspections" {
  grep -qi 'site inspection' "$CAT"
  grep -qi 'report mode' "$CAT"
}

# The finite entry works the same findings /nightshift:quality only reports. It must fix causes,
# never silence them — the one failure mode that would make a quality shift worse than nothing.
@test "the quality-debt entry fixes causes and never silences" {
  grep -qi 'never silence instead of fixing' "$CAT"
  grep -qi 'no new suppressions' "$CAT"
  grep -qi 'snag-log.md' "$CAT"
}

# A contributed shift is a contract handed to an unattended agent on a stranger's repo. The six
# declarations are what makes such a PR reviewable at all.
@test "the catalog recipe demands every declaration a reviewer needs" {
  [ -f "$RECIPE" ]
  for d in 'finite or open-ended' 'Discovery' 'Definition of done' 'never do' 'Verification' 'Supported stacks'; do
    grep -qi "$d" "$RECIPE" || { echo "recipe does not demand: $d"; return 1; }
  done
  grep -qi 'read by a human before merge' "$RECIPE"
}

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
  grep -q 'work-orders.md' "$BATS_TEST_DIRNAME/../skills/setup/SKILL.md"
}

@test "hunt composes from the catalog and may pick more than one" {
  grep -q 'shift-catalog.md' "$HUNT"
  grep -qi 'more than one may be chosen' "$HUNT"
  grep -qi 'read the catalog file rather than reciting from memory' "$HUNT"
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

# The archive files finished paperwork only — the contract and open work are untouchable.
@test "the archive skill moves only finished records, never the contract or open items" {
  s="$BATS_TEST_DIRNAME/../skills/archive/SKILL.md"
  [ -f "$s" ]
  grep -qF 'stay exactly where they are' "$s"      # open items + contract stay
  grep -qF 'never ticks a box' "$s"                # files paperwork, does no work
  grep -qF 'archive/<YYYY-MM-DD>/' "$s"            # dated folders are the shape
  grep -qF 'unanswered stay' "$s"                  # open questions are not history
}
