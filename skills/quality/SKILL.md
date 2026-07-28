---
name: quality
description: Survey the project's existing quality debt — lint, types, dead code — and propose punch-list items. Read-only scan; proposes, never imposes.
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

## 3. Propose items — ask, never impose

Draft one punch-list item per meaningful cluster (e.g. "clear the 12 shellcheck findings under
scripts/", "add mypy and fix what it reports"), each in the standard item shape with its own Verify
and Commit lines. Show the drafts and ask, with three first-class answers:

- **accept** — append the items under `## Items` in `.nightshift/punch-list.md`,
- **edit** — reshape the list with the owner first, then append what they approve,
- **none** — write nothing; fully respected.

If the stack no longer matches the current `## Gates` block, say so in one line and point to
`/nightshift:setup` — gates belong to setup, not to this command.
