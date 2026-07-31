---
name: archive
description: File the finished part of the run state into a dated archive — shipped items, the rotated journal, handled snags. The live files stay lean; the facts stay on disk.
---

Archive the finished paperwork. Work in `$CLAUDE_PROJECT_DIR`. This files records — it never
does shift work, never ticks a box, never touches the contract.

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

## Timing

Best between shifts. During an active shift with open boxes, say so and ask before moving
anything — the ticked lines are the night's scoreboard, and the owner may want the morning
review to see them in place. If the receipts repo exists (`.nightshift/.git`), commit after
archiving so the move itself has history.

## Summarize

Print the archive path and one line per file moved or trimmed — and what stayed live and why.
