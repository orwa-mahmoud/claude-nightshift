# Coverage hunt — open-ended — "give it the night, wake up to tests"

A night spent adding behavior-protecting tests against the work-target repository until quitting
time.

Supported on a repository-mode work target that already has a test runner. Never select this entry in artifact mode. Do not `git init` a notes folder to make tests commitable.

```text
- [ ] **Coverage hunt — add meaningful tests until quitting time.**
  - Ending: open-ended — hours and a deadline are required.
  - Never select this entry when work mode is artifact.
  - Map risks first with `runtime/coverage-risk.sh map` from repository evidence: public APIs,
    critical flows, error/retry/timeout/validation/auth/persistence/concurrency/migration paths,
    changed code, local bug history, and low branch/path coverage. Each cluster names the regression
    it catches, chooses the lowest useful test level, demonstrates a red state when practical via
    `coverage-risk.sh red-state`, then reruns focused and containing suites. Coverage percentage
    alone never satisfies the contract — misleading high coverage without mapped behavior is rejected.
  - Use bounded mutation/property/fuzz checks only when detected and allowed by the shift policy;
    report risk protected, not percentage points purchased.
  - Each cycle: pick the highest-priority uncovered cluster, write behavior-protecting tests, log one
    receipt line (`coverage-risk.sh receipt-line`), run the item gate, commit. Coverage is a
    tripwire, never a target — no padding tests to move a number; any exclusion needs a written reason.
  - Log one line per cycle. Stop only at quitting time, then clock out orderly.
  - Verify: the item gate is green at every commit; receipt lines name behavior protected and
    containing suites rerun green — a higher coverage number alone is not completion.
```
