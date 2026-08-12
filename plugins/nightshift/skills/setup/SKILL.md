---
name: setup
description: Scaffold .nightshift/ from the templates and propose stack-aware quality gates — ask, never impose. Private by default.
---

Set up nightshift in this project. Do the scaffolding first, then the gates conversation, then print
a summary. Work in `$CLAUDE_PROJECT_DIR`.

Every `.nightshift/` and `.claude/` path below is relative to `$CLAUDE_PROJECT_DIR` (on Codex, the
session's working directory is the project root — treat it identically) — write it with
the variable. The shell's working directory persists between Bash calls and drifts into the code
repo during stack detection, so a bare relative path lands wherever the last `cd` left it.

## 1. Scaffold `.nightshift/` (never clobber an existing shift)

For each target below, copy the template only if the target does not already exist:

- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/punch-list-template.md`   → `$CLAUDE_PROJECT_DIR/.nightshift/punch-list.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/drafting-table-template.md` → `$CLAUDE_PROJECT_DIR/.nightshift/drafting-table.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/parking-lot-template.md`  → `$CLAUDE_PROJECT_DIR/.nightshift/parking-lot.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/snag-log-template.md`     → `$CLAUDE_PROJECT_DIR/.nightshift/snag-log.md`

Create `$CLAUDE_PROJECT_DIR/.nightshift/shift-log.md` and
`$CLAUDE_PROJECT_DIR/.nightshift/work-orders.md` with a one-line header each if they do not exist.

## 2. Private by default

- Keep run state out of git. If `$CLAUDE_PROJECT_DIR` is itself a git repo, append a line
  `.nightshift/` to its `.gitignore` (create the file if needed; do not duplicate the line). If it
  is not one — the recommended layout, where the code repo sits a level below — `.nightshift/` is
  already outside every repo, so write no `.gitignore` there. Run history is the owner's; it never
  enters the project repo.
- **Receipts repo — ask, default no.** The run state can be versioned in its own local-only git
  repo inside `.nightshift/`, so every punch-list change and log line has history. Most people
  don't want a git repo living inside their project, so ask — *"version the run state in a local
  receipts repo? (never pushed, never touches your project's history)"* — and on anything but a
  clear yes, skip it: the receipts still exist as plain files. Present the question neutrally —
  never describe the repo as recommended; the default is no. On yes: if `.nightshift/.git` does
  not exist, run `git -C "$CLAUDE_PROJECT_DIR/.nightshift" init` rather than `cd`-ing there, add a
  `$CLAUDE_PROJECT_DIR/.nightshift/.gitignore` that ignores the
  transient markers `STOP`, `.stall`, `.notified`, `deadline`, `.session-end`, `.shift-session`,
  `.watchman`, `.watchman-tick`, and `.lock.d/`, and make one initial commit. **Never add a
  remote to it, never push it.**

## 3. Gates — ask, never impose

Detect the stack from the table in `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/gates-catalog.md`
(monorepo-aware). Then ask the user, showing the detected proposal, with three first-class answers:

- **accept** the proposal as-is,
- **edit** it — add, remove, or replace with THEIR own commands (any shell command is a valid gate),
- **none** — fully respected: the shift runs without automated checks.

If gates were accepted or edited, also ask the **site-inspection interval** (every N items or every
H hours). Write the result into the `## Gates` block of
`$CLAUDE_PROJECT_DIR/.nightshift/punch-list.md`, replacing the placeholder. If the answer was none,
leave the placeholder as-is.

The `## Gates` block is plain markdown the owner may edit anytime — re-run `/nightshift:setup` to
re-detect after a stack change. The contract's immutability binds the agent, not the owner.

## 4. Permissions — the night cannot click Allow

An unattended shift stalls forever on a permission prompt, and a watchman revival runs headless —
denied means denied. Ask one question:

> Overnight runs can't answer permission prompts. Enable `bypassPermissions` for this project?
> (recommended — nightshift's guards are hooks and stay armed in every permission mode)

- **Yes, on Claude Code** → merge `{"permissions": {"defaultMode": "bypassPermissions"}}` into
  `$CLAUDE_PROJECT_DIR/.claude/settings.local.json` (create the file if absent; never clobber keys
  the owner already has). Write the full path: a copy that lands in a nested code repo grants the
  project nothing, and the first prompt of the night proves it. Settings on disk are what revivals
  inherit — a mode picked at launch dies with the process.
- **Yes, on Codex** → there is no settings file to write: approvals are per launch. Tell the owner
  the unattended spelling — `codex -a never -s danger-full-access` — and say the trade plainly:
  the workspace-write sandbox protects `.git`, so a session under it can edit but never commit,
  and the default contract commits once per item. The fence around that access is nightshift's
  own guards, which hold in every mode — the same trade `bypassPermissions` makes on Claude Code.
  An owner whose contract does not commit (the commit rule is theirs to strip from the punch
  list and `clockOutMessage`) runs unattended under plain `workspace-write` — ticks alone finish
  a night, in the gate and the stall guard alike.
- **No** → respect it and say the cost plainly: *"a permission prompt mid-shift freezes the night
  until morning — if the shift stalls on one, that was tonight's trade."* Suggest the narrower
  alternative: pre-allow just the punch list's tools (test runner, linter, git) in the same file.

## 5. The rules file — every knob in one place

Copy `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/nightshift-rules-template.json` to
`$CLAUDE_PROJECT_DIR/.nightshift/rules.json` as-is, if it does not already exist — the owner's one config file,
defaults inline. It lives in nightshift's own folder on purpose: everything nightshift is in
one place, kept out of repo history by the same `.nightshift/` gitignore, versioned by the
receipts repo when one exists — and deleting `.nightshift/` removes all of nightshift, rules
included. Validate the file with `jq -e 'type == "object"'` and report a broken one plainly —
never half-apply it.

The hooks read this file directly on every tool call: an owner's edit applies from their very
next action. Nothing is synced anywhere, nothing needs a restart, and there is no second copy.
Env vars of the matching names (`NIGHTSHIFT_FORBIDDEN_COMMANDS`, `NIGHTSHIFT_TOOL_RULES`, …)
remain session-start overrides for tests and one-off exceptions — say so only if asked. If
On Claude Code, `$CLAUDE_PROJECT_DIR/.claude/settings.local.json` may still carry `NIGHTSHIFT_*` env keys that an
earlier version synced from this file, offer to remove them: the file is the one copy.

**Template evolution — offer, never impose.** On a re-run with the file already present,
compare the shipped template's keys to the owner's file (`jq -r 'keys[]'` on each): offer any
missing key with its default — "this version added `stallWarnEvery`; add it?" — and never
touch a value the owner already has. Same posture for the contract: if the shipped punch-list
template's contract (the text above `## Items`) has changed since the owner's copy was
scaffolded, show the diff and offer a merge — the owner's wording wins every conflict, and a
punch list with open boxes is never touched at all.

## 6. Summarize

Print what was scaffolded, whether a receipts repo was created, and the gates that were written (or
that none were). Tell the user to draft items in `.nightshift/drafting-table.md`, promote them into
the punch list, then run `/nightshift:start` — and that `/nightshift:quality` can turn existing
lint/type debt into proposed items whenever they want it.
