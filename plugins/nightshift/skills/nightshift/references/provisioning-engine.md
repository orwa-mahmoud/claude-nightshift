# Provisioning engine contract (frozen)

Shared engine for Auto-add. Skills never embed install logic; they call the helpers.

## CLI

```text
provision.sh --project DIR plan|apply|recover|rollback [--recipe PATH] [--capability ID] [--budget-seconds N]
```

Windows: `runtime/windows/provision.ps1` with the same verbs.

Exit: `0` ok · `1` usage or a runtime failure · `2` refused · `3` a rollback whose restore could not be proven, leaving the transaction and the baseline store in place for repair.

## Stages

`authorize` → `capture-baseline` → `apply` → `smoke` → `record` → `commit-tooling`

Any failure after `capture-baseline` must `rollback` recipe residue without touching unrelated owner work. Do not retry the same failure in one shift.

## Authorization

`apply` requires an effective tooling policy of `auto-add` from `shift-policy.sh --project DIR resolve --json` (native Windows: `shift-policy.ps1 … resolve -Json`) in repository mode. Artifact mode and other policies refuse with a `refusalReasons` code from `schemas/v1/capability-recipe.json`.

Elevation comes from the same resolved view, never from the engine. A recipe declares what it needs in `elevationCategories`, and each declared category must resolve to `allow` or to an `exact-plan` allowance that binds every command needing it; every command the engine may run is also matched against every category pattern and cleared through `ns_policy_allowed`, so an undeclared category is caught by the command that needs it. A category tonight does not authorize refuses with `elevation-denied:<category>`. Each elevated command that runs leaves one ledger line in the `provisioning` domain carrying its category, the allowance's provenance, and the exact command, and reaches `verified-after-change` only once the smoke has passed.

## State

Incomplete work is recorded only in `.nightshift/provision-transaction.json`. `recover` finishes or rolls back that file before product work. A verified setup commit (`chore(tooling):`) is recognized and not reinstalled.

## Smoke

A verified red baseline (tool runs, reports findings) is success. Install failure is not a red baseline.

## Permissions

If install or smoke would prompt, skip that capability and continue. Never freeze the night. `provision-preflight.sh --project DIR [--recipe PATH] check` reports `permission-prompt-required` when the run is unattended without a grant, or when an allowed `sudo` category meets a recipe that may reach for it and `sudo -n true` does not succeed; under `auto-add` alone it also reports `provisioning-runtime-unavailable` when the provisioning runtime is missing.
