---
name: start
description: Begin the shift — preflight, cut whatever is queued, arm the site, work the punch list. Asks nothing, so a scheduled or headless run works exactly like an interactive one.
---

Start a nightshift. Work in `$CLAUDE_PROJECT_DIR`.

Resolve the task root as `${CLAUDE_PROJECT_DIR:-$PWD}`. If its `.nightshift-link` exists, validate
the one absolute workspace path inside it and use that workspace for every `.nightshift/` read or
write; otherwise use the task root. Never search surrounding folders or guess. Print both paths
when linked. The shell's working directory persists between Bash calls, so never rely on a bare
relative path.

If the start request itself explicitly names a different existing Nightshift workspace, that
owner-provided path is authorization to link it: print both absolute paths, run
`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/runtime/link-workspace.sh --host-root "$TASK_ROOT" --workspace "$PROPOSED_WORKSPACE"`,
then continue from the resolved workspace. Without an explicit path or an existing valid link,
refuse to arm outside the task root and direct the owner to Setup; never discover a target.

Read `.nightshift/work-target` before preflight. It is the absolute code repository selected by
Setup. Keep every `.nightshift/` read and write rooted in the opened workspace, but run project
inspection, edits, gates, Git operations, commits, and verification in that work target. Validate
it with `git -C <target> rev-parse --show-toplevel`; if it is missing, use the workspace itself when
it is a repository or its single immediate child repository, and persist that resolved path. If
several child repositories make the choice ambiguous, refuse to arm until Setup records one.

**State map:** `punch-list.md` → owner-approved work active in this shift;
`drafting-table.md` → known work staged for a later shift; `parking-lot.md` → unresolved owner
decisions plus the default chosen so work continues; `work-orders.md` → timed catalog work composed
only through Hunt. Ordinary known plans never become work orders.

**With work in the punch list, this command asks nothing.** It reads the list, arms the site and
works — which is what lets cron run it at 04:00 and lets the watchman revive it after a crash. It
promotes nothing on its own: what is in the punch list is the shift, exactly as the owner left it.

The one time it speaks is when the punch list is **empty**. Then there is no work to do silently,
so it looks at staged drafts and pending Hunt orders and asks which to promote.

## 1. Preflight

- **One shift, one agent — check before touching anything.** Read `.nightshift/.shift-session`.
  Line 5 names the host that owns it. If the record is still alive, an agent is ALREADY working
  this punch list — do not start a second one beside it; hand the owner the running thread and
  stop here. On Claude Code, alive means line 3's pid exists and `ps -o lstart= -p <pid>` matches
  line 4, or the id on line 1 appears in `claude agents --json`; the handoff is
  `claude --resume <id>` for a terminal, `vscode://anthropic.claude-code/open?session=<id>` for
  the IDE. On Codex the record carries no pid (lines 3–4 are empty by design), so prove life the
  way its watchman does: a `codex` process (exact name — `pgrep -x codex`) whose working
  directory (`lsof -a -p <pid> -d cwd`) is this project, or a rollout (line 2) still growing
  across a short recheck — either tell means live, hand the owner `codex resume <id>`. Neither
  tell means the session and its watchman are both gone, however the record looks.
  `touch .nightshift/STOP` is the lever if they want a live shift ended first. A record whose
  process is provably dead is last night's leftover: fall through and clear it below.
- **Clear every stale run-control marker first**, before anything writes a new one — last night's
  leftovers would otherwise end tonight's shift at its first stop attempt. Remove them all if
  present: `.nightshift/STOP`, `.nightshift/.stall`, `.nightshift/.notified`, `.nightshift/.ended`,
  `.nightshift/.session-end`, `.nightshift/.shift-session`, `.nightshift/.shift-armed`,
  `.nightshift/.watchman-tick`, and the `.nightshift/.lock.d/` directory. If
  `.nightshift/.watchman` holds a live pid, kill it — last night's watchman must not double-arm
  tonight's.
