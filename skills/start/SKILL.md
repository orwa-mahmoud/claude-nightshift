---
name: start
description: Begin the shift — preflight, clear stale markers, set a deadline only when it means something, then work the punch list.
---

Start a nightshift. Work in `$CLAUDE_PROJECT_DIR`.

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
  `.nightshift/deadline`, `.nightshift/.session-end`, `.nightshift/.shift-session`,
  `.nightshift/.watchman-tick`, and the `.nightshift/.lock.d/` directory. If
  `.nightshift/.watchman` holds a live pid, kill it — last night's watchman must not double-arm
  tonight's. A shift that reached the whistle leaves the deadline behind; keeping it means the
  gate clocks the next one out immediately, zero items done.
- If `.nightshift/work-orders.md` holds a pending order, offer to cut it in: on yes, move its item
  under `## Items` and write `.nightshift/deadline` from the order's recorded hours
  (`now + hours*3600`) — the deadline question below is then already answered. Declining leaves
  the order parked; never cut without a yes.
- `.nightshift/punch-list.md` exists and has at least one open `- [ ]` under `## Items`. If not, stop
  and tell the user to run `/nightshift:setup` and add items first.
- The working tree is clean enough to commit per item (warn if not).
- **Rotate the journal before it becomes one.** If `.nightshift/shift-log.md` is larger than
  ~500 KB, move it to `.nightshift/archive/<YYYY-MM-DD>/shift-log.md` and start a fresh one
  with the same one-line header. Only the mechanical journal auto-rotates — `snag-log.md` and
  `parking-lot.md` are the owner's review material; `/nightshift:archive` files those on the
  owner's order.
- **Rules drift:** if `.claude/nightshift-rules.json` exists, compare it to what this session
  actually runs under — `jq -c '.toolDeny'` of the file against `$NIGHTSHIFT_TOOL_RULES`, and
  each other mapped key against its env var. On any mismatch, warn once: the file changed after
  this session's env was fixed — re-run `/nightshift:setup`, then start a fresh session, or
  tonight runs on the old rules. Also compare the shipped template's keys against the file's
  (`jq -r 'keys[]'` on each): keys the template has that the file lacks mean a plugin update
  brought new knobs — say so once and point at `/nightshift:setup` to review them; never add
  them yourself here.
- The night cannot click Allow: if neither `.claude/settings.local.json` nor
  `.claude/settings.json` grants frictionless permissions (`bypassPermissions` default mode or an
  allowlist covering the gates' commands), warn once — a permission prompt mid-shift freezes the
  night, and a headless revival is denied outright. `/nightshift:setup` offers the fix. Warn and
  proceed; the choice stays the owner's.

## 2. Deadline — asked only when it means something

- If `## Items` contains a **walkthrough** (coverage hunt / defect hunt / standing loop), a deadline is REQUIRED —
  the walkthrough has no natural end but the clock. Ask "how many hours of credit?" and write
  `.nightshift/deadline` as a UNIX epoch timestamp (`now + hours*3600`). Refuse to start a
  walkthrough without one.
- If the list is entirely finite items, do NOT nag: its natural end is the last tick, and a stuck
  run is red-flagged in the shift log and held for review. Offer an optional budget cap in one
  line; only write a deadline if the user asks for one.
- Mixed list: ONE deadline for the whole shift — items first, the walkthrough soaks up the rest.

## 3. Heads-up

Surface any still-unanswered entries in `.nightshift/parking-lot.md` (read-only) so the owner sees
what the last shift parked. Append a `shift started` line to `.nightshift/shift-log.md`.

## 4. Arm the night watchman

Unless `NIGHTSHIFT_WATCH=0`, arm it in the background:

```bash
nohup "${CLAUDE_PLUGIN_ROOT}/adapters/watchman.sh" --project "$CLAUDE_PROJECT_DIR" \
  --interval "${NIGHTSHIFT_WATCH:-10}" >/dev/null 2>&1 &
```

It revives a session that DIES mid-shift — an API outage, a crash, a killed terminal — by
spawning a fresh session that resumes from the punch list, and it stands down on done, a
stop-work order, quitting time, or a clean exit. Esc is honored — the watchman reads the
interrupt from the session transcript and stands by rather than resuming; `STOP` remains the
stop-work order, and the only stop a headless run can receive.

## 5. Work

Begin item 1 and follow the nightshift skill: one item at a time, gate before each commit, tick
honestly, park don't ask, leave pushing to the owner unless the punch list says otherwise. From
here the clock-out gate owns the session — it will not let
you stop while any box is open.
