# How Nightshift works

Nightshift is a native plugin for Codex and Claude Code. It adds no proxy, hosted service, or
second agent runtime. Skills define the working method, files preserve the contract, hooks enforce
the host-specific boundaries that are available, and local shell or PowerShell processes handle
scheduling and recovery when no live session can act.

The workflow skills are shared, but their host boundaries are explicit. Each resolves the
host-opened project through Claude Code's project path or, on Codex, a Nightshift recovery override
or the launch directory captured before any shell call can change it. Both become one neutral
task-root and workspace name. Bundled files follow the same pattern: Claude Code substitutes its
plugin root, while Codex uses its plugin root when available or the absolute path attached to the
loaded skill. From there the skill uses one neutral plugin-root name. Hooks, session signals,
permissions, and watchmen remain separate where the hosts actually differ.

## The work contract

Setup creates a local `.nightshift/` workspace. The important files are plain Markdown:

- `punch-list.md` — the work and its completion state;
- `drafting-table.md` — known work that has not been promoted into the active shift;
- `parking-lot.md` — decisions made without blocking the run;
- `work-orders.md` — catalog work composed by Hunt or Quality;
- `product-research.md` and `opportunity-map.md` — evidence and continuation state for product
  evolution;
- `snag-log.md` — problems found and their disposition;
- `shift-log.md` — progress, stalls, recovery, and clock-out.

Completion lives in checkboxes, not in a conversational claim. Normal clock-out is reached only
when every open `- [ ]` under `## Items` is ticked; checkboxes elsewhere in the file do not belong
to the gate. A crash or compaction can discard conversation detail without discarding the
objective, completed items, open work, or verification still due. Product-evolution and
owner-walkthrough shifts also keep the active unit's completed work, decisions, rejected paths,
exact next action, and remaining verification in `opportunity-map.md`.

Only checkboxes under `## Items` in `punch-list.md` belong to the active contract. A list alone does
not activate hooks: Start, or a Hunt or Quality path that starts immediately, creates
`.shift-armed` after preflight. The clock-out gate and owner rules are active only while that marker
exists, open Items remain, and the shift has not ended.

Archive files ticked items and never resets the leftover Shift contract or Gates. An empty
`## Items` section still binds the next Hunt or Start cut — review those sections before
composing a new campaign. Status and Doctor report the leftover; Archive writes a Notes reminder
when a campaign is fully filed.

Immediately after arming, Start makes a harmless host-shell probe—Bash on POSIX, PowerShell on
native Windows—that records `.shift-session` before item work and creates `.shift-lease` for that
process. Passive reads, searches, and MCP calls cannot
make that first claim. The complete session record appears atomically; if two Start probes race,
one wins and the other is explicitly rejected. Gate and guard decisions then apply to the bound
session and current lease owner; another conversation opened beside the shift can chat, ask, or
issue the stop-work order without inheriting the shift gate. The session record's fifth line names
its host (`claude` or `codex`); legacy records without that line belong to Claude Code.

Start also refuses to place a second agent beside a live shift. It returns the recorded session
handoff instead. A helper conversation remains outside the gate, but it is not
permission to start another shift on the same contract. It is outside the shift command guards too:
the helper can chat and ask freely, but it is not a safe channel for commands the shift rules deny.

`rules.json` contains the owner-controlled hooks configuration. `work-target` records the repository
that receives code changes when state lives in a parent workspace. `state-version` prevents newer
or malformed state from being interpreted by older hooks; unsupported versions fail closed.

## Mechanical gates and owner rules

On both Claude Code and Codex, an attempted stop with open punch-list items receives the focused
contract again. On both hosts, hook-backed rules can deny commands, protected paths, suspicious
secret patterns, or commits under the wrong identity.

