# Walkthrough item

Paste ONE of these into `## Items`. A walkthrough is a single open box: it stays open while the loop
runs and closes only at its honest end — converged, or the whistle. `/nightshift:start` asks for
hours whenever the list contains a walkthrough; it has no natural end but the clock, so it may not
start without a deadline.

Both presets share the loop — scan → verify → fix behind the item gate → re-scan — and log one line
per cycle to `shift-log.md` (`cycle N · <scanned> · <found> · <fixed>`). They differ only in the scan.

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
