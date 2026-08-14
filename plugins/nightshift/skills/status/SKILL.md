---
name: status
description: Read-only shift status — open vs ticked items, parked decisions, snag-log summary, deadline remaining, and any STOP/stall state. Starts no work.
---

Report the shift status for `$CLAUDE_PROJECT_DIR` **without starting or changing anything** — this is
read-only.

**State map:** `punch-list.md` → owner-approved work active in this shift;
`drafting-table.md` → known work staged for a later shift; `parking-lot.md` → unresolved owner
decisions plus the default chosen so work continues; `work-orders.md` → timed catalog work composed
only through Hunt. Report these as different categories; do not merge or move them.

Resolve `${CLAUDE_PROJECT_DIR:-$PWD}` through its explicit `.nightshift-link` when present; read
every `.nightshift/` path from the validated absolute target, otherwise the task root. Never search
or guess. The shell's working directory persists between Bash calls, so never use a bare path.

Read `.nightshift/` and print:

- **Schema** — `.nightshift/state-version`: missing means legacy `0`, `1` is current. Report a
  newer or malformed marker and stop there; never rewrite it and never run migration from status.
- **Shift** — whether one is running: `.nightshift/.shift-armed` exists. Without it the punch list
  is a to-do file and nothing is holding it, however many boxes are open — say so plainly and name
  `/nightshift:start` as what begins the shift.
- **Items** — ticked vs open counts from `.nightshift/punch-list.md`, counted **below the `## Items`
  heading only** (open = lines matching a dash + bracketed space; ticked = bracketed x), and the
  title of the current open item. A checkbox above that heading is contract prose, not work, and
  the gate does not count it either.
- **Parked** — the count and one-line titles of entries in `.nightshift/parking-lot.md`.
- **Staged** — known later items in `.nightshift/drafting-table.md`, separately from pending timed
  Hunt orders in `.nightshift/work-orders.md`.
- **Snag log** — the last few dispositions from `.nightshift/snag-log.md`, if any.
- **Product evolution** — when `.nightshift/product-research.md` or
  `.nightshift/opportunity-map.md` contains more than its template headings, report the most recent
  research entry and the counts of candidate, building, shipped, rejected, and parked
  opportunities. If one opportunity is building, show its title, current phase, exact Next action,
  and Verify remaining. Flag multiple building entries as inconsistent without changing them.
  Do not turn the map into work or change a status.
- **Deadline** — if `.nightshift/deadline` exists, the time remaining until quitting time (it holds a
  UNIX epoch; compare with `date +%s`). Otherwise "no deadline (finite list)".
- **State** — whether `.nightshift/STOP` is present (and its reason), and the current
  `.nightshift/.stall` attempt count if any. If a shift is running, the bound session from
  `.nightshift/.shift-session` and whether its process is still alive.
- **Watchman** — if `.nightshift/.watch-reason` exists, print line 1 (the stable code) and the
  same human label Doctor prints (`ns_reason_label` in the shared library). Do not print
  transcript paths, session ids, prompts, or any other payload. Line 2 is optional non-sensitive
  detail only.

Keep it a compact glanceable summary. Do not modify any file, do not begin work.
