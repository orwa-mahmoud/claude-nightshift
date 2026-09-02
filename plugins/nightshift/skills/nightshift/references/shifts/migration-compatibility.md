# Migration compatibility — finite — guarded framework, config, and data migrations

Use when the owner names a framework, dependency, API, configuration, or data migration and
supplies authoritative guidance. Nightshift inventories consumers, compatibility surfaces,
persisted state, ordering, rollback, and representative data — then performs only bounded,
reversible repository work with explicit non-goals. Review-first is the default for broad or
irreversible risk; run-direct may apply only when rollback, compatibility tests, and environment
limits are already documented.

Supported on repositories with named migration guidance (release notes, ADR, runbook, schema
migration tool config, or owner-supplied plan) and detectable consumers or config surfaces.
Requires repository mode. Never select this entry in artifact mode. Do not `git init` a notes
folder to simulate migration state.

Schema: `references/schemas/v1/migration-evidence.json`. Build evidence with
`runtime/migration-evidence.sh` from owner-supplied plans, config inventories, and test results.

## Configuration parity mode

Select when environments must agree on configuration shape before or after a migration. Compare
secret **presence and shape only** — never retrieve, echo, or copy secret values. Run
`runtime/migration-evidence.sh config-parity` across named environments and record gaps for the
owner to reconcile outside the shift when values differ.

## Data migration mode

Select when persisted data or schema changes need ordering, backfill, locks, or representative
samples. Run `runtime/migration-evidence.sh data-safety` before any data operation. Execute data
work only in disposable or specifically owner-approved environments; live production and
destructive operations remain outside normal direct-mode authority unless the owner explicitly
approved that exact environment in the punch-list scope.

```text
- [ ] **Migration compatibility — plan and execute a guarded migration with rollback.**
  - Discovery: require a named migration and authoritative guidance before editing. Inventory
    consumers, public compatibility surfaces, persisted state, ordering, defaults/nullability,
    backfill needs, locks, old/new overlap, idempotency, rollback steps, staged changes, and
    representative data with `runtime/migration-evidence.sh migration-inventory`. Classify each
    change with `runtime/migration-evidence.sh compatibility-assess`. When config/env parity is
    in scope, run `runtime/migration-evidence.sh config-parity`. When data or schema migration is
    in scope, run `runtime/migration-evidence.sh data-safety` and
    `runtime/migration-evidence.sh recovery-plan` for mid-migration failure paths.
  - Never select this entry when work mode is artifact.
  - Work one bounded cluster per cycle: additive compatibility fixes, config shape alignment in
    repo-owned files, staged code changes with compatibility tests, then item gate and commit.
    Park breaking, irreversible, production-only, or legal/data-authority questions in
    parking-lot.md with rollback and exact owner decision required.
  - Review-first is the default for breaking or broad migrations. run-direct may perform only bounded,
    reversible repository changes with compatibility tests, explicit non-goals, and a
    documented rollback path.
  - Never guess legal, privacy, or data-retention authority. Never retrieve or copy secret values.
    Never run destructive or production data operations without explicit owner approval for that
    exact environment.
  - Never leave a half-applied migration without a recorded recovery plan and rollback steps.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when `runtime/migration-evidence.sh verdict` reports a finite status, compatibility tests
    cover touched surfaces, rollback is documented, and every breaking or production blocker is
    fixed, rejected with reason, or parked.
  - Verify: the item gate is green at every commit; migration/config/data fixtures pass;
    compatibility-assess distinguishes additive and breaking changes; config-parity compares shape
    only; data-safety refuses live production; recovery-plan covers failed mid-migration paths;
    verdict never claims legal or production authority was inferred.
```
