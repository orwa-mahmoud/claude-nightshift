---
name: start
description: Begin the shift — preflight, clear stale markers, set a deadline only when it means something, then work the punch list.
---

Start a nightshift. Work in `$CLAUDE_PROJECT_DIR`.

## 1. Preflight

- **Clear every stale run-control marker first**, before anything writes a new one — last night's
  leftovers would otherwise end tonight's shift at its first stop attempt. Remove all five if
  present: `.nightshift/STOP`, `.nightshift/.stall`, `.nightshift/.notified`, `.nightshift/.ended`,
  and `.nightshift/deadline`. A shift that reached the whistle leaves the deadline behind; keeping
  it means the gate clocks the next one out immediately, zero items done.
- If `.nightshift/work-orders.md` holds a pending order, offer to cut it in: on yes, move its item
  under `## Items` and write `.nightshift/deadline` from the order's recorded hours
  (`now + hours*3600`) — the deadline question below is then already answered. Declining leaves
  the order parked; never cut without a yes.
- `.nightshift/punch-list.md` exists and has at least one open `- [ ]` under `## Items`. If not, stop
  and tell the user to run `/nightshift:setup` and add items first.
- The working tree is clean enough to commit per item (warn if not).

## 2. Deadline — asked only when it means something

- If `## Items` contains a **walkthrough** (coverage hunt / defect hunt / standing loop), a deadline is REQUIRED —
  the walkthrough has no natural end but the clock. Ask "how many hours of credit?" and write
  `.nightshift/deadline` as a UNIX epoch timestamp (`now + hours*3600`). Refuse to start a
  walkthrough without one.
- If the list is entirely finite items, do NOT nag: its natural end is the last tick, and a stuck
  run is red-flagged in the shift log and held for review. Offer an optional budget cap in one
  line; only write a deadline if the user asks for one.
- Mixed list: ONE deadline for the whole shift — items first, the walkthrough soaks up the rest.

## 3. Heads-up

Surface any still-unanswered entries in `.nightshift/parking-lot.md` (read-only) so the owner sees
what the last shift parked. Append a `shift started` line to `.nightshift/shift-log.md`.

## 4. Work

Begin item 1 and follow the nightshift skill: one item at a time, gate before each commit, tick
honestly, park don't ask, leave pushing to the owner unless the punch list says otherwise. From
here the clock-out gate owns the session — it will not let
you stop while any box is open.
