---
description: Stage a ready-made overnight job — coverage hunt, defect hunt, or the standing loop — into the drafting table; promoted to the punch list only on the owner's word.
---

Stage a walkthrough for `$CLAUDE_PROJECT_DIR`. Propose, never impose: the punch list changes only
on an explicit yes. If `.nightshift/` does not exist, stop and point to `/nightshift:setup` first.

## 1. Offer the jobs

Present the three presets from
`${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/walkthrough-item.md`, one line each, and ask
which one:

- **Coverage hunt** — meaningful tests until the whistle.
- **Defect hunt** — review → fix until a full pass finds nothing new, or the whistle.
- **Standing loop** — improve and discover; only the clock ends it.

## 2. Stage it — never clobber

Append the chosen preset item to `.nightshift/drafting-table.md`, wrapped in a session banner so
this staging can never tangle with drafts already sitting there:

```text
— staged by /nightshift:hunt · <ISO date time> · start —
- [ ] **<the preset item, verbatim>**
  ...
— staged by /nightshift:hunt · <ISO date time> · end —
```

Existing drafts stay untouched, wherever they are in the file. The drafting table is the owner's
room: they may edit the staged item directly, or ask you to reorganize the whole table — do it
with them, then continue.

## 3. Promote on the owner's word

Show the staged item and ask, with three first-class answers:

- **promote** — copy the item under `## Items` in `.nightshift/punch-list.md`, exactly as staged
  (banners stay behind in the drafting table),
- **edit** — rework it with the owner first, then promote what they approve,
- **leave** — it stays drafted; nothing enters the punch list; fully respected.

## 4. Point at the clock

Remind the owner: `/nightshift:start` demands hours for any walkthrough — the deadline is the cost
cap, and the standing loop ends at nothing else.
