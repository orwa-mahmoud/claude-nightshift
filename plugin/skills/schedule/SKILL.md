---
name: schedule
description: Set a shift to start at a fixed time — check the work is queued, then print the launchd or cron config for this project and the one command that installs it. Generates; registers nothing.
---

Get `$CLAUDE_PROJECT_DIR` ready to start on a clock, then hand the owner the config. Work through
these in order; each one is a check the owner would otherwise discover at 4am.

Every `.nightshift/` path below is relative to `$CLAUDE_PROJECT_DIR` — use the variable. The shell's
working directory persists between Bash calls and is not necessarily the project root.

## 1. Is there a site at all?

No `.nightshift/` — stop and point at `/nightshift:setup`. Nothing below is meaningful without it.

## 2. Is there work queued?

A scheduled start works the punch list it finds and **promotes nothing** — parked work orders and
drafting-table entries stay exactly where they are. So an empty `## Items` means the scheduled run
does nothing at all, and this is the moment to fix that, not 4am.

Count the open `- [ ]` in `.nightshift/punch-list.md`:

- **Items present** — say what they are in one line and carry on.
- **None** — say so plainly and offer the ways to fix it: compose a shift now with
  `/nightshift:hunt` (answer **later**, not **now** — a shift started here defeats scheduling it),
  promote something from `.nightshift/drafting-table.md`, or write an item by hand. Then re-check.
  Never schedule an empty list without saying it will do nothing.

A parked work order is not queued work. If one exists, say so: it must be moved into the punch list
before the scheduled time, because start will not promote it.

## 3. Will the permissions hold?

A scheduled run is headless and cannot answer a prompt. If neither `.claude/settings.local.json`
nor `.claude/settings.json` grants frictionless permissions, warn once — the run will stall on the
first tool that asks. `/nightshift:setup` offers the fix.

## 4. Queuing arms the gate — say so

An open `- [ ]` holds the clock-out gate for the session doing the queuing, this one included. Tell
the owner to end this session with `/nightshift:stop` once the list is ready: it releases the gate
and leaves the boxes honestly open, and the stop-work order is one of the stale markers
`/nightshift:start` clears at preflight — so the scheduled run begins on a clean site with the list
intact.

## 5. Print the config

Ask for the time if the owner has not given one — 24-hour `HH:MM`, local — then run the generator
and show its output as it comes:

```bash
"${CLAUDE_PLUGIN_ROOT}/outside/schedule.sh" --project "$CLAUDE_PROJECT_DIR" --at <HH:MM>
```

`--list` shows what is already registered for this project; `--remove` prints the command that
unregisters it. The generator refuses to hand over a second entry where one exists — two scheduled
starts on one punch list is two agents on one shift.

**Install nothing.** The owner runs the command it prints, or does not.

## 6. Close

Say where the run's output will land (`.nightshift/scheduled.log`), and mention once that the same
generator runs from a terminal with no session — `outside/schedule.sh` is plain shell and spends
no model tokens, which is what makes it reachable on a day this command is not. The README carries
the full offline note.
