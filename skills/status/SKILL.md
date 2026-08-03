---
name: status
description: Read-only shift status — open vs ticked items, parked decisions, snag-log summary, deadline remaining, and any STOP/stall state. Starts no work.
---

Report the shift status for `$CLAUDE_PROJECT_DIR` **without starting or changing anything** — this is
read-only.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — read it with the variable.
The shell's working directory persists between Bash calls and is not necessarily the project root,
and a status read from the wrong directory reports a shift that does not exist.

Read `.nightshift/` and print:

- **Items** — ticked vs open counts from `.nightshift/punch-list.md` (open = lines matching a
  dash + bracketed space; ticked = bracketed x), and the title of the current open item.
- **Parked** — the count and one-line titles of entries in `.nightshift/parking-lot.md`.
- **Snag log** — the last few dispositions from `.nightshift/snag-log.md`, if any.
- **Deadline** — if `.nightshift/deadline` exists, the time remaining until quitting time (it holds a
  UNIX epoch; compare with `date +%s`). Otherwise "no deadline (finite list)".
- **State** — whether `.nightshift/STOP` is present (and its reason), and the current
  `.nightshift/.stall` attempt count if any.

Keep it a compact glanceable summary. Do not modify any file, do not begin work.
