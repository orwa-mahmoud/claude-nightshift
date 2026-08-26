---
name: stop
description: Issue a stop-work order — end the shift at once, leaving unfinished items open.
---

Issue a stop-work order for the host-opened project.

Resolve the host-opened project folder to an absolute `$TASK_ROOT`: use `${CLAUDE_PROJECT_DIR}` on
Claude Code; on Codex honor Nightshift's `${CODEX_PROJECT_DIR}` recovery override when present,
otherwise capture `pwd -P` before any other shell call. Resolve `$TASK_ROOT/.nightshift-link` when
present and call the validated absolute target `$NIGHTSHIFT_WORKSPACE`; otherwise set
`NIGHTSHIFT_WORKSPACE="$TASK_ROOT"`.

Bind the Nightshift directory once: `NS="$NIGHTSHIFT_WORKSPACE/.nightshift"`. On native Windows,
`$NS = Join-Path $NIGHTSHIFT_WORKSPACE '.nightshift'`. After this bind, Nightshift files are
`$NS/<name>` for every read, write, and shell command. Catalog and owner-facing prose may use the
short names (`punch-list.md`, `parking-lot.md`, `STOP`). Never re-resolve. Helpers that take
`--project` or `-Project` still receive `"$NIGHTSHIFT_WORKSPACE"`.
Never search or guess. The shell's working directory persists
between Bash calls, so never use a bare path.

Resolve the installed plugin root to an absolute `$NIGHTSHIFT_PLUGIN_ROOT`: use
`${CLAUDE_PLUGIN_ROOT}` on Claude Code; on Codex use `$PLUGIN_ROOT` when available, otherwise derive
it from the absolute path attached to this skill (`skills/stop/SKILL.md`). Substitute that
absolute path below; never search for the plugin.

On native Windows, use the PowerShell tool and native paths throughout. Resolve the same values
from `$env:CLAUDE_PROJECT_DIR`, `$env:CODEX_PROJECT_DIR`, and `$env:PLUGIN_ROOT`, with
`[Environment]::CurrentDirectory` as the Codex cwd fallback. Do not route Stop through WSL or Git
Bash.

1. Write `$NS/STOP` with a one-line reason and a timestamp (e.g.
  `stopped by owner · <ISO time>`).
2. Append an `ended by user` line to `$NS/shift-log.md`.
3. If `$NS/.watchman` holds a live pid, kill it — the watchman would
  stand down at its next wake anyway, but there is no reason to leave it waiting.
  On POSIX, `kill` the pid on line 1. On native Windows, import
  `Nightshift.psm1` with
  `Import-Module "$NIGHTSHIFT_PLUGIN_ROOT\lib\Nightshift.psm1" -Force`,
  read pid and start time, and `Stop-Process -Id` only when
  `Test-NSRecordedProcess` returns Alive — a reused pid is not this watchman.
4. Report what stays open: the count and titles of the still-open items — left untouched, an
  accurate snapshot of where work stopped.

The shift ends at the next stop attempt: the clock-out gate sees the marker, releases the process
lease, and leaves open boxes as they are. Resume later with Start (`/nightshift:start` on
Claude Code, or ask Nightshift to start on Codex), which clears the marker.

**Panic form (works even if the model is unresponsive):** from any POSIX terminal,
`touch "$NS/STOP"`. In native Windows PowerShell, run
`New-Item -ItemType File -Force "$NS\STOP"`. The gate honors either
marker the same way.
