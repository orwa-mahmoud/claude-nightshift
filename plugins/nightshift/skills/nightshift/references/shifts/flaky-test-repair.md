# Flaky-test repair — finite — unstable tests reproduced and repaired without weakening coverage

Tests that sometimes pass and sometimes fail under the repository's existing test runner. The
shift spends a declared repetition budget reproducing each suspect, fixes only demonstrated
causes, and leaves an honest record when the failure cannot be reproduced.

Use only when the project already has a test command and evidence of instability: repeated local
failure, CI history, or a named suspect test. Supported on any stack whose existing test runner can
repeat a test or suite. Do not add a new flake service or test framework.

```text
- [ ] **Flaky-test repair — reproduce unstable tests and fix their demonstrated causes.**
  - Discovery: collect tests with existing flake evidence from CI logs, failure artifacts, or an
    owner-provided list. Dedupe against snag-log.md (ALL seen — fixed and rejected). Before work,
    declare a repetition budget for each suspect using the project's existing runner.
  - Reproduce one suspect within its budget. If it fails, isolate the deterministic cause (shared
    state, ordering, time, randomness, concurrency, environment, or leaked resources), fix that
    cause, run the item gate, commit, then repeat the repaired test for the same budget.
  - If it never fails within the budget, do not claim a repair. Record the commands, run count, and
    outcome in snag-log.md as unreproduced, then move on.
  - Never delete, skip, quarantine, mute, or weaken a test merely to make CI green.
  - Never replace a meaningful assertion with a looser one, add retries as the fix, or hide a race
    by increasing a timeout without evidence that the timeout is the contract.
  - Never exceed the declared repetition budget chasing an unreproduced failure.
  - Ends when every discovered suspect is either repaired and stable for its declared budget or
    recorded honestly as unreproduced with its evidence and commands.
  - Verify: the item gate is green at every commit; each repaired test passes for its full declared
    repetition budget and its containing suite passes once normally.
```
