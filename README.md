# nightshift

> **Claude works the night shift: it can't clock out until the punch list is done — and the site
> has safety rules.**

A [Claude Code](https://claude.com/claude-code) plugin for long, unattended runs (hours → days).
You write the checklist. Hooks keep the agent on site until every box is ticked, under rules you
set and it can't bend. You go to sleep.

## The screen that made me build nightshift

![An agent checkpoint: the smaller fixes shipped, the bigger items deferred in the agent's own
words — and a question that has been waiting since the night before](docs/the-morning-screen.png)

I asked for eight things and stepped away. That screen is what I came back to:

- the four **easiest** items — done, shipped, wrapped in a proud little table ✅
- the four **hard** ones — "these deserve a focused session, I don't want to rush them"

Buddy. *This* is the focused session. You're alone. It's just you and the list. What else is on
your calendar tonight??

And that's the mild night. The other two, every developer knows:

**The 02:40 question.** Ten hours of overnight work, planned. You go to bed. At 02:40 it stops:
"quick question before I continue." At 08:00 it's still waiting for the answer. The window is
gone; the work isn't done. And if your credit reset that morning — congratulations: last week's
quota died unused, and the same items will now eat the new week's.

**The review loop.** "Review this" — to the same model that wrote the code an hour ago. Twenty
findings. You fix them, ask again: twenty *new* findings. Where were these twenty the FIRST
time?? You spend the whole evening as a mailman between the model and itself, one "check it
again" at a time.

## What nightshift does about it

All three nights end the same way now: you sleep, it works, and your first look in the morning is
at a serious product — not a half-done prototype full of shortcuts.

- **Completion lives in a file, not a phrase.** The shift ends when every `- [ ]` in the punch
  list is ticked — per-item, persistent, greppable. A crashed session resumes from the file.
- **Your rules are laws, not suggestions.** Nothing is blocked out of the box; whatever *you*
  forbid, hooks deny mechanically: `git push` for the night, `rm -rf`, commits that touch a
  protected folder, diffs that smell like secrets, commits under the wrong identity. The agent
  *can't*, not *shouldn't*.
- **Questions get parked, not asked.** Mid-shift the ask-the-user tool is denied; the question
  lands in `parking-lot.md` with a sensible default chosen, and work continues. Watching live?
  Type your answer any time and it's applied. Asleep? Review the parked calls over coffee.
- **A stuck run is held, not sent home.** No-progress stop attempts get red-flagged in the shift
  log while the gate keeps the shift open — you wake to a flagged stall, not an early clock-out.
  Prefer a hard cap? One env var (`NIGHTSHIFT_STALL_MAX=N`), and the deadline bounds the night
  regardless.
- **You're never trapped.** Escape and Ctrl+C still work — it's your keyboard, the plugin can't
  override it. But a pause isn't an ending: the next session resumes the shift, and a headless
  run or the foreman loop has no Escape at all. `touch .nightshift/STOP` from any terminal is the
  real stop-work order: it ends the shift itself — the gate releases, foreman halts, receipts
  written. Open boxes stay open — a true snapshot of where it stopped.
- **Receipts, not vibes.** Timestamps, per-item commits, cycle logs — versioned in a local
  receipts repo inside `.nightshift/` that never touches your project's history (ignored by
  default; no remote, never pushed).

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
- **The two classics.** Add real test coverage overnight, or ride the review → fix loop until a
  full pass finds nothing new. Both ship as ready-made walkthroughs.

If you can write it as a checklist, you can hand it to the night.

## Install

Two commands inside Claude Code — no servers, no tokens, nothing to download:

```text
/plugin marketplace add orwa-mahmoud/claude-nightshift
/plugin install nightshift
```

Then:

```text
/nightshift:setup      # scaffold .nightshift/ + propose quality gates (ask, never impose)
/nightshift:quality    # optional: turn existing lint/type debt into proposed items
# write your items in the punch list — one checkbox per task
/nightshift:start      # hours asked only for open-ended work; then go to sleep
/nightshift:status     # morning: what got done, what got parked, what got stuck
# you review the local commits and push — or forbid pushing outright (one env line below)
```

Panic button, any time, from any terminal: `touch .nightshift/STOP`.

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
projects: your run history is yours, ignored by your repo, versioned in its own local receipts
repo.

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
| **coverage hunt** · **defect hunt** | walkthrough presets | the two famous overnight jobs, ready to run |
| **snag log** | `.nightshift/snag-log.md` | findings ledger across runs — cycle 4 never re-reports cycle 1 |
| **parking lot** | `.nightshift/parking-lot.md` | decisions for the human — parked with a default chosen, the run continues |
| **park, don't ask** | hardhat rule | during a shift the ask-tool is denied — the question is parked with a default chosen; answer mid-run in the session and the agent applies it |
| **quality survey** | `/nightshift:quality` | the optional debt audit — existing lint/type findings become proposed items; accept, edit, or decline |
| **drafting table** | `.nightshift/drafting-table.md` | where items are drawn before they're contracted |
| **quitting time** | `.nightshift/deadline` | when the whistle blows, the gate clocks the shift out — "4 hours of credit" is enforced, not hoped |
| **red-tag** | stall guard | a stuck run is flagged in the shift log and held open by default; `NIGHTSHIFT_STALL_MAX=N` clocks it out after N stuck attempts instead |
| **stop-work order** | `.nightshift/STOP` | `/nightshift:stop` — or `touch .nightshift/STOP` from any terminal — halts the site at once |
| **morning whistle** | `NIGHTSHIFT_NOTIFY_CMD` | optional shift-end ping (ntfy / Pushover / `say`) |
| **foreman** | `adapters/foreman.sh` | outer loop for ANY agent CLI — keeps sending the worker back in until the list is clear |

