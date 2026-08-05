# nightshift

> **Claude works the night shift: it can't clock out until the punch list is done — and the site
> has safety rules.**

A [Claude Code](https://claude.com/claude-code) plugin for long, unattended runs (hours → days) —
a harness for the accountability half of an agent loop. You write the checklist. Hooks keep the
agent on site until every box is ticked, under rules you set and it can't bend. You go to sleep.

Overview and FAQ: <https://orwamahmoud.com/nightshift/>

## Install

Two commands inside Claude Code — no servers, no tokens, nothing else to download:

```text
/plugin marketplace add orwa-mahmoud/claude-nightshift
/plugin install nightshift
```

## Start your first shift in five minutes

You do not need to learn the whole system first.

1. Open a project you trust and run `/nightshift:setup`. Accept the proposed gates you want.
   For an unattended run, either pre-allow the tools your work needs or let setup configure
   `bypassPermissions` for that project.
2. In `.nightshift/punch-list.md`, add one small, real task under `## Items`:

   ```text
   - [ ] **1. <clear task title>.**
     - <exactly what must change>
     - Verify: <commands that prove it is done>
     - Commit: `<type: concise message>`
   ```

3. Run `/nightshift:start`.
4. Later, run `/nightshift:status`.
5. Review the local commit, then push it yourself.

Only four ideas matter on the first run:

- **Punch list:** the work Claude must finish.
- **Gates:** checks that must pass before an item is ticked.
- **Parking lot:** questions Claude records instead of waking you.
- **Shift log:** the record of progress and problems.

Drafting tables, work orders, hunts, the watchman, receipts, and archives are useful later, but
none is required to try one shift.

## The screen that made me build nightshift

![An agent checkpoint: the smaller fixes shipped, the bigger items deferred in the agent's own
words — and a question that has been waiting since the night before](https://github.com/user-attachments/assets/a4816652-a2c1-4212-aff9-8a3dafd848a6)

I asked for eight things and stepped away. That screen is what I came back to:

- the four **easiest** items — done, shipped, wrapped in a proud little table ✅
- the four **hard** ones — "these deserve a focused session, I don't want to rush them"

Buddy. *This* is the focused session. You're alone. It's just you and the list. What else is on
your calendar tonight??

And that's the mild night. The other three, every developer knows:

**The 02:40 question.** Ten hours of overnight work, planned. You go to bed. At 02:40 it stops:
"quick question before I continue." At 08:00 it's still waiting for the answer. The window is
gone; the work isn't done. And if your credit reset that morning — congratulations: last week's
quota died unused, and the same items will now eat the new week's.

**The review loop.** "Review this" — to the same model that wrote the code an hour ago. Twenty
findings. You fix them, ask again: twenty *new* findings. Where were these twenty the FIRST
time?? You spend the whole evening as a mailman between the model and itself, one "check it
again" at a time.

**The 500 night.** The API does go down, and it picks its moments. Somewhere past 2 AM the
session dies with this on screen, and the punch list just sits there:

![API Error: 500 Internal server error — a server-side issue; if it persists, check
status.claude.com](https://github.com/user-attachments/assets/c9a72548-995b-47c3-a72e-03a0f890a5bc)

You know the ritual: one eye on status.claude.com, waiting to relaunch the second it's back up.
So much for sleeping.

## What nightshift does about it

All four nights end the same way now: you sleep, it works, and your first look in the morning is
at a serious product — not a half-done prototype full of shortcuts.

- **Completion lives in a file, not a phrase.** The shift ends when every `- [ ]` in the punch
  list is ticked — per-item, persistent, greppable. A crashed session resumes from the file.
- **Your rules are laws, not suggestions.** Nothing is blocked out of the box; whatever *you*
  forbid, hooks deny mechanically for the length of the shift: `git push` for the night, `rm -rf`,
  commits that touch a protected folder, diffs that smell like secrets, commits under the wrong
  identity. The agent *can't*, not *shouldn't*. And because they are hooks, not permission rules,
  they hold in **every** permission mode — run the night on `bypassPermissions` and your denylist
  still stands. Allow everything, deny your list: a combination Claude Code has no native spelling
  for. They are shift rules, not a background scanner — outside a shift your session is your own.
  And the shift binds **one** session — the one working it: a second conversation opened beside a
  running shift chats, stops, and asks freely, and `/nightshift:start` refuses to start a second
  agent beside a living one — it hands you the running thread instead.
- **Questions get parked, not asked.** Mid-shift the ask-the-user tool is denied; the question
  lands in `parking-lot.md` with a sensible default chosen, and work continues. Watching live?
  Type your answer any time and it's applied. Asleep? Review the parked calls over coffee.
- **A stuck run is held, not sent home.** No-progress stop attempts get red-flagged in the shift
  log while the gate keeps the shift open — you wake to a flagged stall, not an early clock-out.
  Prefer a hard cap? One env var (`NIGHTSHIFT_STALL_MAX=N`), and the deadline bounds the night
  regardless.
- **A dead session is revived, not mourned.** No hook can fire in a session that no longer
  exists — that's the 500 night. You're supposed to be asleep; instead you're refreshing
  status.claude.com so you can relaunch the moment it recovers. Don't — the **night watchman**
  works that shift: it wakes every 10 minutes, and when the site is quiet it resumes **the
  shift's own conversation by id** — hours of context, decisions, where it stood mid-item — so
  the morning transcript is one unbroken thread: the 500, the revival, and everything after, in
  the terminal or your IDE's extension alike. (One platform limitation: an already-open
  conversation view cannot auto-update while a headless revival appends to it. nightshift hands
  you the reopen instead — the revival leaves its resume command and deep links in the parking
  lot, and any of them shows the full thread. An issue is open upstream to close the gap:
  [anthropics/claude-code#82655](https://github.com/anthropics/claude-code/issues/82655).) (The chain degrades honestly: the recorded
  conversation first, `claude --continue` next, a fresh session last — the punch list on disk is
  enough for any of them.) Reviving needs strong positive evidence of death, never "looks
  stuck": the shift records its own session id, transcript, and process at first work, and the
  watchman reads only the session's own signals — your Esc first, then a transcript still
  streaming, a live shift process on silent work, the host's own session roster
  (`claude agents --json`), or any claude session in the project stands it by. Project files
  never vote: a churning build, a sync, or a stray log writer can neither mute your Esc nor
  mask a death. A dead process, a roster without the shift, or a session alive at an errored
  prompt — the transcript's last word is the API error itself — is what gets revived. It stands down at
  every honest ending — done, stop-work order, quitting time, a clean exit — gives an outage
  three tries every wake, all night, until the API answers, and **Esc still means stop**: your interrupt is
  in the transcript, and the watchman reads it before touching anything.
- **You're never trapped.** Escape and Ctrl+C still work — it's your keyboard, the plugin can't
  override it. But a pause isn't an ending: the next session resumes the shift, and a headless
  run has no Escape at all. `touch .nightshift/STOP` from any terminal is the
  real stop-work order: it ends the shift itself — the gate releases, receipts
  written. It lands at the next stop attempt rather than mid-keystroke, and the site rules stay
  armed until then, so an order given in alarm never strips the guards off a still-working agent.
  Open boxes stay open — a true snapshot of where it stopped.
- **Receipts, not vibes.** Timestamps, per-item commits, cycle logs — plain files under
  `.nightshift/`, kept out of your project's history. When they grow, `/nightshift:archive`
  files the finished part into `.nightshift/archive/<date>/` — shipped items, the journal,
  handled snags — dated, readable facts about what landed. Want git history of the run state
  too? Setup offers a local-only receipts repo (opt-in; no remote, never pushed).

## One shift, start to clock-out

https://github.com/user-attachments/assets/06868e7a-0991-4156-bfa1-de5521da36d9

A recorded session, unedited apart from pacing. Three items on the punch list, `/nightshift:start`,
one commit each — and midway the agent announces it is finished and tries to end the session with
two boxes still open. The gate refuses and hands back the contract; it goes back to the list and
clocks out only once every box is ticked.

## When to call in the night shift

- **Two days left in the cycle, 80% of your credit unspent.** It doesn't roll over. Put the
  backlog on the punch list and let the night eat it.
- **Plan with Fable, execute with Opus.** Do the thinking with the big model, write the items,
  hand the list to the workhorse overnight. The punch list *is* the handover — files, not vibes.
- **Your prototype demos great and is held together with tape.** Every shortcut, mock, and "good
  enough for the demo" becomes an item — and instead of babysitting a chat for hours, you wake up
  to the product version.
- **The wall of warnings everyone scrolls past.** No lint, no types, or a thousand findings
  nobody owns. `/nightshift:quality` turns the debt into punch-list items — accept the ones you
  care about, decline the rest, and let the night clear them.
- **The classics.** Add real test coverage overnight, ride the review → fix loop until it
  converges, or run the standing loop until the whistle. All ready-made — `/nightshift:hunt`
  stages one in seconds.

If you can write it as a checklist, you can hand it to the night.

## Command reference

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
plugin/adapters/schedule.sh --project . --at 04:05    # print the config + the install command
plugin/adapters/schedule.sh --project . --list        # what is already registered for this project
plugin/adapters/schedule.sh --project . --remove      # the command that unregisters it
```

Run it from a terminal, or copy the single file anywhere. It refuses a second entry for a project
that already has one, and identifies projects by path rather than folder name, so two checkouts
called `api` never collide. It cannot queue your work for you, though — that part has to be in the
punch list already.

One more appears in your slash menu: `/nightshift:nightshift` is the method itself — how to work an
item, park a decision, keep a snag log. Claude loads it on its own whenever a shift is running, so
you rarely type it; invoke it directly only to have Claude follow the method on a list you are
driving by hand.

## Receipts

**nightshift was built by nightshift.** An enforced punch list guarded every build session of this
repo, and the hooks refused every early clock-out. Each item landed as its own conventional commit
— `git log --oneline` reads like the shift log — and the final punch list + shift log are in
[`examples/self-build.md`](examples/self-build.md).

**And it ran a real production night.** One list, one night, on a published library: 9 items — a
CSV export button, 7 new locales, a Tailwind starter, inline cell editing and row grouping across
every adapter — landed as unsquashed per-item commits, closed 4 issues on merge, and shipped as
v1.2.0 on npm the same day. Public links:
[`examples/adapttable-overnight.md`](examples/adapttable-overnight.md).

The live `.nightshift/` state stays out of this repo — the same default nightshift sets for your
projects: your run history is yours, ignored by your repo, and versioned in its own local
receipts repo if you opt in at setup.

## The three famous shifts

**Defect hunt** — the twenty-findings-every-pass loop from the story above, ridden for you. You
stop playing mailman: every fix goes behind your gates, a snag log makes sure cycle 4 never
re-reports cycle 1, and it stops at one of two clean endings — a full pass finds nothing new
(converged), or the whistle blows (deadline). Either way the bill is capped and the repo is
cleaner than you left it.

**Coverage hunt** — "add test coverage overnight": meaningful tests until the whistle — coverage
is a tripwire, never a target, so no padding tests just to move a number.

**Standing loop** — the greedy one, for when there's credit and hours: improve and discover until
the clock says stop. Every cycle rotates a fresh lens — real-bug traces, UX friction, performance,
contract drift, dead code — walks the live UI, and runs your quality tooling at every site
inspection. An empty cycle doesn't end it; it means dig deeper. Only the whistle ends it.

None of them is a command you babysit — `/nightshift:hunt` writes the one you pick as a **work
order**: the item plus its hours, parked in `.nightshift/work-orders.md` with the clock not
running. Say "start now" and it cuts the order into the punch list, arms the deadline, and the
gate takes over — or leave it parked and `/nightshift:start` offers it when you're ready. Either
way a walkthrough never runs without its cost cap. Prefer to hand-roll? The items live in
[`shift-catalog.md`](plugin/skills/nightshift/references/shift-catalog.md) — paste and tweak, and
`start` asks the hours.

## The vocabulary

Everything is named from a real construction site — learn one term, guess the rest:

| Term | File / mechanism | Meaning |
|---|---|---|
| **punch list** | `.nightshift/punch-list.md` | construction's final acceptance list — the job isn't done until every item is cleared and signed off |
| **clock-out gate** | Stop hook | you can't clock out while the punch list has open items |
| **hardhat** | PreToolUse hook | mandatory safety equipment — your forbidden commands, protected dirs, secret patterns; denied, not discouraged |
| **item gate** | per-item commands | work isn't accepted until it passes inspection — once per item, right before its commit |
| **site inspection** | interval commands | the scheduled heavy inspection (coverage, dead code, Sonar) every N items or H hours |
| **walkthrough** | template item | the open-ended scan → fix loop that hunts defects until the clock runs out |
| **hunt** | `/nightshift:hunt` | writes a ready-made walkthrough as a work order; cuts it into the punch list only on your word |
| **work order** | `.nightshift/work-orders.md` | a prepared job ticket — the item plus its hours, clock not running until the cut |
| **snag log** | `.nightshift/snag-log.md` | findings ledger across runs — cycle 4 never re-reports cycle 1 |
| **parking lot** | `.nightshift/parking-lot.md` | decisions for the human — parked with a default chosen, the run continues |
| **park, don't ask** | hardhat rule | during a shift the ask-tool is denied — the question is parked with a default chosen; answer mid-run in the session and the agent applies it |
| **quality survey** | `/nightshift:quality` | the optional debt audit — existing lint/type findings become proposed items; accept, edit, or decline |
| **drafting table** | `.nightshift/drafting-table.md` | where items are drawn before they're contracted |
| **quitting time** | `.nightshift/deadline` | past the deadline, the next stop attempt clocks the shift out and starts nothing new — a whistle, not an axe: it bounds the night without killing work mid-item |
| **red-tag** | stall guard | a stuck run is flagged in the shift log and held open by default; `NIGHTSHIFT_STALL_MAX=N` clocks it out after N stuck attempts instead |
| **stop-work order** | `.nightshift/STOP` | `/nightshift:stop` — or `touch .nightshift/STOP` from any terminal — ends the shift at the agent's next stop attempt; the site rules stay armed until it actually stops |
| **morning whistle** | `NIGHTSHIFT_NOTIFY_CMD` | optional shift-end ping (ntfy / Pushover / `say`) |
| **night watchman** | `plugin/adapters/watchman.sh` | revives a session that DIED mid-shift (crash, API outage) by resuming its own conversation; stands down at every honest ending |

## Owner knobs

Zero-config by default; every knob below is off until you set it (unset ⇒ the default described).

**One file drives them all:** setup copies a ready template to `.nightshift/rules.json` —
clean JSON, yours to edit: the tool-deny map, the guard patterns, the cadences, the watchman's
revival orders, the gate's clock-out text. The hooks read the file directly on every tool call,
so an edit applies from your very next action — no sync, no restart, no second copy. During a
shift the file itself is guarded: the session working the night is denied touching it, so only
you set or lift a rule. The env vars below remain as session-start overrides for tests and
one-off exceptions.

| Env var | Effect |
|---|---|
| `NIGHTSHIFT_TOOL_RULES` | JSON map of tool name → denial message (rules file: `toolDeny`). A key denies that tool with your wording; an empty message lifts the rule; absent keys mean the default — AskUserQuestion parked, everything else allowed |
| `NIGHTSHIFT_REVIVAL_PROMPT` | your wording for the order a **resumed** conversation gets — default is one line ("you were cut off, continue"), because the thread carries its own context (rules file: `revivalPrompt`) |
| `NIGHTSHIFT_FRESH_PROMPT` | your wording for the **fresh-session** fallback's order — the only rung that starts with no context, so its default points at the punch list (rules file: `freshRevivalPrompt`) |
| `NIGHTSHIFT_GATE_MESSAGE` | your wording for the clock-out gate's DO-NOT-STOP reinjection (rules file: `clockOutMessage`) |
| `NIGHTSHIFT_STALL_WARN` | hold-mode stall warning cadence — warn every N stuck stop attempts (rules file: `stallWarnEvery`; default 3) |
| `NIGHTSHIFT_FORBIDDEN_COMMANDS` | deny any Bash command matching this `grep -E` pattern during a shift — your own site rules. `git .*push` keeps pushing yours for the night (the `.*` also catches `git -c k=v push`); `rm -rf\|docker\|terraform` fences the rest. The rules file is guarded during a shift, so only you set or lift a rule — never the agent working the night |
| `NIGHTSHIFT_EXPECTED_EMAIL` | during a shift, deny commits authored under any other identity |
| `NIGHTSHIFT_PROTECTED_DIRS` | during a shift, space/pipe-separated dir names never to `git add/commit/tag/remote` |
| `NIGHTSHIFT_NEVER_COMMIT_PATTERNS` | during a shift, deny a commit whose diff matches this `grep -E` pattern — the index, widened to the working tree when the command stages implicitly (`git commit -a`) |
| `NIGHTSHIFT_WATCH` | minutes between night-watchman wakes; `0` disarms it (unset ⇒ 20). The revival resumes **the shift's own conversation by id** (`claude --resume <recorded session> -p`) — one unbroken thread in the terminal and the IDE extension alike — degrading per attempt to `claude --continue -p` and last to a fresh `claude -p` in case the conversation itself is what broke. `NIGHTSHIFT_WATCH_AGENT="claude -p"` makes every revival a fresh session instead |
| `NIGHTSHIFT_STALL_MAX` | by default a stuck agent is held and red-flagged in the shift log, never clocked out; set `=N` to clock the shift out after N stuck attempts. |
| `NIGHTSHIFT_NOTIFY_CMD` | shift-end ping; runs with `$NIGHTSHIFT_SUMMARY` set (e.g. `say "$NIGHTSHIFT_SUMMARY"`). The watchman rings it too — once per outage — when a dead session could not be revived: the one night event that needs you. A successful revival never pages; it lands as a notice in `parking-lot.md` with the thread's resume command and deep links |

Every rule above is **shift-scoped**: it applies while `.nightshift/punch-list.md` has an open
`- [ ]` and the gate has not yet ended the shift. With no punch list, or once the last box is
ticked, your session is ordinary again and none of them are watching. They are site rules for the
night, not a background scanner.

The two commit knobs read git, so they work against the repository the commit lands in — one the
command names itself (`git -C <dir>`, `cd <dir> &&`), else the tool's working directory, the
project dir, or the single repo below it. Where that is genuinely ambiguous, such as a workspace
holding two repos with the commit run from the root, they deny and say so rather than guess.

**Changed in v0.4.0:** the commit guards resolve the repository they inspect, so they hold in the
recommended layout below as well as in-place. Commits there count as shift progress too.

**Changed in v0.3.0:** by default a stalled agent is now held and red-flagged, never clocked out —
in the clock-out gate. Set `NIGHTSHIFT_STALL_MAX=N` to restore
auto-clock-out after N stuck attempts.

## Recommended layout

nightshift works in-place on any repo — state is gitignored, and can be versioned in its own
local receipts repo if you opt in at setup, so your project history stays clean either way. For
hard separation, run it from a plain workspace folder that contains your repo:

```text
my-project/            ← plain folder, not a repo — open Claude Code here
├── repo/              ← your actual git repo (the only thing that pushes)
├── .nightshift/       ← run state + receipts, entirely outside your repo
└── .claude/           ← your local Claude Code config
```

Outside the repo, run state can never be committed by any mistake — separation by construction,
not configuration. (This repo is built exactly this way.)

## Built into Claude Code, not bolted on

nightshift extends Claude Code through its own extension points — hooks for enforcement, skills
for the method, the plugin marketplace for install. It wraps nothing, proxies nothing, and needs
no package manager: `/plugin install` is the whole setup. A harness that stands outside an agent
can only re-invoke it; one that runs inside can refuse the exit, deny the tool call, and park the
question.

The *method* travels further than the plugin does. A punch list, one commit per item, decisions
parked instead of asked — that is plain markdown and git, and you can follow it by hand with any
agent. The mechanical enforcement is Claude Code's, deliberately.

## The fine print

Two different guarantees, never confused:

- **Mechanical** (hooks): *when* the agent may stop, and *what* you forbade — leak a secret, ask
  mid-run, touch a command on your list, or quietly clock out with work outstanding.
- **Convention** (contract + skill): the quality of the work behind a tick. The item gate raises
  the bar where you have tooling — and **no lint / no tests is a first-class path**, not a
  degraded one.

Read this before you trust it overnight:

- **The list is built with you; the shift runs without you.** Drafting, `/nightshift:quality` and
  `/nightshift:hunt` are desk work — that is where the night's quality is decided, and none of it
  arms anything. `/nightshift:start` is the boundary: from there the gate will not let the agent
  stop and the ask-tool is denied, which is what you want at 3am and pure friction at 3pm. Arm it
  when you're leaving.
- **Esc still means stop, watchman or not.** Your interrupt is recorded in the session
  transcript, and the watchman reads it before reviving anything: an Esc-paused session is stood
  by, not resumed. What gets revived is a session that *died* — or errored with nobody there. If
  the transcript cannot be read it assumes the 500, not the Esc: waking a paused session costs an
  apology, a lost night costs the night.
- **Ticks are self-certified.** The gate re-injects the full working standard — no stubs, gate
  green, never fake a tick — at every stop attempt, so it never decays out of context; what it
  proves is that the agent couldn't quietly stop with work outstanding, not that the work behind
  a tick is good. The contract and your item gate raise that bar; they don't eliminate the gap.
- **Completion beats cost by default.** A stuck run is held and red-flagged, not ended — so a
  finite list with no deadline can keep retrying until you look in. Bound it when cost matters
  more: `NIGHTSHIFT_STALL_MAX=N` clocks out a stuck run, an open-ended walkthrough *requires*
  hours (`start` refuses to run one without a deadline), and the gate enforces quitting time
  mechanically.
- **The stall guard reads ticks + commits as progress** — so an agent that commits failed attempts
  can look alive. Your item gate mitigates this; the deadline caps it regardless.
- **The guards are pattern matches, not a sandbox.** Deny rules match the command text — they keep
  a well-meaning agent from drifting, not a determined adversary out. Keep reviewing commits, and
  try your first shift on a scratch repo before pointing it at anything sensitive.
- **The stop-work order is always available** — `/nightshift:stop` or `touch .nightshift/STOP` —
  so a shift can never trap you.

## Development

Tests, lint, coverage, plugin validation and the release process: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Prior art

Anthropic's official **ralph-loop** plugin (after Geoffrey Huntley's *ralph* technique) proved both
the demand and the mechanism: keep the agent running until it says a completion phrase. nightshift
exists for what comes after — *ralph keeps Claude running; nightshift makes the running accountable.*

## License

[MIT](LICENSE) © [Orwa Mahmoud](https://orwamahmoud.com)
