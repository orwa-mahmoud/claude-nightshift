# Vocabulary

Everything is named from a real construction site — learn one term, guess the rest:

| Term | File / mechanism | Meaning |
|---|---|---|
| **punch list** | `.nightshift/punch-list.md` | construction's final acceptance list — the job isn't done until every item is cleared and signed off |
| **clock-out gate** | Stop hook + `.shift-armed` | the bound session can't clock out while the armed punch list has open Items |
| **hardhat** | PreToolUse hook | mandatory safety equipment — your forbidden commands, protected dirs, secret patterns; denied, not discouraged |
| **process lease** | `.nightshift/.shift-lease` | transient ownership of the active shift process — each watchman recovery advances its generation, admitting the recovered worker and fencing stale processes on the same conversation without locking other tabs |
| **item gate** | per-item commands | work isn't accepted until it passes inspection — once per item, right before its commit |
| **site inspection** | interval commands | the scheduled heavy inspection (coverage, dead code, Sonar) every N items or H hours |
| **walkthrough** | template item | the open-ended scan → fix loop that hunts defects until the clock runs out |
| **hunt** | Nightshift Hunt | writes a ready-made walkthrough as a work order; cuts it into the punch list only on your word |
| **work order** | `.nightshift/work-orders.md` | a prepared job ticket — the item plus its hours, clock not running until the cut |
| **snag log** | `.nightshift/snag-log.md` | findings ledger across runs — cycle 4 never re-reports cycle 1 |
| **product research** | `.nightshift/product-research.md` | dated evidence about the product, users, comparable tools, and unmet needs; conclusions keep their source links |
| **opportunity map** | `.nightshift/opportunity-map.md` | ranked product opportunities with evidence, value, differentiation, effort, reversibility, risk, and an explicit status; its single `building` entry is the resumable current cycle |
| **parking lot** | `.nightshift/parking-lot.md` | decisions for the human — parked with a default chosen, the run continues |
| **park, don't ask** | `toolDeny` question entries | during a shift the host's ask tool is denied with the configured message — the question is parked with a default chosen; an empty native entry allows ask-and-wait instead |
| **quality survey** | Nightshift Quality | the optional debt audit — review findings first or choose a direct run that fixes them |
| **drafting table** | `.nightshift/drafting-table.md` | where items are drawn before they're contracted |
| **issue import** | Nightshift Import issues | copies selected GitHub issues onto the drafting table as quoted source; never searches, never writes back to GitHub |
| **quitting time** | `.nightshift/deadline` | past the deadline, the next stop attempt clocks the shift out and starts nothing new — a whistle, not an axe: it bounds the night without killing work mid-item |
| **red-tag** | stall guard | a stuck run is flagged in the shift log and held open by default; `NIGHTSHIFT_STALL_MAX=N` clocks it out after N stuck attempts instead |
| **stop-work order** | `.nightshift/STOP` | Nightshift Stop — or the platform-native terminal command that creates this file — ends the shift at the agent's next stop attempt; the site rules stay armed until it actually stops |
| **morning whistle** | `NIGHTSHIFT_NOTIFY_CMD` | optional shift-end ping (ntfy / Pushover / `say`) |
| **night watchman** | `plugins/nightshift/runtime/` | one per host and operating-system runtime — after positive death evidence it advances the process lease and resumes its recorded session; host-specific pause and close signals determine when it stands down |
