# Shift catalog

The ready shifts `/nightshift:hunt` offers. Each entry is a punch-list item, complete with its own
contract and Verify line — paste one into `## Items` by hand, or let hunt assemble it for you.

Two endings exist, and every entry declares which it has:

- **Open-ended** — no natural end but the clock. It stays a single open box while its loop runs and
  closes at the whistle (or at convergence, where the entry says so). `/nightshift:hunt` requires
  hours for these; a walkthrough may not start without a deadline.
- **Finite** — the work is a known list. It ends when the list is clear. Hours are optional: a cap,
  not a requirement.

Open-ended entries share the loop — scan → verify → fix behind the item gate → re-scan — and log one
line per cycle to `shift-log.md` (`cycle N · <scanned> · <found> · <fixed>`). They differ in the scan
and in the ending.

**Adding an entry:** see `catalog-recipe.md` in this directory. An entry that does not declare its
ending, its definition of done, and what it will never do is not reviewable, and will not be merged.

## Coverage hunt — open-ended — "give it the night, wake up to tests"

```text
- [ ] **Coverage hunt — add meaningful tests until quitting time.**
  - Each cycle: find the highest-value untested behaviour, write real tests for it, run the item
    gate, commit. Coverage is a tripwire, never a target — no padding tests to move a number; any
    exclusion needs a written reason.
  - Log one line per cycle. Stop only at quitting time, then clock out orderly.
  - Verify: the item gate is green at every commit.
```

## Defect hunt — open-ended — the review cycle, ridden to convergence

```text
- [ ] **Defect hunt — review, fix, re-review until it converges.**
  - Each cycle: review for defects; dedupe every finding against snag-log.md (ALL seen — fixed and
    rejected) so a later cycle never re-reports an earlier one; fix each behind the item gate;
    append dispositions; re-review.
  - Stop at the first honest ending: a full pass finds nothing NEW (converged), or quitting time.
    Zero new findings is success — stop even with time on the clock.
  - Verify: the item gate is green at every commit; snag-log.md dispositions are current.
```

## Standing loop — open-ended — improve and discover until quitting time

The greedy one: no convergence ending. An empty cycle is not "done" — it means the lens was too
shallow. For when there is credit and hours, and the job is "make the product better".

```text
- [ ] **Standing loop — improve and discover until quitting time.**
  - Open-ended: the deadline is the ONLY thing that ends this item. A cycle that finds nothing
    means the lens was too shallow — go deeper (a new subsystem, a new entry point, a new user
    path) and start the next cycle at once. Never idle between cycles.
  - Each cycle pick 1–2 fresh lenses and rotate — never repeat the same shallow pass:
    - Real bugs — trace one concrete user scenario end-to-end through every layer: races,
      permission holes, stale state after mutations, timezone and edge inputs.
    - UX friction — dead ends, hidden state, missing empty/loading/error states, too many clicks
      to high-frequency work.
    - Performance — hot-path waste, N+1 queries, missing indexes, chatty endpoints, needless
      re-renders.
    - Contracts — type drift between layers, duplicated enums out of sync, permission gating
      parity on both sides (fail closed).
    - Dead code — verify truly unreachable first, then delete fully; never stub.
  - If the project has a UI, walk it live every few cycles with real clicks and the console open —
    code-only scans miss what clicking finds.
  - At every site inspection (the interval in `## Gates`; hourly if none is set), run the
    project's quality tooling in report mode and feed new findings into the next cycle.
  - Dedupe every finding against snag-log.md (ALL seen — fixed and rejected) before acting; append
    dispositions after. Park owner decisions in parking-lot.md and keep working.
  - Verify: the item gate is green at every commit; one conventional commit per coherent fix.
```

## Clear quality debt — finite — the backlog your tools already know about

The finite counterpart to the hunts: the work is a list your own tooling produces, so it ends when
that list is clear. `/nightshift:quality` runs the same scan read-only and proposes items without
starting anything; this entry works them.

```text
- [ ] **Clear quality debt — fix what the project's own tooling reports.**
  - Scan first: run the item-gate commands from `## Gates` in report mode (lint, types, tests),
    per top-level package in a monorepo. Cluster the findings by tool and directory.
  - Work one cluster per cycle: fix the real cause behind the item gate, commit, re-scan.
  - Never silence instead of fixing — no new suppressions, no relaxed config, no deleted tests. A
    finding the owner should decide on goes to parking-lot.md with a default, and work continues.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected) so a rejected finding is not raised
    a second time.
  - Ends when a full scan reports nothing new, or at quitting time if hours were set.
  - Verify: the item gate is green at every commit.
```
