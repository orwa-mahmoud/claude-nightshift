# Command reference

```text
/nightshift:setup      # scaffold .nightshift/ + propose quality gates (ask, never impose)
/nightshift:quality    # read-only survey: what the project's own tooling reports. Writes nothing
/nightshift:hunt       # compose tonight: pick ready shifts, set hours, add your scope
# or write your items in the punch list by hand — one checkbox per task
#   item anatomy, with real items: examples/overnight-webapp.md
/nightshift:start      # asks nothing: cuts what is queued, arms the site, works the list
/nightshift:status     # morning: what got done, what got parked, what got stuck
/nightshift:stop       # end the shift now; open boxes stay open, honestly
/nightshift:archive    # file finished work into .nightshift/archive/<date>/ — shipped items, logs, handled snags
# you review the local commits and push — or forbid pushing outright (one env line below)
```

Stop-work order, any time, from any terminal: `touch .nightshift/STOP`. In an interactive session
Escape is the immediate halt; STOP is what reaches a headless run, and it ends
the shift at the agent's next stop attempt.

**Permissions: the night cannot click Allow.** An unattended shift freezes on a permission prompt,
and a watchman revival runs headless — a denied tool stays denied. For long runs,
`bypassPermissions` is the recommended mode, set in the project's `.claude/settings.local.json` so
revived sessions inherit it (`/nightshift:setup` offers this and writes it on a yes); the narrower
alternative is pre-allowing the punch list's own tools. nightshift's guards are hooks — they stay
armed in every permission mode, bypass included. Decline both and a mid-shift prompt costs the
night; that trade is the owner's.

### Start it at a fixed time

```text
/nightshift:schedule
```

It checks the things that would otherwise surprise you at 4am — that work is actually queued in the
punch list, that permissions won't stall a headless run, that nothing is registered twice — then
prints the launchd plist (macOS) or crontab line for this project and the one command that installs
it. **It registers nothing itself.**

Two things it will tell you, worth knowing in advance: **the items must be in the punch list before
the scheduled time**, because a start works the list it finds and promotes nothing; and **a sleeping
machine runs nothing** — launchd defers a missed job to the next wake, cron loses it, and only
`pmset repeat wakeorpoweron` makes a Mac wake for it.

#### When you have no credit left

The moment you most want to schedule a run is often the moment your quota is gone — and then no
slash command works, because a command is read by the model. The generator underneath is plain
shell that spends no tokens and needs no session:

```bash
plugin/outside/schedule.sh --project . --at 04:05    # print the config + the install command
plugin/outside/schedule.sh --project . --list        # what is already registered for this project
plugin/outside/schedule.sh --project . --remove      # the command that unregisters it
```

Run it from a terminal, or copy the single file anywhere. It refuses a second entry for a project
that already has one, and identifies projects by path rather than folder name, so two checkouts
called `api` never collide. It cannot queue your work for you, though — that part has to be in the
punch list already.

One more appears in your slash menu: `/nightshift:nightshift` is the method itself — how to work an
item, park a decision, keep a snag log. Claude loads it on its own whenever a shift is running, so
you rarely type it; invoke it directly only to have Claude follow the method on a list you are
driving by hand.
