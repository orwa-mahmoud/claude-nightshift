---
name: stop
description: Issue a stop-work order — end the shift at once, leaving unfinished items open.
---

Issue a stop-work order for the host-opened project.

Resolve the host-opened project folder to an absolute `$TASK_ROOT`: use `${CLAUDE_PROJECT_DIR}` on
Claude Code; on Codex honor Nightshift's `${CODEX_PROJECT_DIR}` recovery override when present,
otherwise capture `pwd -P` before any other shell call. Resolve `$TASK_ROOT/.nightshift-link` when
present and call the validated absolute target `$NIGHTSHIFT_WORKSPACE`; otherwise set
`NIGHTSHIFT_WORKSPACE="$TASK_ROOT"`. Never search or guess. The shell's working directory persists
between Bash calls, so never use a bare path.

1. Write `.nightshift/STOP` with a one-line reason and a timestamp (e.g. `stopped by owner ·
   <ISO time>`).
2. Append an `ended by user` line to `.nightshift/shift-log.md`.
3. If `.nightshift/.watchman` holds a live pid, kill it — the watchman would stand down at its
   next wake anyway, but there is no reason to leave it waiting.
4. Report what stays open: the count and titles of the still-open items — left untouched, an
   accurate snapshot of where work stopped.

The shift ends at the next stop attempt: the clock-out gate sees the marker, releases the process
lease, and leaves open boxes as they are. Resume later with Start (`/nightshift:start` on
Claude Code, or ask Nightshift to start on Codex), which clears the marker.

**Panic form (works even if the model is unresponsive):** from any POSIX terminal, `touch
.nightshift/STOP`. In native Windows PowerShell, run
`New-Item -ItemType File -Force .nightshift\STOP`. The gate honors either marker the same way.