- **The deadline is cleared only if it has already passed.** A shift that reached the whistle
  leaves a spent deadline behind, and keeping it clocks tonight out immediately with zero items
  done. But a deadline still in the future is tonight's plan — written by the owner or by hunt's
  cut — and since this command never asks for hours, deleting it would strand a walkthrough that
  can no longer be given a clock.
- **The punch list is the shift.** If `.nightshift/punch-list.md` has at least one open `- [ ]`
  under `## Items`, that is the work — start it. Do not promote, cut, or add anything: parked
  orders and drafts stay exactly where the owner left them.
- **Resume the active product cycle before rediscovery.** When the open item is product evolution,
  inspect `.nightshift/opportunity-map.md` for its single `Status: building` entry before doing new
  research or selecting work. If present, its `Next` action and `Verify remaining` are the
  continuation point. More than one building entry is inconsistent state: do not guess between
  them; keep the earliest one active, mark the others `candidate`, record the repair in
  `shift-log.md`, and continue.
- **Only when the punch list is empty, offer what is staged.** Read `.nightshift/work-orders.md`
  and `.nightshift/drafting-table.md`. If either holds work, show it in one short list and ask
  which to work now. On the owner's choice, **cut it — move, never copy**: the item goes under
  `## Items` and is removed from the file it came from, so it never exists in two places. From a
  work order, write `.nightshift/deadline` as a UNIX epoch from the recorded hours
  (`now + hours*3600`); an order marked finite with no hours writes no deadline.
- If the punch list is empty and nothing is parked, stop and say so: `/nightshift:setup` if the
  project is new, `/nightshift:hunt` to compose a shift, or write an item by hand.
- The working tree is clean enough to commit per item (warn if not).
- **Rotate the journal before it becomes one.** If `.nightshift/shift-log.md` is larger than
  ~500 KB, move it to `.nightshift/archive/<YYYY-MM-DD>/shift-log.md` and start a fresh one
  with the same one-line header. Only the mechanical journal auto-rotates — `snag-log.md` and
  `parking-lot.md` are the owner's review material; `/nightshift:archive` files those on the
  owner's order.
- **New knobs check:** if `.nightshift/rules.json` exists, compare the shipped
  template's keys against the file's (`jq -r 'keys[]'` on each): keys the template has that
  the file lacks mean a plugin update brought new knobs — say so once and point at
  `/nightshift:setup` to review them; never add them yourself here. (The hooks read the file
  live — there is no drift to check and no restart to suggest.)
