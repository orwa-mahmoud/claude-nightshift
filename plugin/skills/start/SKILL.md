---
name: start
description: Begin the shift — preflight, cut whatever is queued, arm the site, work the punch list. Asks nothing, so a scheduled or headless run works exactly like an interactive one.
---

Start a nightshift. Work in `$CLAUDE_PROJECT_DIR`.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — write it with the variable.
The shell's working directory persists between Bash calls and drifts into the code repo while
running gates, so a bare relative path reads or writes wherever the last `cd` left it.

**With work in the punch list, this command asks nothing.** It reads the list, arms the site and
works — which is what lets cron run it at 04:00 and lets the watchman revive it after a crash. It
promotes nothing on its own: what is in the punch list is the shift, exactly as the owner left it.

The one time it speaks is when the punch list is **empty**. Then there is no work to do silently,
so it looks at what is parked and asks which of it to work.

## 1. Preflight

- **One shift, one agent — check before touching anything.** Read `.nightshift/.shift-session`.
  If it records a session that is still alive — line 3's pid exists and `ps -o lstart= -p <pid>`
  matches line 4, or the id on line 1 appears in `claude agents --json` — an agent is ALREADY
  working this punch list. Do not start a second one beside it. Tell the owner and hand them the
  running thread: `claude --resume <id>` for a terminal,
  `vscode://anthropic.claude-code/open?session=<id>` for the IDE — and stop here;
  `touch .nightshift/STOP` is the lever if they want that shift ended first. A record whose
  process is dead is last night's leftover: fall through and clear it below.
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
- **Only when the punch list is empty, offer what is parked.** Read `.nightshift/work-orders.md`
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
- The night cannot click Allow: if neither `.claude/settings.local.json` nor
  `.claude/settings.json` grants frictionless permissions (`bypassPermissions` default mode or an
  allowlist covering the gates' commands), warn once — a permission prompt mid-shift freezes the
  night, and a headless revival is denied outright. `/nightshift:setup` offers the fix. Warn and
  proceed; the choice stays the owner's.

## 2. Deadline — read, never asked

The deadline is written when the work is composed, not here.

- `.nightshift/deadline` already exists (hunt wrote it at the cut, or the owner wrote it by hand):
  use it as is.
- No deadline and the list is entirely **finite** items: correct — their natural end is the last
  tick, and a stuck run is red-flagged in the shift log and held for review.
- No deadline and `## Items` contains an **open-ended walkthrough** (coverage hunt, defect hunt,
  standing loop): **refuse to start.** A walkthrough with no clock never ends. Say so in one line
  and point at `/nightshift:hunt`, which asks for hours; never invent a number.
- One deadline governs the whole shift: finite items first, the walkthrough soaks up the rest.

## 3. Arm the gate

Every check has passed and the work is known, so the shift begins here. Create the marker:

```bash
touch "$CLAUDE_PROJECT_DIR/.nightshift/.shift-armed"
```

**This, and nothing else, is what puts a session on shift.** Until it exists the punch list is an
ordinary to-do file: the clock-out gate holds nobody and hardhat's guards apply to no one, so a
session that writes items while planning still stops freely. From here the hooks bind the first
session that trips them — this one — and hold it to the list.

Write it last. A marker left behind by a preflight that stopped early would put the next session
on a shift it never started.

## 4. Heads-up

Surface any still-unanswered entries in `.nightshift/parking-lot.md` (read-only) so the owner sees
what the last shift parked — printed, never waited on. Append a `shift started` line to
`.nightshift/shift-log.md`.

## 5. Arm the night watchman

Unless the rules file's `watchMinutes` is `0` (or `NIGHTSHIFT_WATCH=0` overrides), arm it in
the background — it reads its cadence from the rules file itself:

```bash
nohup "${CLAUDE_PLUGIN_ROOT}/runtime/claude/watchman.sh" --project "$CLAUDE_PROJECT_DIR" >/dev/null 2>&1 &
```

It revives a session that DIES mid-shift — an API outage, a crash, a killed terminal — by
spawning a fresh session that resumes from the punch list, and it stands down on done, a
stop-work order, quitting time, or a clean exit. Esc is honored — the watchman reads the
interrupt from the session transcript and stands by rather than resuming; `STOP` remains the
stop-work order, and the only stop a headless run can receive.

## 6. Work

Begin item 1 and follow the nightshift skill: one item at a time, gate before each commit, tick
honestly, park don't ask, leave pushing to the owner unless the punch list says otherwise. From
here the clock-out gate owns the session — it will not let
you stop while any box is open.
