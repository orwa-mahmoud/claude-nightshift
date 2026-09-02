# Data migration — finite — schema and data changes in approved environments only

Use when the owner names a data or schema migration with backfill, locks, defaults/nullability,
representative data, and rollback requirements. Execute data operations only in disposable or
specifically owner-approved environments; production/destructive work stays outside normal
direct-mode authority.

Supported on repository mode with a data migration plan. Never select this entry in artifact mode.

```text
- [ ] **Data migration — apply or verify a bounded data migration safely.**
  - Discovery: record environment (disposable vs owner-approved vs production). Run
    `runtime/migration-evidence.sh data-safety` on the operation list: backfill, locks,
    defaults/nullability, idempotency, rollback, and representative data coverage. Run
    `runtime/migration-evidence.sh production-refusal` before any execute step.
  - Perform only operations where `mayExecuteDataOperations` is true. On mid-migration failure,
    follow `midMigrationRecovery` — rollback when available, otherwise park for the owner.
  - Never execute unsupported data semantics; never run destructive production work in direct mode
    without explicit owner approval in scope.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when operations complete in an approved environment, or every blocker is parked with
    rollback documented, and production refusal remains enforced.
  - Verify: the item gate is green at every commit; data-safety `mayExecuteDataOperations` matches
    the environment used; unsupported semantics are parked not guessed.
```
