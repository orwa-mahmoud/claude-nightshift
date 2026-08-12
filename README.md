# nightshift

> **Give Claude a checklist before bed. It can't clock out until every box is ticked, never stalls
> on a question, and revives itself if the API dies at 3 AM.**

A [Claude Code](https://claude.com/claude-code) plugin for long, unattended runs (hours → days) —
a harness for the accountability half of an agent loop. You write the checklist. Hooks keep the
agent on site until every box is ticked, under rules you set and it can't bend. You go to sleep.

Overview and FAQ: <https://orwamahmoud.com/nightshift/>

## Install

Two commands inside Claude Code — no npm, no Homebrew, no separate CLI, no API keys, no server:

```text
/plugin marketplace add orwa-mahmoud/claude-nightshift
/plugin install nightshift
```

Also runs on **OpenAI Codex** — same package, same skills, its own hook wiring:

```text
codex plugin marketplace add orwa-mahmoud/claude-nightshift
codex plugin add nightshift@nightshift
```

The clock-out gate, the guards, the skills and crash revival are live-verified on Codex — a
killed session is resumed into its own conversation, same as on Claude Code. One boundary
remains: a Codex session that is alive but wedged on an API error is left alone until that
signature has been observed in the wild.

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
session dies, the punch list stops where it stood, and this is the screen you wake up to:

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

- **Two days left in the cycle, 80% of your credit unspent.** It doesn't roll over — and you do
  not need a backlog ready to spend it. `/nightshift:hunt` offers a ready-made shift, writes it as
  the punch list, and the night turns the credit into tests, fixes or upgrades you would otherwise
  have lost.
- **The API is throwing 500s and you are about to leave.** Write the items, start the shift, and
  go. The first call comes back `API Error: 500` and nothing runs — the watchman keeps knocking
  all night, and picks up that same conversation the moment the API answers.
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

## The ready shifts

You do not have to invent the night's work. `/nightshift:hunt` reads the catalog, offers what it
finds — test coverage, a review loop ridden to convergence, your lint and type debt, dependency
upgrades, security advisories, a standing improve-and-discover loop — and writes the one you pick
as a work order: the item plus its hours, parked with the clock not running. Say the word and it
cuts the order into the punch list and the gate takes over.

Each entry declares how it ends. **Open-ended** ones have no natural end but the clock, so hunt
requires hours and a walkthrough never runs without a cost cap. **Finite** ones work a list your
own tooling produces and end when it is clear, so hours are a cap rather than a requirement.

The entries live one per file in
[`shifts/`](plugins/nightshift/skills/nightshift/references/shifts/) — read that directory for the current set
and the exact contract of each. Nothing enumerates them, deliberately: a page listing the catalog
would put every contributor in the same diff.

**Running a night that isn't in there? Add it.** An entry is markdown — no hooks, no code — and
lands as its own file, so nothing you write collides with anyone else's.
[`CONTRIBUTING.md`](CONTRIBUTING.md) has the recipe, and shift entries are the contribution most
likely to be merged.

## Reference

- [**Command reference**](docs/commands.md) — every slash command, what it asks, and the offline
  paths that need no session.
- [**Owner knobs**](docs/knobs.md) — every rule you can set for a shift, and what each one denies.
- [**Vocabulary**](docs/vocabulary.md) — the words nightshift uses for its own parts, and the file
  behind each one.

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
- **Esc is Claude's stop; Codex has none.** On Claude Code your interrupt is recorded in the
  session transcript, and the watchman reads it before reviving anything: an Esc-paused session
  is stood by, not resumed. What gets revived is a session that *died* — or errored with nobody
  there. If the transcript cannot be read it assumes the 500, not the Esc: waking a paused
  session costs an apology, a lost night costs the night. Codex records no owner interrupt, so
  closing an interactive Codex session with open boxes hands the night to the watchman —
  `/nightshift:stop` or `touch .nightshift/STOP` is the stop-work order on every host.
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

## Roadmap

**Codex support** is complete for the night: gate, guards, skills, scheduling and the watchman
all run on OpenAI Codex from the same package. The one open edge is wedge detection — a Codex
session alive at an API error is stood by, not revived, until that transcript signature has been
observed in a real outage — see
[#41](https://github.com/orwa-mahmoud/claude-nightshift/issues/41).

## Development

Tests, lint, coverage, plugin validation and the release process: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

[MIT](LICENSE) © [Orwa Mahmoud](https://orwamahmoud.com)
