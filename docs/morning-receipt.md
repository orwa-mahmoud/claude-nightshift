# The morning receipt

Everything else in `.nightshift/` is a working file: the punch list changes as items tick, the
parking lot empties as decisions get read, the ledger keeps growing. The morning receipt is the
one file meant to be read once, cover to cover, over coffee. It renders Markdown from records that
already exist — the evidence ledger, the resolved shift policy, `punch-list.md`,
`parking-lot.md`, and `shift-log.md` — and invents nothing. A check that did not run is never
described as passed, and a model's own claim about its work is never upgraded into proof; only a
ledger record, a commit, or a receipt earns a line in the receipt.

`runtime/morning-receipt.sh --project DIR [--view owner|reviewer|release|artifact] [--out PATH]`
(native Windows: `runtime/windows/morning-receipt.ps1`) renders it on demand. The clock-out gate
also writes the owner view automatically, best effort, to
`.nightshift/receipts/morning-<YYYY-MM-DD>-<shiftId>.md` — a failed render never blocks the
shift from ending, and `/nightshift:archive` moves the file with the rest of the night's receipts.
Status prints the first section on request.

## What each section means

1. **Shift** — the shift id, host, and work target; when it started and ended and how it ended
   (done, a stop-work order, quitting time, or a stall); how many items were open versus ticked;
   commits or artifact receipts; and the policy that actually ran — verification level, tooling
   policy, completion mode, and every elevation allowance with its provenance. Three lines always
   appear here, in this order: `Verified:` names what ran green and by which command,
   `Disabled by owner:` names the checks the chosen verification level skipped, and
   `Unavailable:` names any tool or source the ledger or the detector marked unavailable. A
   disabled check is never described as a passed one.
2. **Baseline** — one line per originating source (the tool, its exact command, and its
   environment) with that source's environment digest and raw-output digest, so a reviewer can
   tell exactly what ran and against what versions.
3. **What changed** — the comparison table: every finding classified against its baseline as new,
   cleared, unchanged, regressed, unavailable, a rejected duplicate, parked, or human-only, then
   one line per fix naming the item, its commit or receipt, how to re-verify it, and what the same
   source reported afterward. A tool that failed or went unavailable mid-shift is reported exactly
   that way — never folded into the cleared count.
4. **Parked** — decisions added to the parking lot this shift, each with the default chosen so
   work could continue and how to roll that default back if the owner disagrees.
5. **Unsupported / unmeasured** — surfaces the ledger could not put through the usual pass/fail
   path: human-only judgment calls, unsupported checks, and anything left unmeasured.
6. **Next** — the exact next action, taken from the punch list's open items and, during a long
   product-evolution or owner-walkthrough shift, the single opportunity marked `Status: building`.

Any section with nothing to report is left out entirely rather than printed empty. A zero-gate
`fast` shift with no ledger renders only the Shift section, and its `Verified:` line reads exactly
`Verified: none — verification level none (owner)` — the absence of checks is stated, not implied
by a missing section.

## Which view is for whom

- **owner** (the default) — every section above. Read this one first.
- **reviewer** — sections 2 and 3 only, with every locator intact, for someone re-running the
  verification rather than trusting the tick.
- **release** — section 1 plus a section 3 narrowed to regressions: a release decision needs to
  see the regression count confirmed at zero, not infer it from an empty table.
- **artifact** — sections 1, 4, 5, and 6, for a persistent-folder shift with no repository behind
  it. Commits become receipts and no git terminology appears.

All four views read the same underlying records, so none of them can disagree with another — they
only differ in which sections they show and how much detail survives inside them.

## Determinism

Digests throughout are sha256, hex-encoded. Every table row cites the ledger record id and
locator behind it — nothing in the receipt lacks a source record. Timestamps are UTC
(`%Y-%m-%dT%H:%M:%SZ`) and honor `NIGHTSHIFT_EVIDENCE_NOW` in tests. The bash, PowerShell, and
jq/python renderers produce byte-identical Markdown from the same ledger.
