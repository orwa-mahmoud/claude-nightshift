# nightshift

> **Claude works the night shift: it can't clock out until the punch list is done — and the site
> has safety rules.**

## What it does

nightshift lets Claude Code work through a local punch list unattended. It adds:

- a **completion gate** — the session cannot end while the list has open items
- **mechanical safety hooks** — your own site rules, enforced: forbidden commands, no secrets in
  commits, no mid-run questions
- **stall and deadline protection** — a stuck run is red-flagged and held for your review; an
  overlong one clocks out at the deadline you set
- **local receipts** for every run — commits, timestamps, cycle logs

## Why

Two nights every developer knows:

**The question that killed the run.** You planned ten hours of overnight work with Claude — and
went to bed. At 02:40 it stopped to ask a question. At 08:00 it was still waiting for the answer.
The window was gone; the work wasn't done.

**The loop that ate the evening.** You built the prototype and asked the AI to review it before
testing: 20 findings. You fixed them, asked again: 20 more. You spent the whole evening
babysitting the cycle, one "check it again" at a time.

nightshift ends both the same way: you sleep, it works, and your first look in the morning is at a
serious product — not a half-done prototype full of shortcuts. It's a
[Claude Code](https://claude.com/claude-code) plugin for long, unattended runs (hours → days) that
makes autonomy **accountable**:

- **Completion lives in a file, not a phrase.** The shift ends when every `- [ ]` in the punch list
  is ticked — per-item, persistent, greppable. A crash resumes from the file.
- **Safety is enforced, not requested — and every rule is yours.** Nothing is blocked out of the
  box. Whatever you forbid, hooks mechanically deny: any command on your forbidden list
  (`git push` is the classic one-liner), protected-folder commits, secret-pattern leaks, commits
  under the wrong identity — the agent *can't* do the dangerous thing, not merely *shouldn't*.
- **A question can't kill the run — and you lose no control.** During a shift the ask-the-user tool
  is denied; the question is parked in `parking-lot.md` instead, with the most defensible default
  chosen, and the work continues. Watching the run live? Type an answer into the session at any
  moment — the agent picks it up and applies it directly. Asleep? Review the parked decisions over
  coffee.
- **A stuck run is held, not sent home.** Repeated stop-attempts with zero progress red-flag the
  shift in the log while the gate keeps it open — you wake to a flagged stall, never to an early
  clock-out with work outstanding. Want a hard cap instead? `NIGHTSHIFT_STALL_MAX=N` clocks the
  shift out after N stuck attempts, and the deadline bounds the night regardless.
- **You're never trapped.** `touch .nightshift/STOP` from any terminal ends the shift at once;
  unfinished boxes stay honestly unfinished.
- **Every run leaves receipts — without polluting your repo.** Timestamps, per-item commits, cycle
  logs — versioned in a local receipts repo inside `.nightshift/` that never touches your project's
  history (ignored by default; no remote, never pushed).

## nightshift was built by nightshift

This repo was built by the exact mechanism it ships: an enforced punch list guarded every build
session, and the hooks refused to let it clock out early. The receipts:

- **the commit history** — every punch-list item landed as its own conventional commit; read the
  log, see the shift (`git log --oneline`);
- **the self-build snapshot** — the final punch list + shift log: [`examples/self-build.md`](examples/self-build.md).

The live `.nightshift/` state stays out of this repo — the same default nightshift sets for your
projects: your run history is yours, ignored by your repo, versioned in its own local receipts repo.

## Install

Two commands inside Claude Code — no servers, no tokens, nothing to download:

```text
/plugin marketplace add orwa-mahmoud/claude-nightshift
/plugin install nightshift
```

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

## Quickstart

```text
/nightshift:setup      # scaffold .nightshift/ + propose quality gates (ask, never impose)
/nightshift:quality    # optional: turn existing lint/type debt into proposed items
# write your items in the punch list — one checkbox per task
/nightshift:start      # hours asked only for open-ended work; then go to sleep
/nightshift:status     # morning: what got done, what got parked, what got stuck
# you review the local commits and push — or forbid pushing outright (one env line below)
```

Panic button, any time, from any terminal: `touch .nightshift/STOP`.

## The two famous shifts

**Defect hunt** — the review loop from the top of this page, run for you. nightshift rides the review
→ fix cycle alone — every fix behind your gates, a snag log so cycle 4 never re-reports cycle 1 — and
stops at one of two honest endings: a full pass finds nothing new (converged), or the whistle blows
(deadline). Either way the bill is capped and the repo is cleaner than you left it.

**Coverage hunt** — "add test coverage overnight": meaningful tests until the whistle — coverage is a
tripwire, never a target, so no padding tests just to move a number.

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

nightshift works in-place on any repo — state is gitignored and versioned in its own local receipts
repo, so your project history stays clean either way. For hard separation, run it from a plain
workspace folder that contains your repo:

```text
my-project/            ← plain folder, not a repo — open Claude Code here
├── repo/              ← your actual git repo (the only thing that pushes)
├── .nightshift/       ← run state + receipts, entirely outside your repo
└── .claude/           ← your local Claude Code config
```

Outside the repo, run state can never be committed by any mistake — separation by construction, not
configuration. (This repo is built exactly this way.)

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

## Honest by design

Two different guarantees, never confused:

- **Mechanical** (hooks): *when* the agent may stop, and *what* you forbade — leak a secret, ask
  mid-run, touch a command on your list, or quietly clock out with work outstanding.
- **Convention** (contract + skill): the quality of the work behind a tick. The item gate raises the
  bar where you have tooling — and **no lint / no tests is a first-class path**, not a degraded one.

Read this before you trust it overnight:

- **Ticks are self-certified.** The gate checks *boxes*, not *work* — it guarantees the agent can't
  quietly stop with work outstanding, not that a ticked box is truly done. The contract and your item
  gate raise that bar; they don't eliminate the gap.
- **Completion beats cost by default.** A stuck run is held and red-flagged, not ended — so a
  finite list with no deadline can keep retrying until you look in. Bound it when cost matters
  more: `NIGHTSHIFT_STALL_MAX=N` clocks out a stuck run, an open-ended walkthrough *requires*
  hours (`start` refuses to run one without a deadline), and the gate enforces quitting time
  mechanically.
- **The stall guard reads ticks + commits as progress** — so an agent that commits failed attempts
  can look alive. Your item gate mitigates this; the deadline caps it regardless.
- **The guards are pattern matches, not a sandbox.** Deny rules match the command text — they stop
  an honest agent from drifting, not a determined adversary. Keep reviewing commits, and try your
  first shift on a scratch repo before pointing it at anything sensitive.
- **The stop-work order is always available** — `/nightshift:stop` or `touch .nightshift/STOP` — so a
  shift can never trap you.

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
