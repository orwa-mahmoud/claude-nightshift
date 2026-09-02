# Pull-request readiness — finite — scoped change set ready for human review

Use when the owner names one branch or change set and wants it checked against acceptance criteria,
repository rules, review comments, tests, docs, and security before a human approves or merges.
Nightshift fixes supported gaps and leaves a review map; it never submits a review, approves, pushes,
merges, or closes issues without explicit owner authority.

Supported on repository mode only unless a clearly useful artifact-only review input exists. Route
generic code review requests elsewhere. Typical hours: 2–4.

```text
- [ ] **Pull-request readiness — prepare a named change set for human review.**
  - Discovery: anchor to the named branch or change set, linked issue or acceptance criteria,
    repository rules, diff scope, supplied review comments, compatibility notes, tests, docs,
    packaging, and configured checks. Build the acceptance map with
    `runtime/pr-readiness-evidence.sh acceptance-map`, validate diff scope with `diff-scope`, and
    record owner-only refusals with `owner-action-refusal`. Never search for extra scope or mutate
    GitHub (no review submit, approve, push, merge, close).
  - Fix supported gaps in scope, rerun focused and containing gates, disposition every finding in a
    review map via `runtime/pr-readiness-evidence.sh review-map` (changed areas, acceptance evidence,
    remaining risks, unsupported surfaces, commits, rollback, exact reviewer decisions still needed).
  - One conventional commit per repaired gap when in direct mode; park ambiguous or owner-only items
    in parking-lot.md with reversible defaults.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every scoped gap is fixed, rejected with reason, or parked and containing checks are
    green; the review map is complete and owner-only actions remain refused.
  - Verify: the item gate is green at every commit; review map lists every finding disposition;
    `owner-action-refusal` shows push/merge/approve as refused unless explicit authority was named.
```
