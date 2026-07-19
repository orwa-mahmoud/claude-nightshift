# Walkthrough item

Paste ONE of these into `## Items` — or let `/nightshift:hunt` stage it for you. A walkthrough is a
single open box: it stays open while the loop runs and closes only at its honest end — converged,
or the whistle. `/nightshift:start` asks for hours whenever the list contains a walkthrough; it has
no natural end but the clock, so it may not start without a deadline.

All presets share the loop — scan → verify → fix behind the item gate → re-scan — and log one line
per cycle to `shift-log.md` (`cycle N · <scanned> · <found> · <fixed>`). They differ in the scan,
and in the ending: the hunts may converge; the standing loop ends at nothing but the whistle.

## Coverage hunt — "give it the night, wake up to tests"

```text
- [ ] **Coverage hunt — add meaningful tests until quitting time.**
  - Each cycle: find the highest-value untested behaviour, write real tests for it, run the item
    gate, commit. Coverage is a tripwire, never a target — no padding tests to move a number; any
    exclusion needs a written reason.
  - Log one line per cycle. Stop only at quitting time, then clock out orderly.
  - Verify: the item gate is green at every commit.
```

## Defect hunt — the review cycle, ridden to convergence

```text
- [ ] **Defect hunt — review, fix, re-review until it converges.**
  - Each cycle: review for defects; dedupe every finding against snag-log.md (ALL seen — fixed and
    rejected) so a later cycle never re-reports an earlier one; fix each behind the item gate;
    append dispositions; re-review.
  - Stop at the first honest ending: a full pass finds nothing NEW (converged), or quitting time.
    Zero new findings is success — stop even with time on the clock.
  - Verify: the item gate is green at every commit; snag-log.md dispositions are current.
```

## Standing loop — improve and discover until quitting time

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
