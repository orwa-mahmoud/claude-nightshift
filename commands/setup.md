---
description: Scaffold .nightshift/ from the templates and propose stack-aware quality gates — ask, never impose. Private by default.
---

Set up nightshift in this project. Do the scaffolding first, then the gates conversation, then print
a summary. Work in `$CLAUDE_PROJECT_DIR`.

## 1. Scaffold `.nightshift/` (never clobber an existing shift)

For each target below, copy the template only if the target does not already exist:

- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/punch-list-template.md`   → `.nightshift/punch-list.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/drafting-table-template.md` → `.nightshift/drafting-table.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/parking-lot-template.md`  → `.nightshift/parking-lot.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/snag-log-template.md`     → `.nightshift/snag-log.md`

Create `.nightshift/shift-log.md` and `.nightshift/work-orders.md` with a one-line header each if
they do not exist.

## 2. Private by default

- Append a line `.nightshift/` to the project's `.gitignore` (create the file if needed; do not
  duplicate the line). Run history is the owner's — it never enters the project repo.
- Give `.nightshift/` its own local-only receipts repo so state stays versioned without touching the
  project history: if `.nightshift/.git` does not exist, `git init` inside `.nightshift/`, add a
  `.nightshift/.gitignore` that ignores the transient markers `STOP`, `.stall`, `.notified`,
  `deadline`, and make one initial commit. **Never add a remote to it, never push it.**

## 3. Gates — ask, never impose

Detect the stack from the table in `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/gates-catalog.md`
(monorepo-aware). Then ask the user, showing the detected proposal, with three first-class answers:

- **accept** the proposal as-is,
- **edit** it — add, remove, or replace with THEIR own commands (any shell command is a valid gate),
- **none** — fully respected: the shift runs without automated checks.

If gates were accepted or edited, also ask the **site-inspection interval** (every N items or every
H hours). Write the result into the `## Gates` block of `.nightshift/punch-list.md`, replacing the
placeholder. If the answer was none, leave the placeholder as-is.

The `## Gates` block is plain markdown the owner may edit anytime — re-run `/nightshift:setup` to
re-detect after a stack change. The contract's immutability binds the agent, not the owner.

## 4. Summarize

Print what was scaffolded, whether a receipts repo was created, and the gates that were written (or
that none were). Tell the user to draft items in `.nightshift/drafting-table.md`, promote them into
the punch list, then run `/nightshift:start` — and that `/nightshift:quality` can turn existing
lint/type debt into proposed items whenever they want it.
