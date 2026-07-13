# nightshift

> **Claude works the night shift: it can't clock out until the punch list is done — and the site
> has safety rules.**

A [Claude Code](https://claude.com/claude-code) plugin for long, unattended runs (hours → days)
that makes autonomy **accountable**: completion lives in a punch-list file the agent can't clock
out of — not a phrase it says — safety is enforced by hooks rather than requested by prompts, human
decisions are parked instead of blocking, and every run leaves receipts.

## Install

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
| **hardhat** | PreToolUse hook | mandatory safety equipment — no push, no protected-dir commits, no secrets; denied, not discouraged |
| **spot-check** | PostToolUse hook | the inspector checks each piece of work as it lands |
| **item gate** | per-item commands | work isn't accepted until it passes inspection — once per item, right before its commit |
| **site inspection** | interval commands | the scheduled heavy inspection (coverage, dead code, Sonar) every N items or H hours |
| **walkthrough** | template item | the open-ended scan → fix loop that hunts defects until the clock runs out |
| **coverage hunt** · **defect hunt** | walkthrough presets | the two famous overnight jobs, ready to run |
| **snag log** | `.nightshift/snag-log.md` | findings ledger across runs — cycle 4 never re-reports cycle 1 |
| **parking lot** | `.nightshift/parking-lot.md` | decisions for the human — parked with a default chosen, the run continues |
| **park, don't ask** | hardhat rule | during a shift, asking the user is denied — the owner is asleep |
| **drafting table** | `.nightshift/drafting-table.md` | where items are drawn before they're contracted |
| **quitting time** | `.nightshift/deadline` | when the whistle blows, the gate clocks the shift out — "4 hours of credit" is enforced, not hoped |
| **red-tag** | stall guard | a stuck item is pulled out of service and parked, so the shift ends instead of looping to dawn |
| **stop-work order** | `.nightshift/STOP` | `/nightshift:stop` — or `touch .nightshift/STOP` from any terminal — halts the site at once |
| **morning whistle** | `NIGHTSHIFT_NOTIFY_CMD` | optional shift-end ping (ntfy / Pushover / `say`) |
| **foreman** | `adapters/foreman.sh` | outer loop for ANY agent CLI — keeps sending the worker back in until the list is clear |

## Quickstart

```text
/nightshift:setup      # scaffold .nightshift/ + propose quality gates (ask, never impose)
# write your items in the punch list — one checkbox per task
/nightshift:start      # hours asked only for open-ended work; then go to sleep
/nightshift:status     # morning: what got done, what got parked, what got stuck
```

Panic button, any time, from any terminal: `touch .nightshift/STOP`.

## License

[MIT](LICENSE) © Orwa Mahmoud
