---
name: stop
description: Issue a stop-work order — end the shift at once, leaving open items honestly open.
---

Issue a stop-work order for `$CLAUDE_PROJECT_DIR`.

1. Write `.nightshift/STOP` with a one-line reason and a timestamp (e.g. `stopped by owner ·
   <ISO time>`).
2. Append an `ended by user` line to `.nightshift/shift-log.md`.
3. If `.nightshift/.watchman` holds a live pid, kill it — the watchman would stand down at its
   next wake anyway, but there is no reason to leave it waiting.
4. Report what stays open: the count and titles of the still-open items — left untouched, an honest
   snapshot of where work stopped.

The shift ends at the next stop attempt: the clock-out gate sees the marker and releases, with open
boxes left as they are. Resume later with `/nightshift:start`, which clears the marker.

**Panic form (works even if the model is unresponsive):** from any terminal, `touch
.nightshift/STOP`. The gate honors it the same way.
