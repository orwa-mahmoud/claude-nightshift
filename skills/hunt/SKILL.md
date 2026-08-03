---
name: hunt
description: Compose tonight's shift from the ready catalog — pick the jobs, choose how each ends, add your own scope — then park it or start it. Work is composed here; /nightshift:start only executes.
---

Compose a shift for `$CLAUDE_PROJECT_DIR`. Propose, never impose: nothing is worked without an
explicit yes. If `.nightshift/` does not exist, stop and point to `/nightshift:setup` first.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — write it with the variable.
The shell's working directory persists between Bash calls and is not necessarily the project root,
so a bare relative path lands wherever the last `cd` left it.

## 1. Offer the catalog

Present every entry in `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/shift-catalog.md`, one
line each, with its ending marked. **More than one may be chosen** — a night can clear the lint
backlog and then hunt coverage until the whistle.

Read the catalog file rather than reciting from memory: entries are added there over time, and a
job that exists in the file but not in the offer is a job the owner never gets.

## 2. Ask how it ends

Per the entry's declared ending:

- **Open-ended** (coverage hunt, defect hunt, standing loop) — hours are REQUIRED. These have no
  natural end but the clock; a walkthrough may not start without a deadline.
- **Finite** (clear quality debt) — ask the ending as an explicit either/or: *until every finding
  is clear, or capped at N hours?* Both are real answers; the work ends when the list is empty
  either way, and hours are only a safeguard against a backlog bigger than the night.

One deadline governs the whole shift. On a mixed selection say so plainly in one line: the finite
work runs first, and the open-ended job soaks up whatever time is left.

## 3. Ask for scope — one question, every entry

> Anything specific about scope or approach?

Free text, and skippable. It is where the useful shift is made: *"only `packages/api/`"*, *"use
`getTestInstance()` from the test package"*, *"one module — this becomes a single reviewable PR"*.
Never edit the entry's own contract to fit it; the owner's words become their own sub-bullet:

```text
  - **Owner instructions:** <verbatim, as written>
```

The entry's rules stay above it untouched. They are what keeps a shift honest — assert behaviour
rather than counts, gate green at every commit, never silence instead of fixing — and owner text
adds constraints rather than replacing them.

## 4. Show the assembled shift, then ask

Print the items exactly as they will be written, with the hours and the ending, and ask for one
approval. This is the last look before anything is armed; a typo, a wrong path, or an instruction
that contradicts the contract is caught here or not at all.

On approval, append to `.nightshift/work-orders.md` — hunt's own file; the drafting table stays the
owner's room. Never clobber orders already sitting there — append below them:

```text
## Work order — <ISO date time>
Hours: <N, or "none — finite">

- [ ] **<entry item, verbatim>**
  - **Owner instructions:** <if any>
```

The hours are inert while the order sits here — the clock starts only at the cut.

## 5. Start now?

One question: **start now, or park it for later?**

On **now** — start the shift yourself, here, without making the owner type another command. Follow
`/nightshift:start` exactly: clear the stale markers, **move** the item out of `work-orders.md` and
under `## Items` in the punch list (a cut, never a copy — it must not exist in two places), write
`.nightshift/deadline` from the recorded hours, **arm the gate** with
`touch "$CLAUDE_PROJECT_DIR/.nightshift/.shift-armed"`, log the start, arm the watchman. The
marker is what starts the shift — without it the list is written and nothing is holding it. From
that second the gate holds this session until the list is done, a stop-work order lands, or the
whistle blows.

On **later** — the order stays parked in `work-orders.md` with its hours, costing nothing. It arms
nothing and the gate stays inert. `/nightshift:start` will offer it when the owner is ready.
