---
name: quality
description: Survey the project's quality debt — lint, types, tests — then fix it now, draft it for later, or drop it. The scan is read-only; nothing is written or started without an explicit answer.
---

Survey this project's existing quality debt and turn what matters into proposed punch-list items.
The scan is read-only: run checks in report mode, fix nothing, write nothing without an explicit
yes. Work in `$CLAUDE_PROJECT_DIR`.

## 1. Detect and scan

Detect the stack from the table in `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/gates-catalog.md`
(monorepo-aware), then run the matching item-gate commands in report-only mode — no fix flags, no
writes. Skip any tool that is not installed; never install anything. If `.nightshift/` does not
exist yet, scan anyway and note that `/nightshift:setup` is the next step before a shift can run.

## 2. Report in plain numbers

Summarize what came back per tool and per top-level directory — counts, not lectures. A finding is
information, not a demand: the owner may know about it and not care.

## 3. Offer the work — three answers, one of them starts it

Draft one punch-list item per meaningful cluster (e.g. "clear the 12 shellcheck findings under
`scripts/`", "add mypy and fix what it reports"), each in the standard item shape with its own
Verify and Commit lines. Show the drafts, then ask — with three first-class answers:

- **fix now** — write the items straight under `## Items` in `.nightshift/punch-list.md` and start
  the shift here, following `/nightshift:start`: clear the stale markers, log the start, arm the
  watchman. These are finite items, so no deadline is required; offer an optional hours cap in one
  line and write `.nightshift/deadline` only if the owner names a number. From that second the gate
  holds this session until every box is ticked.
- **draft for later** — append them to `.nightshift/drafting-table.md` and arm nothing. The
  drafting table is staging: it is never read by the gate, which is exactly why proposals can wait
  there safely. Tell the owner they can promote what they want into the punch list and run
  `/nightshift:start`, or pick *clear quality debt* from `/nightshift:hunt` to work the whole
  backlog in one shift.
- **ignore** — write nothing at all; fully respected. A finding the owner does not care about is
  not a defect.

Never write to the punch list on anything but an explicit **fix now**. An open `- [ ]` there arms
the clock-out gate for every session in this project, including the one running now — so the box
and the start belong together, or neither happens.

If the stack no longer matches the current `## Gates` block, say so in one line and point to
`/nightshift:setup` — gates belong to setup, not to this command.
