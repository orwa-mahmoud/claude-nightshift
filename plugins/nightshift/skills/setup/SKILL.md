---
name: setup
description: Scaffold .nightshift/ from the templates and propose stack-aware quality gates — ask, never impose. Private by default.
---

Set up nightshift in this project. Do the scaffolding first, then the gates conversation, then print
a summary. Work in `$CLAUDE_PROJECT_DIR`.

**State map:** `punch-list.md` → owner-approved work active in this shift;
`drafting-table.md` → known work staged for a later shift; `parking-lot.md` → unresolved owner
decisions plus the default chosen so work continues; `work-orders.md` → timed catalog work composed
only through Hunt. Ordinary plans belong in the drafting table, never in Hunt or the parking lot.

Resolve the task root as `${CLAUDE_PROJECT_DIR:-$PWD}`. If its `.nightshift-link` exists, validate
the one absolute workspace path inside it and use that workspace for every `.nightshift/` read or
write; otherwise use the task root. Never search surrounding folders or guess. Claude's
`.claude/` settings stay at the task root. The shell's working directory persists between Bash calls,
so never rely on a bare relative path.

If the user explicitly identifies a different existing workspace containing `.nightshift/`, show
both absolute paths and ask for confirmation. On yes, run
`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/link-workspace.sh --host-root "$TASK_ROOT" --workspace "$PROPOSED_WORKSPACE"`.
The pointer is local-only and state remains in the authoritative workspace; never copy it.

## 0. Require a real project workspace

Before creating or changing any file, resolve the project root to an absolute path. If it is under
`/workspace/scratch/`, this is a disposable ChatGPT scratch workspace rather than the user's real
repository. **Stop immediately: create no `.nightshift/` directory, rules, settings, receipts repo,
or other files.** Tell the user directly:

> Nightshift needs a real software project workspace. This ChatGPT conversation is using a
> temporary workspace, so files created here will not affect your repository.
>
> Open your project in Codex, or start Codex connected to its GitHub repository. Then mention
> Nightshift and say: “Set up Nightshift in this project.”

Do not mention Claude Code in this ChatGPT-specific redirect: the user is already in an OpenAI
product, so give them the shortest OpenAI-native route. Do not infer “temporary” merely because the
project is not a git repository — local non-git projects and the recommended parent-workspace
layout remain valid. The explicit disposable scratch path is the stop signal.

Resolve the code repository before stack detection:

- If the workspace itself is a Git repository, it is the work target.
- Otherwise inspect its immediate, non-hidden child directories. If exactly one is a Git
  repository, that repository is the work target while `.nightshift/` stays in the opened parent.
- If several child repositories exist and `.nightshift/work-target` does not already select one,
  show the choices and require an explicit target; never guess.
- Persist the chosen repository's absolute Git top-level path, followed by one newline, in
  `$NIGHTSHIFT_WORKSPACE/.nightshift/work-target`. On later setup runs, validate and retain that
  target unless the owner explicitly changes it. Stack detection, Git checks, gates, commits, and
  verification operate in this work target—not necessarily in the workspace holding run state.

## 1. Scaffold `.nightshift/` (never clobber an existing shift)

For each target below, copy the template only if the target does not already exist:

- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/punch-list-template.md`   → `$NIGHTSHIFT_WORKSPACE/.nightshift/punch-list.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/drafting-table-template.md` → `$NIGHTSHIFT_WORKSPACE/.nightshift/drafting-table.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/parking-lot-template.md`  → `$NIGHTSHIFT_WORKSPACE/.nightshift/parking-lot.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/snag-log-template.md`     → `$NIGHTSHIFT_WORKSPACE/.nightshift/snag-log.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/product-research-template.md` → `$NIGHTSHIFT_WORKSPACE/.nightshift/product-research.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/opportunity-map-template.md` → `$NIGHTSHIFT_WORKSPACE/.nightshift/opportunity-map.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/work-orders-template.md` → `$NIGHTSHIFT_WORKSPACE/.nightshift/work-orders.md`

Create `$NIGHTSHIFT_WORKSPACE/.nightshift/shift-log.md` with a one-line header if absent.

**State version.** `.nightshift/state-version` is the schema marker. This plugin supports
integer `1`. If this run created `.nightshift/` (the directory did not exist when setup
started), write exactly `1` followed by a newline to
`$NIGHTSHIFT_WORKSPACE/.nightshift/state-version` after the templates. If `.nightshift/`
already existed and the marker is missing, that workspace is legacy version `0` — offer
`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/migrate-state.sh --project "$NIGHTSHIFT_WORKSPACE"`
and run it only after an explicit yes; the script writes only the marker and refuses while
armed. A marker newer than `1`, or a malformed file, fails closed: print the diagnostic, do
not rewrite or downgrade it, and do not continue scaffolding as if the site were current.

## 2. Private by default

- Keep run state out of git. If `$NIGHTSHIFT_WORKSPACE` is itself a git repo, append a line
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
  not exist, run `git -C "$NIGHTSHIFT_WORKSPACE/.nightshift" init` rather than `cd`-ing there, add a
  `$NIGHTSHIFT_WORKSPACE/.nightshift/.gitignore` that ignores the
  transient markers `STOP`, `.stall`, `.notified`, `deadline`, `.session-end`, `.shift-session`,
  `.watchman`, `.watchman-tick`, and `.lock.d/`, and make one initial commit. **Never add a
  remote to it, never push it.**

## 3. Gates — ask, never impose

Detect the stack in the persisted work target from the table in
`${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/gates-catalog.md` (monorepo-aware). Then ask the
user, showing the detected proposal, with three first-class answers:

- **accept** the proposal as-is,
- **edit** it — add, remove, or replace with THEIR own commands (any shell command is a valid gate),
- **none** — fully respected: the shift runs without automated checks.

If gates were accepted or edited, also ask the **site-inspection interval** (every N items or every
H hours). Write the result into the `## Gates` block of
`$NIGHTSHIFT_WORKSPACE/.nightshift/punch-list.md`, replacing the placeholder. If the answer was none,
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
`$NIGHTSHIFT_WORKSPACE/.nightshift/rules.json` as-is, if it does not already exist — the owner's one config file,
defaults inline. It lives in nightshift's own folder on purpose: everything nightshift is in
one place, kept out of repo history by the same `.nightshift/` gitignore, versioned by the
receipts repo when one exists — and deleting `.nightshift/` removes all of nightshift, rules
included. Validate the file with `jq -e 'type == "object"'` and report a broken one plainly —
never half-apply it. The template's `$schema` field points at
`skills/nightshift/references/nightshift-rules.schema.json` so editors catch invalid names,
types, and values; it is ignored at runtime. Editor discovery, including a `json.schemas`
workspace setting for copies that lack `$schema`, is documented in `docs/knobs.md`.

The hooks read this file directly on every tool call: an owner's edit applies from their very
next action. Nothing is synced anywhere, nothing needs a restart, and there is no second copy.
Env vars of the matching names (`NIGHTSHIFT_FORBIDDEN_COMMANDS`, `NIGHTSHIFT_TOOL_RULES`, …)
remain session-start overrides for tests and one-off exceptions — say so only if asked. If
On Claude Code, `$CLAUDE_PROJECT_DIR/.claude/settings.local.json` may still carry `NIGHTSHIFT_*` env keys that an
earlier version synced from this file, offer to remove them: the file is the one copy.

**Local rule profiles — offer, never impose.** Setup may list the shipped examples in
`skills/nightshift/references/profiles/` (`balanced`, `no-push`, `strict-secrets`) and preview
one with
`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/apply-profile.sh --project "$NIGHTSHIFT_WORKSPACE" --profile <name> --mode fill|replace`.
Applying requires an explicit yes and `--apply`. Fill never overwrites an owner value. Replace
shows the complete next file first. Profiles are a one-time local copy — no network, no
subscription. Refuse `--apply` while armed.

**Template evolution — offer, never impose.** On a re-run with the file already present,
compare the shipped template's keys to the owner's file (`jq -r 'keys[]'` on each): offer any
missing key with its default — "this version added `stallWarnEvery`; add it?" — and never
touch a value the owner already has. Same posture for the contract: if the shipped punch-list
template's contract (the text above `## Items`) has changed since the owner's copy was
scaffolded, show the diff and offer a merge — the owner's wording wins every conflict, and a
punch list with open boxes is never touched at all.

## 6. Summarize

Print the workspace-state path and resolved work target, what was scaffolded, whether a receipts
repo was created, and the gates that were written (or that none were). Tell the user to draft items in `.nightshift/drafting-table.md`, promote them into
the punch list, then start the shift (`/nightshift:start` on Claude Code, or ask Nightshift to start
on Codex). Mention that the open-ended product-evolution shift keeps its evidence and ranked work in
`.nightshift/product-research.md` and `.nightshift/opportunity-map.md`, while the quality skill can
turn existing lint/type debt into proposed items whenever they want it.
