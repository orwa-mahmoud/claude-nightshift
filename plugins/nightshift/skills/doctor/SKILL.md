---
name: doctor
description: Read-only Nightshift diagnosis — workspace, rules, markers, session, watchman, and classified next actions. Use when a shift looks wrong, recovery is unclear, or the owner asks what Nightshift sees. Never repairs by being invoked.
---

Diagnose `$CLAUDE_PROJECT_DIR` **without changing anything**. Doctor is deeper than status: it
explains what Nightshift resolved and which failures that implies. It does not arm, stop, revive,
rewrite, or delete. Report `.nightshift/state-version` as current (`1`), legacy (missing = `0`),
malformed, or future. Offer `runtime/migrate-state.sh` as `[confirm]` only for unarmed legacy
workspaces; never run it because Doctor was invoked. Future versions are `[blocked]` — never
downgrade.

**State map:** `punch-list.md` → owner-approved work active in this shift;
`drafting-table.md` → known work staged for a later shift; `parking-lot.md` → unresolved owner
decisions plus the default chosen so work continues; `work-orders.md` → timed catalog work composed
only through Hunt. Report these as different categories; do not merge or move them.

Resolve `${CLAUDE_PROJECT_DIR:-$PWD}` through its explicit `.nightshift-link` when present; read
every `.nightshift/` path from the validated absolute target, otherwise the task root. Never search
or guess. The shell's working directory persists between Bash calls, so never use a bare path.

## 1. Run the inspector

```bash
"${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/doctor.sh" --project "$CLAUDE_PROJECT_DIR"
```

Print its report verbatim. Do not summarise away Facts, Warnings, or Actions. The script uses the
same workspace and work-target libraries as the hooks.

## 2. Classify actions — do not execute them

The report tags every suggestion:

- `[safe]` — mechanical leftover with no live session (for example a stale watchman pid file whose
  process is already gone). Still do **not** apply it because Doctor was invoked; offer it.
- `[confirm]` — owner decision (broken link, missing setup, leftover STOP while they still want
  the night). During an **unattended active shift** (`.shift-armed` and open boxes), report that
  the recommendation should be parked with the default "leave in place until morning", but do not
  write the parking lot or ask—the Doctor invocation remains byte-identical.
- `[blocked]` — Nightshift cannot fix this here (non-resumable Codex id, missing host binary,
  unverified wedge). Say so. Never guess a session id.

Invoking Doctor alone must leave the tree byte-identical. Never perform a repair merely because
Doctor was invoked.

## 3. After the report

Offer the classified repairs after the report. If the owner explicitly asks to apply a `[safe]`
leftover while no shift is armed, they are no longer in Doctor — follow stop/start/setup as those
skills specify. Until that explicit ask, change nothing. During an unattended shift, the offer is
informational only: continue the active work without asking or writing state.

Doctor may list local rule profiles and show a preview. Applying a profile is a separate
owner action (`runtime/apply-profile.sh`); invoking Doctor never writes `rules.json`.

If the owner then explicitly asks to **Export support bundle**, they are no longer in Doctor.
Run `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/export-support.sh --project "$CLAUDE_PROJECT_DIR"`.
Print its path, included sections, and omitted categories. Do not upload, attach, transmit, or
open the file. Invoking Doctor alone must not create `.nightshift/support/`.
