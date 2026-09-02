# Provisioning engine contract (frozen)

Shared engine for Auto-add. Skills never embed install logic; they call the helpers.

## CLI

```text
provision.sh --project DIR plan|apply|recover|rollback [--recipe PATH] [--capability ID] [--budget-seconds N]
```

Windows: `runtime/windows/provision.ps1` with the same verbs.

## Stages

`authorize` → `capture-baseline` → `apply` → `smoke` → `record` → `commit-tooling`

Any failure after `capture-baseline` must `rollback` recipe residue without touching unrelated owner work. Do not retry the same failure in one shift.

## Authorization

`apply` requires an effective tooling policy of `auto-add` from `shift-policy.sh --project DIR resolve --json` (native Windows: `shift-policy.ps1 … resolve -Json`) in repository mode. Artifact mode and other policies refuse with a `refusalReasons` code from `schemas/v1/capability-recipe.json`.

## State

Incomplete work is recorded only in `.nightshift/provision-transaction.json`. `recover` finishes or rolls back that file before product work. A verified setup commit (`chore(tooling):`) is recognized and not reinstalled.

## Smoke

A verified red baseline (tool runs, reports findings) is success. Install failure is not a red baseline.

## Permissions

If install or smoke would prompt, skip that capability and continue. Never freeze the night.