Optional command, path, identity, and secret guards are off by default; Setup proposes them and the
owner chooses. The two explicit question-tool entries are the exception: the shipped rules park
questions so an unattended shift does not wait, and the owner may set either value to an empty
string to allow that host's question tool. Active rules hold in every permission mode, including a
broadly permitted unattended session. That combination lets the host run without approval prompts
while hooks still enforce the owner's configured boundaries—a frictionless permission mode plus
an owner-specific denylist that host permissions alone do not express.

Hooks enforce command and stop boundaries. They do not prove that the work behind a checked box is
good. Verification belongs in each item's gate, and a human still reviews the resulting commits.

## Questions, stalls, and deadlines

During a shift, questions are parked with a sensible default instead of silently waiting for the
owner. An owner watching live can answer immediately; otherwise the decision remains on disk for
morning review.

That mechanical policy is explicit in `rules.json`: `toolDeny.AskUserQuestion` controls Claude
Code and `toolDeny.request_user_input` controls Codex. A non-empty value denies that exact tool
with the owner's message; an empty value allows it. The [tool-rules reference](knobs.md#tool-rules)
explains the remaining contract text an owner changes for an interactive, ask-and-wait shift.
Existing workspaces should re-run Setup after upgrade and accept the offered
`request_user_input` entry; Nightshift never inserts it without confirmation.

Run directly authorizes reasonable, reversible implementation defaults without a second approval
pause. Significant decisions, rejected paths, and rollback instructions stay in `parking-lot.md`
for morning review; publishing, destructive changes, and owner policy remain out of scope unless
explicitly authorized.

Review-first Hunt and Quality runs scan or draft only and arm nothing until the owner approves.
Run-direct paths perform the same Start preflight before arming.

A no-progress stop attempt is logged as a stall while the finite contract remains open. Owners who
prefer a hard retry cap can set `NIGHTSHIFT_STALL_MAX=N`. Open-ended shifts require a deadline;
Start refuses to arm one without it. Finite shifts may also use one as a cap.

The stall guard reads checked items and commits as progress. A deadline is therefore the final
cost boundary when failed attempts could otherwise keep producing commits. Without a deadline or
stall cap, a finite shift can remain held and retry until the owner intervenes.

## Recovery

No hook can recover the session it was running inside after that process dies. Nightshift's
watchman runs outside the session, records the active conversation identity, and wakes
periodically. The default cadence is ten minutes and is owner-configurable.

Both watchmen act only on a shift recorded for their own host and require positive evidence before
reviving a dead session. When a resumable identity exists, they target that conversation first;
the host-specific continuation and fresh-session fallbacks below cover failed resume attempts or a
missing identity. They never revive merely because a repository “looks stuck”: builds, syncs, logs,
and all other project-file activity do not vote on session life. They stand down for a completed
shift, a stop-work order, quitting time, or a shift owned by the other host.

Immediately before each revival attempt, the watchman atomically advances `.shift-lease` to a new
generation and passes that generation's ownership nonce to the child process. Every observable
tool call from the bound shift is checked against the lease. The recovered child is admitted; an
older UI or headless process on the same conversation is denied and told to reopen the thread. A
retry advances the generation again, fencing a previous recovery attempt that outlived its caller.
The clock-out gate checks the same ownership before changing stall, STOP, ending, or receipt state.

The lease is scoped to the shift, not the project. Unrelated tabs and conversations continue to
work normally, while a second Start still refuses because an armed shift already exists. Normal
completion, a processed stop-work order, quitting time, or an opted-in stall ending releases the
lease. It is transient, excluded from receipts, and its capability is omitted from support output.
While the shift is active, hooks deny agent tools in any conversation from targeting the lease
itself; ownership changes only through Start, the watchman, or clock-out.

One narrow fail-closed window exists when recovery began before any session identity could be
recorded. Until the recovered child's first observed call binds its new identity, Nightshift cannot
distinguish that child from a helper conversation, so only the child carrying the recovery nonce is
admitted. Once bound, unrelated conversations are free again.

