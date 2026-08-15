# Owner walkthrough — open-ended — pursue one owner-supplied objective until quitting time

A custom hours-cycle for a goal the owner names. Nightshift keeps the objective verbatim, derives
the next concrete unit from the repository, and implements, verifies, and reassesses until the
clock ends the shift.

**Selection:** Guided only. Never select this entry in Automatic mode: its objective must come
directly from the owner, not from repository discovery. Do not combine it with another open-ended
entry; this walkthrough owns the shift's single continuation record.

**Owner instructions:** Required. The guided scope answer is the objective, not optional tailoring.
If it is empty, do not compose, cut, or arm the shift.

Supported on a real project workspace whose objective can be advanced through local, reviewable
engineering work. Publishing, deployment, spending, real-data mutation, secrets, and legal or
licensing decisions remain outside the coding-work authorization.

```text
- [ ] **Owner walkthrough — pursue the owner's objective until quitting time.**
  - Ending: open-ended — hours and a deadline are required.
  - Objective: the Owner instructions attached by Hunt are authoritative and must remain verbatim.
    Never replace them with an easier, narrower, or merely adjacent goal.
  - Isolate first: work on a dedicated nightshift branch, never the default branch. Never merge,
    push, open a PR, deploy, publish, or mutate an external service unless the owner explicitly
    authorized that exact action.
  - Establish the continuation record before implementation: use the single `Status: building`
    entry in opportunity-map.md. Preserve the owner objective in Scope, derive observable
    Acceptance from it and the repository, and record Current phase, Completed, Decisions,
    Rejected, Next, and Verify remaining. If a building entry already exists for this objective,
    resume its exact Next action before exploring again. Never open a second building entry.
  - Each cycle: inspect current repository evidence and the continuation record, choose the
    strongest coherent unit that advances the objective and fits the remaining time, implement it
    end-to-end, run the item gate, commit separately, then refresh the continuation record and
    reassess. Prefer completing one reviewable path over starting several partial ones.
  - Verification comes from the objective, repository-owned tests and tooling, and the configured
    item gate. Never weaken a test, suppress a finding, or redefine acceptance merely to claim
    progress. The item gate must be green at every commit.
  - Keep the continuation record current at meaningful boundaries: after design, a coherent
    implementation step, a stable decision, a commit, or a verification-state change. Record the
    exact next action and remaining verification so compaction or revival can continue without
    reconstructing the conversation. Do not rewrite it after every command.
  - Park genuine owner decisions with the strongest sensible reversible default and continue.
    Stop for the owner only when the action falls outside the authorized coding-work boundary.
  - Large work is allowed; an incoherent stopping point is not. Do not begin a unit that cannot be
    left reviewable within the remaining time. Never manufacture busywork after the objective is
    satisfied; deepen its verification, remove objective-related defects, or improve the same
    path without expanding into unrelated work.
  - Open-ended: quitting time is the normal ending. At the whistle, finish the coherent unit in
    hand, leave the branch green, update the continuation record, and write a morning handoff with
    delivered commits, decisions, remaining work, exact Next, and Verify remaining. The owner's
    stop-work order remains available and leaves open work honestly open.
  - Verify: the item gate is green at every commit; each delivered unit advances the verbatim
    owner objective; opportunity-map.md and the morning handoff identify the exact current state.
```
