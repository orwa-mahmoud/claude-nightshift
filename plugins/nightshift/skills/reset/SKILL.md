---
name: reset
description: Abandon current Nightshift runtime mechanics without deleting the owner's work or evidence.
---

Reset runtime mechanics for the host-opened project. This recovers from damaged or confusing
runtime state. It does not delete the punch list, rules, history, or `.nightshift/` itself.

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
it from the absolute path attached to this skill (`skills/reset/SKILL.md`). Substitute that
absolute path below; never search for the plugin.

On native Windows, use the PowerShell tool and native paths throughout. Resolve the same values
from `$env:CLAUDE_PROJECT_DIR`, `$env:CODEX_PROJECT_DIR`, and `$env:PLUGIN_ROOT`, with
`[Environment]::CurrentDirectory` as the Codex cwd fallback. Do not route Reset through WSL or Git
Bash.

Run the trusted helper. Do not delete runtime files by hand:

```bash
"$NIGHTSHIFT_PLUGIN_ROOT/runtime/reset-shift.sh" --project "$NIGHTSHIFT_WORKSPACE"
```

On native Windows:

```powershell
& "$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\reset-shift.ps1" -Project "$NIGHTSHIFT_WORKSPACE"
```

The helper first performs Stop (pause and disarm), then removes the current deadline, leftover
`STOP`, and temporary session, recovery, watchman, lease, and mutex markers. It preserves the punch
list and unfinished items, rules, parking lot, work orders, receipts, archives, research,
opportunities, snag log, shift log, and workspace configuration such as work-target and work-mode.
A second Reset is safe. It never deletes `.nightshift/`.

Report that the deadline was removed and that durable files remain. The plugin install is
untouched. Start after Reset writes a new deadline only when Hunt, a work order, or the owner
supplies one — it does not invent a time budget.
