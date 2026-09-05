---
name: stop
description: Issue a stop-work order — pause the shift immediately, leaving unfinished items open.
---

Pause the host-opened project immediately so the owner can edit the punch list and resume later.

Bind once, then never search, guess, or re-resolve. `$TASK_ROOT` is the host-opened project
folder: `${CLAUDE_PROJECT_DIR}` on Claude Code; on Codex the `CODEX_PROJECT_DIR` recovery override
when Nightshift set it, otherwise `pwd -P` captured before any other shell call.
`$NIGHTSHIFT_WORKSPACE` is the validated absolute target of `$TASK_ROOT/.nightshift-link` when that
link exists, otherwise `$TASK_ROOT`. Then `NS="$NIGHTSHIFT_WORKSPACE/.nightshift"` (native Windows:
`$NS = Join-Path $NIGHTSHIFT_WORKSPACE '.nightshift'`), and every Nightshift file is `$NS/<name>`
for the rest of the run; helpers taking `--project` or `-Project` receive
`"$NIGHTSHIFT_WORKSPACE"`. The shell's working directory persists between calls, so a bare path is
never safe.

Resolve the installed plugin root to an absolute `$NIGHTSHIFT_PLUGIN_ROOT`: use
`${CLAUDE_PLUGIN_ROOT}` on Claude Code; on Codex use `$PLUGIN_ROOT` when available, otherwise derive
it from the absolute path attached to this skill (`skills/stop/SKILL.md`). Substitute that
absolute path below; never search for the plugin.

On native Windows, use the PowerShell tool and native paths throughout. Resolve the same values
from `$env:CLAUDE_PROJECT_DIR`, `$env:CODEX_PROJECT_DIR`, and `$env:PLUGIN_ROOT`, with
`[Environment]::CurrentDirectory` as the Codex cwd fallback. Do not route Stop through WSL or Git
Bash.

Run the trusted helper. Do not write `$NS/STOP` by hand, do not delete `$NS/.shift-armed`, and do
not kill `$NS/.watchman` yourself — the helper performs the safe teardown:

```bash
"$NIGHTSHIFT_PLUGIN_ROOT/runtime/stop-shift.sh" --project "$NIGHTSHIFT_WORKSPACE"
```

On native Windows:

```powershell
& "$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\stop-shift.ps1" -Project "$NIGHTSHIFT_WORKSPACE"
```

The helper writes `$NS/STOP` with a reason and UTC timestamp, appends `stopped by owner` to
`$NS/shift-log.md`, and kills only a verified live Nightshift watchman. It does not remove
`$NS/.shift-armed`. Open boxes stay open as the record. Hardhat stays until clock-out writes
`$NS/.ended`. Reset is the manual escape. The deadline, punch list, rules, parking lot, work
orders, receipts, archives, research, opportunities, and shift history stay on disk. Do not wait
for a later Stop event to write the marker — the helper writes it now.

Report the helper's `open-items` count and that the deadline was preserved. A second Stop is safe.

Resume later with Start (`/nightshift:start` on Claude Code, or ask Nightshift to start on Codex).
Start clears the pause markers and begins a new ownership lease. A future preserved deadline
remains the deadline. An expired preserved deadline is not silently renewed: write a new UNIX epoch
to `$NS/deadline`, or run Reset then Start.

This works from the bound conversation, from a helper conversation, and when a failed clock-out left a recovery nonce that still fences the recorded conversation.

**Panic form (does not disarm immediately):** from any POSIX terminal,
`touch "$NS/STOP"`. In native Windows PowerShell, run
`New-Item -ItemType File -Force "$NS\STOP"`. That marker is honored at the next Stop event or
watchman wake. Prefer the helper when the model is stuck — it does not wait for that event.
