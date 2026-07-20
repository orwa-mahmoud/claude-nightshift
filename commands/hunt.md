---
description: Write a ready-made overnight job — coverage hunt, defect hunt, or the standing loop — as a work order with its hours; cut into the punch list only when the owner says start.
---

Prepare a work order for `$CLAUDE_PROJECT_DIR`. Propose, never impose: the punch list changes only
on an explicit yes. If `.nightshift/` does not exist, stop and point to `/nightshift:setup` first.

## 1. Offer the jobs

Present the three presets from
`${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/walkthrough-item.md`, one line each, and ask
which one — and how many hours it gets (every preset is open-ended; the hours are its only cost
cap):

- **Coverage hunt** — meaningful tests until the whistle.
- **Defect hunt** — review → fix until a full pass finds nothing new, or the whistle.
- **Standing loop** — improve and discover; only the clock ends it.

## 2. Write the work order

Append the chosen preset and its hours to `.nightshift/work-orders.md` — hunt's own file; the
drafting table stays the owner's room. Never clobber orders already sitting there — append below
them:

```text
## Work order — <ISO date time>
Hours: <N>

- [ ] **<the preset item, verbatim>**
  ...
```

The hours are inert while the order sits here — the clock starts only at the cut.

## 3. Ask: start now?

One question. On **yes**:

- **cut** the item — move it from `work-orders.md` under `## Items` in
  `.nightshift/punch-list.md`; the order entry is removed, the punch list is the only place it
  lives now,
- write `.nightshift/deadline` as a UNIX epoch: `now + hours*3600`,
- append a `shift started · work order · <preset> · <N>h` line to `.nightshift/shift-log.md`.

From that second the site is live: the clock-out gate holds every session here — this one
included — until the list is done, a stop-work order lands, or the whistle blows.

On **no**: the order stays parked with its hours, costing nothing; `/nightshift:start` offers it
when the owner is ready. Fully respected either way.
