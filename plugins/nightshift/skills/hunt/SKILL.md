---
name: hunt
description: Compose a guided or automatic shift from the ready catalog, then review it first or run it directly under one time budget. Use when the owner wants to choose jobs or let Nightshift find the highest-value applicable work.
---

Compose a shift for `$CLAUDE_PROJECT_DIR`. If `.nightshift/` does not exist, stop and point to
`/nightshift:setup` first.

Resolve `${CLAUDE_PROJECT_DIR:-$PWD}` through its explicit `.nightshift-link` when present; write
every `.nightshift/` path to the validated absolute target, otherwise the task root. Never search
or guess. The shell's working directory persists between Bash calls, so never use a bare path.

Read `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/execution-modes.md` before composing work.
It is the shared contract for who selects work, when the clock starts, direct-mode authority, and
how multiple entries become one shift.

## 1. Ask who selects

Entries live one per file in `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/shifts/`. **List
that directory and read every file in it**. `shift-catalog.md` beside it explains the two endings;
it does not list the entries.

Offer two first-class modes:

- **Guided** — show one offer line per entry, with its ending marked. The owner may choose more
  than one.
- **Automatic** — ask for hours, inspect the project, determine which entries apply, deduplicate
  their findings, and rank them using `execution-modes.md`. Show evidence only in review-first
  mode; run-direct does not pause.
**More than one may be chosen** — a night can clear the lint backlog and then hunt coverage until
the whistle.

Read the directory rather than reciting from memory: entries are added over time, and a job that
exists in the folder but not in the offer is a job the owner never gets.

## 2. Ask when execution starts

Ask **review first, or run directly?** This choice is independent from Guided or Automatic.

- In **review first**, all discovery remains read-only and the clock starts only after approval.
- In **run directly**, start the clock immediately and do not pause after discovery. Follow the
  direct-mode decision policy in `execution-modes.md`.

## 3. Establish the ending

Per the entry's declared ending:

- **Open-ended** (coverage hunt, defect hunt, product evolution / standing loop) — hours are REQUIRED. These have no
  natural end but the clock; a walkthrough may not start without a deadline.
- **Finite** (clear quality debt) — ask the ending as an explicit either/or: *until every finding
  is clear, or capped at N hours?* Both are real answers; the work ends when the list is empty
  either way, and hours are only a safeguard against a backlog bigger than the night.

One deadline governs the whole shift. Automatic mode always requires hours. On a mixed selection
say so plainly in one line: the finite
work runs first, and the open-ended job soaks up whatever time is left.

## 4. Ask for guided scope

> Anything specific about scope or approach?

Ask this in Guided mode. In Automatic mode infer the safest valuable scope from evidence and the
time budget. Free text is skippable. It is where the useful shift is made: *"only `packages/api/`"*, *"use
`getTestInstance()` from the test package"*, *"one module — this becomes a single reviewable PR"*.
Never edit the entry's own contract to fit it; the owner's words become their own sub-bullet:

```text
  - **Owner instructions:** <verbatim, as written>
```

The entry's rules stay above it untouched. They are what keeps a shift honest — assert behaviour
rather than counts, gate green at every commit, never silence instead of fixing — and owner text
adds constraints rather than replacing them.

## 5. Review or cut

In **review first**, print the items exactly as they will be written, with evidence, order, hours,
and ending, then ask for one approval. This is the last look before anything is armed. Write
nothing before approval.

In **run directly**, do not ask again: write the order and immediately cut it into the active shift.
Record significant discovery and selection decisions in `parking-lot.md` as required by the shared
mode contract.

On approval, append to `.nightshift/work-orders.md` — hunt's own file; the drafting table stays the
owner's room. Never clobber orders already sitting there — append below them:

```text
## Work order — <ISO date time>
Hours: <N, or "none — finite">

- [ ] **<entry item, verbatim>**
  - **Owner instructions:** <if any>
```

The hours are inert while a review-first order sits here — the clock starts only at the cut, after
approval. In run-direct mode the order is cut immediately, so its clock starts now.

## 6. Start or park after review

After review-first approval, ask **start now, or park it for later?** Run-direct skips this question
and always starts now; choosing it was already explicit authorization.

On **now** — start the shift yourself, here, without making the owner type another command. Follow
`/nightshift:start` exactly: clear the stale markers, **move** the item out of `work-orders.md` and
under `## Items` in the punch list (a cut, never a copy — it must not exist in two places), write
`.nightshift/deadline` from the recorded hours, **arm the gate** with
`touch "$NIGHTSHIFT_WORKSPACE/.nightshift/.shift-armed"`, log the start, arm the watchman. The
marker is what starts the shift — without it the list is written and nothing is holding it. From
that second the gate holds this session until the list is done, a stop-work order lands, or the
whistle blows.

On **later** — the order stays parked in `work-orders.md` with its hours, costing nothing. It arms
nothing and the gate stays inert. `/nightshift:start` will offer it when the owner is ready.
