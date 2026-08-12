---
name: nightshift
description: Run an accountable autonomous shift — work a punch list to completion without clocking out early, park decisions instead of asking, and leave receipts. Use when the user wants to work through a todo list autonomously, run overnight, "don't stop until it's done", "keep going until the list is clear", add test coverage overnight, find and fix everything, or keep reviewing until it's clean.
---

# nightshift — the brain

You are working a **shift**: a punch list the clock-out gate won't let you abandon. Your job is to
finish every item to its own standard, safely, leaving receipts. This skill is how you run one.

If `.nightshift/` doesn't exist yet, tell the user to run `/nightshift:setup` first, then
`/nightshift:start`. The commands own scaffolding and preflight; this skill owns the work.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — use the variable. (On Codex the variable does not exist; the session's working directory is the project root — treat it identically.) The shell's
working directory persists between Bash calls and is not the project root once a gate or a build has
run from inside the code repo; a bare relative path then reads a punch list that isn't there and
writes receipts nobody will find.

## The contract is above `## Items`

`.nightshift/punch-list.md` has a contract section, then `## Items`. The contract binds YOU for the
whole shift: **never edit, trim, or reword it, and never delete an item** — not even to end the
shift. The owner may change the `## Gates` block anytime, so **re-read the punch list at the start of
every item; never cache it.** If you ever notice the contract or an item was altered, restore it
from git before continuing, then carry on.

## One item at a time

Top to bottom, one item, no batching:

1. **Read** the item and the current `## Gates` block.
2. **Build** it fully — production-ready, no stubs, no "documented for later". If you can do it now,
   do it now. Effort is never a reason to defer: "this deserves a focused session" — this IS the
   focused session. Only correctness justifies narrowing an item.
3. **Gate** — run the item gate (the `## Gates` commands) right before the commit. It must be green.
   No suppressions without a written reason beside them.
4. **Commit** — one conventional commit, local by default: the owner reviews and pushes. Push
   yourself only when the punch list explicitly says to.
5. **Tick** the box to `- [x]`. Never fake a tick: the box means the work behind it is real.

Then the next item. Item anatomy: one top-level checkbox per task, plain `-` sub-bullets, its own
**Verify** and **Commit** lines. Promote new work from `drafting-table.md` into `## Items`; never
invent scope the owner didn't ask for.

## Park, don't ask

A shift runs while the owner sleeps. If a decision is genuinely theirs, do NOT ask — the gate denies
it anyway. Instead: choose the most sensible production-grade default, record the decision and your
reasoning in `parking-lot.md` in plain language, and keep working. The owner reviews it over coffee.

## Snag log discipline

Before reporting findings in a review or walkthrough, read `snag-log.md` and dedupe against ALL seen
— fixed AND rejected — so a later cycle never re-reports an earlier one. Append dispositions after
acting: `finding · evidence · fixed/rejected-because/accepted-tradeoff · date`.

## Walkthroughs

A walkthrough is one open box that stays open while a scan → fix → re-scan loop runs. It ends only
honestly:

- **Coverage hunt** — write meaningful tests until quitting time. Coverage is a tripwire, never a
  target; no padding, exclusions need a reason.
- **Defect hunt** — review, dedupe against the snag log, fix behind the gate, re-review. Stop when a
  full pass finds nothing NEW (converged) or at quitting time. **Zero new findings is success** —
  stop honestly even with time on the clock.
- **Standing loop** — improve and discover: rotate 1–2 fresh lenses per cycle (bugs, UX,
  performance, contracts, dead code), walk the live UI every few cycles, run the quality tooling
  at each site inspection. No convergence ending — an empty cycle means a deeper lens, and only
  quitting time ends the item.

Log one line per cycle to `shift-log.md`. A cycle that finds nothing new is success, not idleness.

## Quitting time — a whistle, not an axe

If a deadline is set, past it you start NOTHING new — but you FINISH the unit already in your hands
(the current item, or the current walkthrough cycle), clock out orderly, and stop, even slightly
over. The gate makes this mechanical; you make it graceful. Deadlines belong to open-ended work: a
finite item list ends at its last tick; never start a walkthrough without one.

## Red-tag yourself when stuck

If you catch yourself unable to finish an item — looping, blocked on something real — **red-tag it
yourself**: park it in `parking-lot.md` as `stalled — needs human`, note why, and move to the next
item. Do not loop. The gate's stall warning is the backstop, not the plan.

## Ending the shift

You may stop only when every box is `- [x]`, or the owner issues a stop-work order
(`.nightshift/STOP`). If a shift must end mid-work, clock out orderly: a `wip:` commit plus one
handover line in `shift-log.md`, then stop. History is append-only on shift — no `reset --hard`,
`rebase`, `amend`, or force operations; the night's receipts must survive to morning.
