---
name: setup
description: Scaffold .nightshift/ from the templates and propose stack-aware quality gates — ask, never impose. Private by default.
---

Set up nightshift in this project. Do the scaffolding first, then the gates conversation, then print
a summary. Work in `$CLAUDE_PROJECT_DIR`.

## 1. Scaffold `.nightshift/` (never clobber an existing shift)

For each target below, copy the template only if the target does not already exist:

- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/punch-list-template.md`   → `.nightshift/punch-list.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/drafting-table-template.md` → `.nightshift/drafting-table.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/parking-lot-template.md`  → `.nightshift/parking-lot.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/snag-log-template.md`     → `.nightshift/snag-log.md`

Create `.nightshift/shift-log.md` and `.nightshift/work-orders.md` with a one-line header each if
they do not exist.

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
  clear yes, skip it: the receipts still exist as plain files. On yes: if `.nightshift/.git` does
  not exist, `git init` inside `.nightshift/`, add a `.nightshift/.gitignore` that ignores the
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
H hours). Write the result into the `## Gates` block of `.nightshift/punch-list.md`, replacing the
placeholder. If the answer was none, leave the placeholder as-is.

The `## Gates` block is plain markdown the owner may edit anytime — re-run `/nightshift:setup` to
re-detect after a stack change. The contract's immutability binds the agent, not the owner.

## 4. Permissions — the night cannot click Allow

An unattended shift stalls forever on a permission prompt, and a watchman revival runs headless —
denied means denied. Ask one question:

> Overnight runs can't answer permission prompts. Enable `bypassPermissions` for this project?
> (recommended — nightshift's guards are hooks and stay armed in every permission mode)

- **Yes** → merge `{"permissions": {"defaultMode": "bypassPermissions"}}` into
  `.claude/settings.local.json` in the project (create the file if absent; never clobber keys the
  owner already has). Settings on disk are what revivals inherit — a mode picked at launch dies
  with the process.
- **No** → respect it and say the cost plainly: *"a permission prompt mid-shift freezes the night
  until morning — if the shift stalls on one, that was tonight's trade."* Suggest the narrower
  alternative: pre-allow just the punch list's tools (test runner, linter, git) in the same file.

## 5. The rules file — every knob in one place

Copy `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/nightshift-rules-template.json` to
`.claude/nightshift-rules.json` if it does not already exist — the owner's one config file,
defaults inline, survives plugin updates. Then load it: validate with `jq -e 'type == "object"'`
(an invalid file is reported, never half-applied) and sync each key into the `env` block of
`.claude/settings.local.json`, machine-escaped, never clobbering env keys that are not
nightshift's:

- `toolDeny` (object) → `NIGHTSHIFT_TOOL_RULES` (compact, via `jq -c`)
- `forbiddenCommands` → `NIGHTSHIFT_FORBIDDEN_COMMANDS`
- `neverCommitPatterns` → `NIGHTSHIFT_NEVER_COMMIT_PATTERNS`
- `expectedEmail` → `NIGHTSHIFT_EXPECTED_EMAIL`
- `protectedDirs` → `NIGHTSHIFT_PROTECTED_DIRS`
- `stallMax` → `NIGHTSHIFT_STALL_MAX`
- `stallWarnEvery` → `NIGHTSHIFT_STALL_WARN`
- `watchMinutes` → `NIGHTSHIFT_WATCH`
- `watchRetrySeconds` → `NIGHTSHIFT_WATCH_RETRY`
- `notifyCommand` → `NIGHTSHIFT_NOTIFY_CMD`
- `revivalPrompt` → `NIGHTSHIFT_REVIVAL_PROMPT`
- `freshRevivalPrompt` → `NIGHTSHIFT_FRESH_PROMPT`
- `clockOutMessage` → `NIGHTSHIFT_GATE_MESSAGE`

An empty string, empty object, or `0` means "use the default": remove that env key rather than
writing it. The env is what enforces, fixed at session start — the file is the owner's editor,
not the agent's lever. Editing the file changes nothing by itself; the summary must say so:
**"rules changed → re-run `/nightshift:setup`, then start a fresh session."**

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