- The night cannot click Allow. On Claude Code: if neither `.claude/settings.local.json` nor
  `.claude/settings.json` grants frictionless permissions (`bypassPermissions` default mode or an
  allowlist covering the gates' commands), warn once — a permission prompt mid-shift freezes the
  night, and a headless revival is denied outright; `/nightshift:setup` offers the fix. On Codex:
  approvals are per launch — a shift meant to run unattended is started
  `codex -a never -s danger-full-access` — the workspace-write sandbox blocks `git commit`
  (`.git` is protected). A contract that does not commit needs only `workspace-write`; ticks
  alone finish a night. The guards remain the fence either way.
  Warn and proceed; the choice stays the owner's.

## 2. Deadline — read, never asked

The deadline is written when the work is composed, not here.

- `.nightshift/deadline` already exists (hunt wrote it at the cut, or the owner wrote it by hand):
  use it as is.
- No deadline and the list is entirely **finite** items: correct — their natural end is the last
  tick, and a stuck run is red-flagged in the shift log and held for review.
- No deadline and `## Items` contains an **open-ended walkthrough** (coverage hunt, defect hunt,
  product evolution / standing loop): **refuse to start.** A walkthrough with no clock never ends. Say so in one line
  and point at `/nightshift:hunt`, which asks for hours; never invent a number.
- One deadline governs the whole shift: finite items first, the walkthrough soaks up the rest.

## 3. Arm the gate

Every check has passed and the work is known, so the shift begins here. Create the marker:

```bash
touch "$NIGHTSHIFT_WORKSPACE/.nightshift/.shift-armed"
```

**This, and nothing else, is what puts a session on shift.** Until it exists the punch list is an
ordinary to-do file: the clock-out gate holds nobody and hardhat's guards apply to no one, so a
session that writes items while planning still stops freely. From here the hooks bind the first
session that trips them — this one — and hold it to the list.

Write it last. A marker left behind by a preflight that stopped early would put the next session
on a shift it never started.

### Codex identity checkpoint — before the watchman

Codex exposes the current task identity to Nightshift through hook payloads, not as a shell
environment variable. Immediately after writing `.shift-armed`, make one harmless read-only tool
call (`pwd` is sufficient) so the Codex hardhat records `.shift-session`, then classify line 1 with
`ns_codex_identity_kind` from `lib/lib.sh` **before arming the watchman or beginning item work**.

- `resumable` — continue.
- `missing` — continue only with the already-documented fresh-session fallback; say plainly that
  same-thread recovery is unavailable until an identity is recorded.
- `unsupported` or `malformed` — refuse the unattended start. Remove only the markers created by
  this attempted start (`.shift-armed` and its new `.shift-session`), append one failed-preflight
  line to `shift-log.md`, and stop before the watchman or item work. Never pass the value to Codex,
  print it, guess a replacement, or start a fresh unrelated task.

This capture-and-check is part of Start, not an owner instruction to remember. An attended session
that does not request an unattended shift remains unaffected.

## 4. Heads-up

Surface any still-unanswered entries in `.nightshift/parking-lot.md` (read-only) so the owner sees
what the last shift parked — printed, never waited on. Append a `shift started` line to
`.nightshift/shift-log.md`.

## 5. Arm the night watchman

Each host arms its own; both read their cadence from the rules file, and each stands down on a
shift the other host owns. Unless the rules file's `watchMinutes` is `0` (or
`NIGHTSHIFT_WATCH=0` overrides), arm it in the background.

On Claude Code:

```bash
nohup "${CLAUDE_PLUGIN_ROOT}/runtime/claude/watchman.sh" --project "$NIGHTSHIFT_WORKSPACE" >/dev/null 2>&1 &
```

On Codex (the plugin root is `$PLUGIN_ROOT` or its `CLAUDE_PLUGIN_ROOT` compatibility twin; if
neither is set in your shell, it is the installed plugin cache directory):

```bash
nohup "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/runtime/codex/watchman.sh" --project "$NIGHTSHIFT_WORKSPACE" >/dev/null 2>&1 &
```

The Codex identity checkpoint above has already passed before this command is reached. One stance
to state plainly on Codex: there is no owner-interrupt tell yet, so closing an
interactive session with open boxes hands the night to the watchman — it will resume the
conversation headless and finish the list, but only when `.shift-session` holds a resumable
session id (a UUID or a long hex token). ChatGPT thread/conversation handles, rollout paths, and
other non-resumable identities are refused: the watchman stands down rather than guessing or
starting an unrelated conversation. A missing id (a 500 before the first record) still falls
back to a fresh session whose handover is the punch list. The stop-work order
(`touch .nightshift/STOP`) is the off switch, on every host.

It revives a session that DIES mid-shift — an API outage, a crash, a killed terminal — by
spawning a fresh session that resumes from the punch list, and it stands down on done, a
stop-work order, quitting time, or a clean exit. On Claude Code, Esc is honored — the watchman
reads the interrupt from the session transcript and stands by rather than resuming; on Codex
there is no interrupt to read, which is the stance above. `STOP` remains the stop-work order on
every host, and the only stop a headless run can receive.

## 6. Work

Begin item 1 and follow the nightshift skill: one item at a time, gate before each commit, tick
honestly, park don't ask, leave pushing to the owner unless the punch list says otherwise. From
here the clock-out gate owns the session — it will not let
you stop while any box is open.
