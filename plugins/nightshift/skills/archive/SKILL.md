---
name: archive
description: File the finished part of the run state into a dated archive — shipped items, research, opportunities, the rotated journal, and handled snags. The live files stay lean; the facts stay on disk.
---

Archive the finished paperwork. Work in `$CLAUDE_PROJECT_DIR`. This files records — it never
does shift work, never ticks a box, never touches the contract.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — write it with the
variable. (On Codex the variable does not exist; the session's working directory is the
project root — treat it identically.)
The shell's working directory persists between Bash calls and is not necessarily the project root;
records filed into the wrong directory are records lost.

## Where it goes

Everything lands in `.nightshift/archive/<YYYY-MM-DD>/` — today's date, one folder per archive
run (create parents; re-running on the same day appends to that day's files).

## What moves, what stays

- **Punch list → `shipped.md`.** Move every ticked `- [x]` line under `## Items` into the
  archive's `shipped.md` under a `## Shipped <date>` heading — that file reads as the plain
  record of what actually landed. Open `- [ ]` items and everything above `## Items` (the
  contract, the gates) stay exactly where they are.
- **Shift log → the archive, whole.** Move `shift-log.md` into the folder and start a fresh one
  with the same one-line header. The journal is mechanical; its lines belong to the dates they
  happened.
- **Snag log — only what's handled.** Move entries that carry a disposition (fixed, ignored,
  answered) into the archive's `snag-log.md`. Entries still awaiting the owner stay live: an
  open question is not history yet.
- **Parking lot — only what's answered.** Same rule: answered entries move, unanswered stay.
- **Work orders — only what's spent.** Orders already cut into a punch list or marked done
  move; pending orders stay.
- **Product research → the archive after its shift.** When no shift is active, append the completed
  entries from `product-research.md` to the archive's `product-research.md`, preserving their dates,
  sources, evidence, and conclusions; then restore the live file from the shipped template. During
  an active shift, leave all research live. Research is evidence, so never summarize it away or
  strip its source URLs while filing it.
- **Opportunity map — only terminal outcomes.** Move `shipped` and `rejected` entries from
  `opportunity-map.md` into the archive's `opportunity-map.md`, preserving their evidence links and
  reasons. Keep `candidate`, `building`, and `parked` entries live: they can still affect a future
  cycle or need the owner. Restore the shipped headings if moving the last terminal entry leaves an
  empty section. Never renumber or silently change a status during archive.

## Timing

Best between shifts. During an active shift with open boxes, say so and ask before moving
anything — the ticked lines are the night's scoreboard, and the owner may want the morning
review to see them in place. If the receipts repo exists (`.nightshift/.git`), commit after
archiving so the move itself has history.

## Summarize

Print the archive path and one line per file moved or trimmed — and what stayed live and why.
