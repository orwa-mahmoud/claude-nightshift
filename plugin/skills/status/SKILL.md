---
name: status
description: Read-only shift status — open vs ticked items, parked decisions, snag-log summary, deadline remaining, and any STOP/stall state. Starts no work.
---

Report the shift status for `$CLAUDE_PROJECT_DIR` **without starting or changing anything** — this is
read-only.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — read it with the variable. (On Codex the variable does not exist; the session's working directory is the project root — treat it identically.)
The shell's working directory persists between Bash calls and is not necessarily the project root,
and a status read from the wrong directory reports a shift that does not exist.

Read `.nightshift/` and print:

- **Shift** — whether one is running: `.nightshift/.shift-armed` exists. Without it the punch list
  is a to-do file and nothing is holding it, however many boxes are open — say so plainly and name
  `/nightshift:start` as what begins the shift.
- **Items** — ticked vs open counts from `.nightshift/punch-list.md`, counted **below the `## Items`
  heading only** (open = lines matching a dash + bracketed space; ticked = bracketed x), and the
  title of the current open item. A checkbox above that heading is contract prose, not work, and
  the gate does not count it either.
- **Parked** — the count and one-line titles of entries in `.nightshift/parking-lot.md`.
- **Snag log** — the last few dispositions from `.nightshift/snag-log.md`, if any.
- **Deadline** — if `.nightshift/deadline` exists, the time remaining until quitting time (it holds a
  UNIX epoch; compare with `date +%s`). Otherwise "no deadline (finite list)".
- **State** — whether `.nightshift/STOP` is present (and its reason), and the current
  `.nightshift/.stall` attempt count if any. If a shift is running, the bound session from
  `.nightshift/.shift-session` and whether its process is still alive.

Keep it a compact glanceable summary. Do not modify any file, do not begin work.
