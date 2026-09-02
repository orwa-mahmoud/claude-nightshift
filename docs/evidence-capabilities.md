# Evidence-aware capabilities

Nightshift ships a catalog of shift contracts — each with discovery rules, a definition of done,
verification, and supported stacks. Phase 04–07 added **evidence helpers**: small Python runtimes
with POSIX shell wrappers that normalize findings, refuse owner-only actions, and record what was
measured versus unavailable.

## Runtime helpers

| Helper | Purpose |
| --- | --- |
| `quality-workflow.sh` | Normalize, dedupe, and rank quality findings |
| `coverage-risk.sh` / `defect-cycle.sh` | Risk-ordered coverage and defect lens rotation |
| `engineering-evidence.sh` | Flaky tests, CI warnings, dead code, dependencies, vulnerabilities |
| `product-truth-evidence.sh` | API drift, accessibility, localization, documentation claims |
| `source-policy-evidence.sh` | Closed/bounded/connected source policies and untrusted redaction |
| `seo-evidence.sh` | Local, Live, and Connected SEO evidence modes |
| `owner-work-evidence.sh` | Issue graphs, walkthrough plans, product-evolution hypotheses |
| `pr-readiness-evidence.sh` | Branch-scoped acceptance maps and review maps |
| `release-readiness-evidence.sh` | Baseline comparison and public-claims matrices |
| `build-onboarding-evidence.sh` | Reproducibility and onboarding journeys |
| `migration-evidence.sh` | Migration plans, config parity, data safety |
| `operational-evidence.sh` | Performance, incident, runbook, observability, toil |
| `specialist-evidence.sh` | Product journeys and evidence-gated specialist modes |
| `history-context.sh` | Receipt index, presets, audience handoffs, source adapters |
| `continuity-handoff.sh` | Cross-host handoff packages and campaign sequencing |

Schemas live under `plugins/nightshift/skills/nightshift/references/schemas/v1/`. Fixtures and
`tests/*.bats` cover each helper; shift contracts under `references/shifts/` reference the helpers
in their Discovery and Verify lines.

## Shift policy and profiles

Three layers resolve before arming:

1. **`rules.json`** — owner gates, retention, branch mode, tool denies (including default `sudo`
   and Docker socket denies unless explicitly allowed).
2. **`shift-defaults.json`** — verification profile (`fast`, `balanced`, `strict`, `custom`),
   tooling policy (`existing-tools`, `auto-add`, `repository-tooling`), execution mode.
3. **One-shift allowances** — optional temporary elevation recorded with provenance on the receipt.

Shipped profiles (`fast`, `balanced`, `strict`) in `references/profiles/` propose defaults and
Gates text during Setup; owner rules remain authoritative.

A **zero-gate `fast` shift** is first-class: items and receipts land without automated checks;
verification level on the receipt states what ran.

## Artifact and non-developer shifts

Repository mode commits to the work target; **artifact mode** completes with
`write-receipt.sh` into `$NS/receipts/`. Research synthesis, documentation writing, and cited
reports inherit `cited-research.md`. Source policies (`closed-list`, `bounded-discovery`,
`connected-corpus`) gate what may be fetched; untrusted content passes through `redact-untrusted`.

## Cross-host continuity

The punch list, parking lot, snag log, and receipts — not either conversation — hold authority.
`continuity-handoff.sh` builds versioned handoff packages and rejects duplicate workers.
Multi-night **campaigns** are independent bounded shifts; the next night begins only after the prior
archives or the owner accepts its handoff.

## Contract evaluation toolkit

The repository root `evals/` directory hosts the **contract schema and evaluation toolkit**
(priority cases, frozen identifiers, instruction-size budgets). Run `tests/evals.bats` locally;
human review remains required for catalog contributions.

## Limits

- Ticks are self-reported; helpers record evidence honestly but do not certify independent proof.
- Connectors beyond local files and owner-supplied exports remain optional until explicitly shipped.
- No central telemetry in the MIT core; product measures belong in local receipts only.
- Optional **SonarQube Community Edition** can back site inspections when `sonar-project.properties`
  exists and a local instance answers; Sonar is never a per-item gate. See
  [`gates-catalog.md`](../plugins/nightshift/skills/nightshift/references/gates-catalog.md).

## Example receipt shapes

**Repository mode** — each work package ends in one conventional commit; the morning handoff is the
punch list, parking lot, snag log, and `git log` on the work target.

**Artifact mode** — `runtime/write-receipt.sh` records item text, verification commands, optional
decisions, and hashed outputs under `.nightshift/receipts/`. Status and Doctor surface receipt
counts; Archive files them with the shift.

A bounded unattended receipt names actual commands run, tools that were missing, surfaces that
could not be measured, and what the owner should review — never invented external acceptance.