Native Windows uses the same lease and marker contract through bundled PowerShell. Hooks identify
the host ancestor through `Win32_Process`, verify a recorded PID with its UTC start time, and
protect lease capabilities with a private Windows ACL. Task Scheduler generation is the Windows
counterpart to launchd, cron, and systemd generation. The complete parity and the conservative
limits around process evidence, login state, and filesystems are documented in
[Native Windows](windows.md).

Claude Code provides additional transcript and session signals. Its liveness ladder checks the
shift transcript for the owner's Escape first, then checks current transcript activity, the
recorded process, the host's `claude agents --json` roster, and other Claude processes in the
project. Any positive evidence of live work—or unavailable process evidence—stands down rather
than guessing. A live session whose latest conversation event is an API error can instead be
classified as wedged and resumed. A clean `SessionEnd` also stands the watchman down.

Positive revival evidence is the inverse: a recorded process proved dead, a responsive host roster
without the shift session, or an API-error event at the end of a live conversation with nobody
acting.

Codex has no equivalent Escape or clean-session-end signal. Closing an interactive Codex session
with open Items therefore leaves the armed shift to its watchman. A growing rollout or live Codex
process keeps it standing by. A live session that appears wedged on an API error is also left alone
until a stable rollout signature has been captured and classified; see
[#41](https://github.com/orwa-mahmoud/nightshift/issues/41).

With the shipped rules, each Claude watchman wake makes up to three attempts when it has a session
ID: `claude --resume <id>`, then `claude --continue`, then a fresh `claude -p`. Without a recorded
ID, the first attempt is `--continue`. Codex also makes up to three timed attempts, but its rungs
are `codex exec resume` when the identity is resumable, then fresh `codex exec` fallbacks. The
pauses come from `watchRetrySeconds` in `rules.json`.

Every attempt re-runs the host's liveness ladder first, so an owner action or returning session
cancels the remaining retries. An exhausted wake waits for the next one rather than declaring the
night over.

Codex same-conversation revival requires a resumable identity in `.shift-session`; ChatGPT thread
handles, rollout paths, and other known non-resumable identities stand down rather than opening an
unrelated conversation. A missing first identity may use the documented fresh fallback. In every
case, the punch list remains the authoritative handoff.

### Reopening a revived thread

A headless revival appends to the recorded Claude conversation, but an IDE panel that was already
open does not reload turns written by that external process. Close and reopen the recorded thread
from conversation history to see the current transcript. When a recorded session ID exists, the
watchman writes `claude --resume <session-id>` plus Cursor and VS Code deep links to
`parking-lot.md` after the headless subprocess exits successfully—which may not be until that run
finishes. The recovered worker needs no owner monitoring: it continues against the punch list, and
`shift-log.md` records the `resume attempt` for optional inspection.

Do not type **Continue** in the unchanged panel while a headless revival may be working. If the old
process reaches an observable tool, the process lease rejects it before that tool runs. Reopening
is required only to see or interact with the current transcript because the lease cannot refresh
the host's UI. Claude live refresh is tracked in
[anthropics/claude-code#82655](https://github.com/anthropics/claude-code/issues/82655).

Codex has the same stale-window boundary: `codex exec resume` can append to the durable session
without refreshing an already-open Desktop thread. Reopen it before prompting again. The lease
fences observable tools in the stale process; it does not repair the display. Upstream tracking:
[openai/codex#28259](https://github.com/openai/codex/issues/28259) and
[openai/codex#21743](https://github.com/openai/codex/issues/21743).

Those three reports concern display and session-index synchronization. If the hosts resolve them,
the manual reopen can disappear and the recovery handoff can feel consistent across interactive
and headless use. The watchman, on-disk contract, and process lease still provide the recovery and
safety behavior; broader context-continuity reports discussed below can affect resume quality and
are not merely interface polish.

## Stop means stop

Escape and Ctrl+C remain available host interrupts; Nightshift cannot override the owner's
keyboard. They pause or interrupt the current process without clearing the punch list. A clean
Claude session exit is different: it tells the watchman to stand down until Start re-arms. A
headless run has no Escape. On Claude Code, Escape in the shift transcript also tells the watchman
to stand by. Codex exposes no equivalent owner-interrupt signal; closing an interactive Codex
session with open Items leaves the armed shift to its watchman. To end the shift itself on either
host, use the host command or create the portable stop-work order in the folder that contains
`.nightshift/` (not beside `.nightshift-link`):

```bash
touch .nightshift/STOP
```

Native Windows PowerShell uses
`New-Item -ItemType File -Force .nightshift\STOP`.

The order is applied at the agent's next stop attempt so the guards are not stripped from work that
is still running. It then releases the gate, records the ending, and snapshots receipts when the
optional receipts repository is enabled. Open boxes remain open, preserving the exact stopping
point.

## Receipts

Nightshift leaves timestamps, per-item commits, cycle logs, parked decisions, and snag
dispositions under `.nightshift/`. The folder is ignored by the project repository. Setup can
optionally version it in a separate local-only Git repository. That repository is off by default;
Nightshift gives it no remote and never pushes it.

Archiving moves finished work into `.nightshift/archive/<date>/` while keeping the current working
files small.

## Different strengths on each host

Both hosts expose the Stop event Nightshift uses to refuse an early clock-out while open Items
remain. Both also receive the persistent contract, owner rules, bounded shifts, recovery after a
dead resumable session, isolated changes, and reviewable progress. Those capabilities ship as
native skills and hook wiring from one package; Nightshift wraps and proxies nothing.

The differences are in recovery evidence. Claude Code exposes Escape, clean session-end, process,
transcript, and API-error signals. Codex exposes process and rollout activity but not an owner
interrupt, clean close, or verified API-wedge signature. Same-conversation Codex recovery also
depends on a resumable identity recorded before the original process disappears.

Claude's initial interactive lease can include the CLI ancestor's pid and process start time.
On POSIX, Codex's hook payload cannot prove equivalent process ancestry, so its initial lease is
scoped to the bound session; the watchman's private generation nonce supplies the process fence
once recovery begins. Native Windows hooks can walk the Codex process ancestry and record the
same PID/start-time pair when the operating system exposes it.

Nightshift does not claim to repair either host's conversation history. It keeps the important
working state independent of that history. Claude Code's strongest host-specific behavior is the
complete recovery ladder around its transcript and session signals. Codex's strongest additional
value is a bounded shift, durable product-research and opportunity state, mechanical owner rules,
and reviewable progress around a naturally persistent task.

The host continuity failures around this boundary have been reported by Codex users in
[#25900](https://github.com/openai/codex/issues/25900),
[#8310](https://github.com/openai/codex/issues/8310), and
[#29356](https://github.com/openai/codex/issues/29356), and by Claude Code users in
[#6159](https://github.com/anthropics/claude-code/issues/6159) and
[#43044](https://github.com/anthropics/claude-code/issues/43044). Nightshift preserves the working
contract around those failures; it does not patch either host's context engine.

## Workspaces and repositories

Nightshift resolves two locations and persists both decisions:

- the **state workspace** owns `.nightshift/`;
- the **work target** is the Git repository that receives stack detection, gates, commits, and
  verification. Its canonical path is stored in `.nightshift/work-target`.

State resolution never searches parent or sibling folders. Work-target resolution accepts the
opened repository or exactly one immediate, non-hidden child repository. Several candidates require
an explicit choice.

### Repository root (supported)

Open a repository directly to keep local state at its root:

```text
repo/                  ← state workspace and work target
├── .git/
└── .nightshift/       ← gitignored run state
```

Setup may create an optional local receipts repository inside `.nightshift/`; it never adds a
remote.

### Parent with one repository (supported)

For separation by construction, open a plain parent workspace with one repository:

```text
my-project/            ← workspace opened in the host
├── repo/              ← the repository that may eventually push
├── .nightshift/       ← local run state and receipts
└── .claude/           ← local Claude Code settings, when used
```

Setup resolves the sole child repository once and persists its canonical path. Because
`.nightshift/` is outside that repository, run state cannot enter its history by mistake.

### Git worktree (supported)

An opened Git worktree resolves to its own top level, including when `.git` is a worktree pointer
file rather than a directory:

```text
feature-worktree/      ← state workspace and this worktree's work target
├── .git               ← Git-managed worktree pointer
└── .nightshift/
```

Each worktree uses its own state by default. To share an existing Nightshift workspace deliberately,
use the explicit link described below. A parent containing several worktrees is the same as any
multi-repository parent: Nightshift requires a selected work target instead of guessing.

### Parent with several repositories (selection required)

This layout is refused until Setup records an explicit choice:

```text
workspace/
├── repo-a/
├── repo-b/
└── .nightshift/
```

Setup shows the repository choices and writes the selected canonical top level to
`.nightshift/work-target`. Start refuses to arm if that record is absent, invalid, or no longer a
repository. Nightshift never selects the first directory silently.

### Linked task root (explicit opt-in)

If the host task and state workspace must be different folders, create one explicit link:

```bash
plugins/nightshift/runtime/link-workspace.sh \
  --host-root /absolute/task/root \
  --workspace /absolute/nightshift/workspace
```

Native Windows uses `runtime\windows\link-workspace.ps1` with `-HostRoot` and `-Workspace`.

The task root receives a machine-local `.nightshift-link`, excluded through Git's local
`info/exclude` when applicable. This file is a trust boundary: it must be a regular file—not a
symlink—with exactly one absolute path to an existing directory that already owns `.nightshift/`.
Blank extra lines, relative paths, missing targets, symlinks, and targets without `.nightshift/`
fail closed.

The linked workspace becomes authoritative for every state read and write; no state is copied.
The link does not choose the code repository—that remains the linked workspace's persisted
`.nightshift/work-target`. Project settings stay at the host task root.

This repository is maintained with a parent state workspace and a nested public work target.

Remote SSH and devcontainers use these same layouts only when the host process, plugin, repository,
state workspace, hooks, and watchman all run inside the remote environment. The reproducible matrix
and the refused split-runtime boundary are in [Remote environments](remote-environments.md).

## Guarantees and limits

- **Mechanical:** hooks govern when either host may stop and which configured commands or paths are
  denied during the shift.
- **Conventional:** the skill and punch-list contract govern the quality represented by a tick.
  The model reports its own completion; the owner and item checks verify it.
- **No lint or tests is a first-class setup path:** setup does not invent project tooling. The
  item's observable definition of done carries the verification instead.
- **Contract reinjection is not proof:** every blocked stop receives the working standard again,
  including no stubs, pass the item's gate, and never fake a tick, so that standard does not decay
  out of context. This proves only that open Items prevented an early clock-out—not that a checked
  item is good.
- **Completion beats cost by default:** a stuck finite shift remains held and flagged. Add a
  deadline or `NIGHTSHIFT_STALL_MAX` when a cost boundary matters more than indefinite retry.
- **Progress is approximate:** the stall guard treats ticks and commits as progress, so a failed
  attempt committed by the agent can look alive. Item checks and the deadline remain the backstop.
- **No built-in push block:** pushing is allowed unless the owner adds it to the shift rules.
- **Guards are not a sandbox:** shell-command rules match command text. The pattern rules prevent
  accidental drift by a cooperative agent, not deliberate evasion.
- **The process lease fences observed tools:** it rejects stale-process calls delivered to the
  host's PreToolUse hook after ownership transfers. It cannot revoke a call already admitted,
  refresh the IDE, terminate a host process, suppress generated text, or control commands a human
  runs directly in another terminal.
- **Permissions still matter:** an unattended run cannot click an approval prompt. Configure the
  required host permissions before leaving.
- **First run attended:** use a trusted or scratch repository, observe stop and recovery behavior,
  and review every local commit before relying on an overnight run.

Continue with the [first-night safety checklist](first-night-checklist.md), the
[owner knobs](knobs.md), or the [command reference](commands.md).
