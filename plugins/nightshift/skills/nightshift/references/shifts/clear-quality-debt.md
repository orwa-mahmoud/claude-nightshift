# Clear quality debt — finite — the backlog your tools already know about

The finite counterpart to the hunts: the work is a list your own tooling produces, so it ends when
that list is clear. Quality uses this entry in either launch mode: Review first scans without writes
and waits for an explicit disposition; Run directly composes, arms, and works the findings without
a second pause.

In **artifact mode** (a non-Git folder with supplied documents or reports), inspect owner files
only. Resolve the source policy with a receipt from `receipt-templates.md`, validate
supplied exports with a receipt from `receipt-templates.md`, redact untrusted material
with a receipt from `receipt-templates.md` before ranking findings, and complete with
a receipt from `receipt-templates.md` plus write-receipt into `$NS/receipts/`.
Never require git, a package manager, or repository tooling. Do not `git init` a notes folder.

## Data-quality mode

Requires named domain rules the owner supplied. Run a receipt from `receipt-templates.md`
before ranking dataset issues. Validate against those rules only — never infer business data rules
from type definitions alone.

```text
- [ ] **Clear quality debt — fix what the project's own tooling reports.**
  - Scan first: in data-quality mode run a receipt from `receipt-templates.md` with the
    owner-supplied domain rules before the quality scan. In repository mode run the item-gate
    commands from `## Gates` in report mode (lint,
    types, tests), per top-level package in a monorepo. Unparsed tool output is unavailable,
    never "no findings". In artifact mode scan supplied documents in the skill instead of inventing
    repository tools. Normalize findings in a receipt,

    dedupe by root cause while retaining every source, and rank into one coherent queue. Record
    unavailable tools honestly.
  - Baseline before the first fix cluster with a receipt from `receipt-templates.md`; after each cluster
    re-scan and score with a receipt from `receipt-templates.md` under the shift policy completion mode.
  - Work one cluster per cycle: fix the root cause behind the item gate, commit, re-scan.
  - Never silence instead of fixing — no new suppressions, no relaxed config, no deleted tests. A
    finding the owner should decide on goes to parking-lot.md with a default, and work continues.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected) and the ranked quality queue so a
    rejected finding is not raised a second time.
  - Ends when a full scan reports nothing new, or at quitting time if hours were set.
  - Verify: the item gate is green at every commit; evidence-compare passes for the chosen
    completion mode (clear-all or no-regression-plus-selected-debt) before clock-out.
```