## The two famous shifts

**Defect hunt** — the twenty-findings-every-pass loop from the story above, ridden for you. You
stop playing mailman: every fix goes behind your gates, a snag log makes sure cycle 4 never
re-reports cycle 1, and it stops at one of two clean endings — a full pass finds nothing new
(converged), or the whistle blows (deadline). Either way the bill is capped and the repo is
cleaner than you left it.

**Coverage hunt** — "add test coverage overnight": meaningful tests until the whistle — coverage
is a tripwire, never a target, so no padding tests just to move a number.

Neither is a command — both ship as ready-made items in
[`walkthrough-item.md`](skills/nightshift/references/walkthrough-item.md): paste one into your
punch list, and `/nightshift:start` will demand the hours (a walkthrough may not start without a
deadline — that's your cost cap).

## Owner knobs

Zero-config by default; every knob below is off until you set it (unset ⇒ the default described):

| Env var | Effect |
|---|---|
| `NIGHTSHIFT_FORBIDDEN_COMMANDS` | deny any Bash command matching this `grep -E` pattern during a shift — your own site rules. `git push` keeps pushing yours for the night; `rm -rf\|docker\|terraform` fences the rest. Env vars are fixed at session start, so only you can set or lift a rule — never the agent mid-run |
| `NIGHTSHIFT_EXPECTED_EMAIL` | deny commits authored under any other identity |
| `NIGHTSHIFT_PROTECTED_DIRS` | space/pipe-separated dir names never to `git add/commit/tag/remote` |
| `NIGHTSHIFT_NEVER_COMMIT_PATTERNS` | deny a commit whose staged diff matches this `grep -E` pattern |
| `NIGHTSHIFT_STALL_MAX` | by default a stuck agent is held and red-flagged in the shift log, never clocked out; set `=N` to clock the shift out after N stuck attempts. The foreman honors the same knob for its loop (`--stall N` is the CLI form) |
| `NIGHTSHIFT_NOTIFY_CMD` | shift-end ping; runs with `$NIGHTSHIFT_SUMMARY` set (e.g. `say "$NIGHTSHIFT_SUMMARY"`) |

**Changed in v0.3.0:** by default a stalled agent is now held and red-flagged, never clocked out —
in the clock-out gate and in the foreman loop alike. Set `NIGHTSHIFT_STALL_MAX=N` to restore
auto-clock-out after N stuck attempts.

## Recommended layout

nightshift works in-place on any repo — state is gitignored and versioned in its own local
receipts repo, so your project history stays clean either way. For hard separation, run it from a
plain workspace folder that contains your repo:

```text
my-project/            ← plain folder, not a repo — open Claude Code here
├── repo/              ← your actual git repo (the only thing that pushes)
├── .nightshift/       ← run state + receipts, entirely outside your repo
└── .claude/           ← your local Claude Code config
```

Outside the repo, run state can never be committed by any mistake — separation by construction,
not configuration. (This repo is built exactly this way.)

## Best on Claude Code. Works anywhere a terminal works.

The methodology (punch list, parking lot, snag log) is plain markdown + git — any agent can follow
it. The mechanical enforcement is Claude Code-native today; for every other agent CLI, **foreman**
moves the loop outside the agent:

```bash
adapters/foreman.sh --agent "codex exec --full-auto" --deadline "07:00" --max-iterations 50
```

While the punch list has open boxes and the deadline hasn't passed, it re-invokes the agent — and
because each iteration's only memory is the files, it's crash-proof by design. The hooks block a
*polite* early quit; foreman revives a *dead* one (crash, rate limit, context exhaustion at 3am).
They compose: run foreman around `claude -p` for a truly bulletproof overnight.

## The fine print

Two different guarantees, never confused:

- **Mechanical** (hooks): *when* the agent may stop, and *what* you forbade — leak a secret, ask
  mid-run, touch a command on your list, or quietly clock out with work outstanding.
- **Convention** (contract + skill): the quality of the work behind a tick. The item gate raises
  the bar where you have tooling — and **no lint / no tests is a first-class path**, not a
  degraded one.

Read this before you trust it overnight:

- **Ticks are self-certified.** The gate checks *boxes*, not *work* — it guarantees the agent
  can't quietly stop with work outstanding, not that a ticked box is truly done. The contract and
  your item gate raise that bar; they don't eliminate the gap.
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

```bash
bats tests/                          # test suite — brew install bats-core / apt-get install bats
shellcheck hooks/*.sh adapters/*.sh  # lint
tests/coverage.sh                    # line coverage via kcov (runs in docker on non-Linux)
claude plugin validate . --strict    # manifest + marketplace validation
```

CI ([`ci.yaml`](.github/workflows/ci.yaml)) runs shellcheck, the bats suite, and plugin
validation on every push.

**Releasing:** installs are pinned to `version` in `.claude-plugin/plugin.json` — users receive
updates only when it changes. Bump the version, then tag.

## Prior art

Anthropic's official **ralph-loop** plugin (after Geoffrey Huntley's *ralph* technique) proved both
the demand and the mechanism: keep the agent running until it says a completion phrase. nightshift
exists for what comes after — *ralph keeps Claude running; nightshift makes the running accountable.*

## License

[MIT](LICENSE) © Orwa Mahmoud
