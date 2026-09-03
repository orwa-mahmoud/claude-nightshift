# Maintainer verification matrix

Shipped architecture for the evidence-aware capability system on branch
`feat/evidence-aware-capability-system`. Run these checks after changes that touch the listed
surfaces. Full program verification is `tests/run-parallel.sh` or `bats -r tests/` (item 09A); CI
runs the same partition via six parallel `tests/run-shard.sh` jobs.

## Policy and shift lifecycle

| Surface | Schemas | Host paths | Authoritative tests |
| --- | --- | --- | --- |
| Three-layer policy (rules, shift-defaults, shift-policy) | `plugins/nightshift/skills/nightshift/references/schemas/v1/shift-defaults.json`, `plugins/nightshift/skills/nightshift/references/schemas/v1/shift-policy.json` | `plugins/nightshift/lib/policy.sh`, `plugins/nightshift/runtime/shift-policy.sh`, `plugins/nightshift/runtime/apply-profile.sh`; Windows: `plugins/nightshift/runtime/windows/apply-profile.ps1` | `tests/shift-policy.bats`, `tests/precedence.bats`, `tests/policy-matrix.bats`, `tests/rule-profiles.bats`, `tests/windows-shift-policy.bats` |
| Resolved policy view | — | `plugins/nightshift/runtime/doctor.sh`, `plugins/nightshift/runtime/status.sh`, `plugins/nightshift/runtime/export-support.sh` | `tests/doctor.bats`, `tests/status.bats`, `tests/support-bundle.bats` |
| Permission preflight | — | `plugins/nightshift/runtime/preflight-needs.sh` | `tests/preflight-needs.bats` |
| Provisioning transaction | — | `plugins/nightshift/runtime/provision.sh`, `plugins/nightshift/runtime/provision-preflight.sh`, `plugins/nightshift/runtime/provision-recover.sh` | `tests/provisioning.bats`, `tests/provision-recover.bats` |

## Evidence ledger and helpers

| Helper | Runtime | Tests |
| --- | --- | --- |
| Findings ledger | `plugins/nightshift/runtime/evidence.sh`, `plugins/nightshift/runtime/windows/evidence.ps1` | `tests/evidence.bats`, `tests/windows-evidence.bats` |
| Quality / coverage / defect | `plugins/nightshift/runtime/quality-workflow.sh`, `plugins/nightshift/runtime/coverage-risk.sh`, `plugins/nightshift/runtime/defect-cycle.sh` | `tests/quality-workflow.bats`, `tests/coverage-risk.bats`, `tests/defect-cycle.bats` |
| Engineering | `plugins/nightshift/runtime/engineering-evidence.sh` | `tests/engineering-confidence.bats` |
| Product truth | `plugins/nightshift/runtime/product-truth-evidence.sh` | `tests/product-truth-evidence.bats` |
| Source policy / research | `plugins/nightshift/runtime/source-policy-evidence.sh` | `tests/source-policy-evidence.bats`, `tests/redaction-malicious.bats` |
| SEO | `plugins/nightshift/runtime/seo-evidence.sh` | `tests/seo-evidence.bats`, `tests/seo-fixtures.bats` |
| Owner work | `plugins/nightshift/runtime/owner-work-evidence.sh` | `tests/owner-work-evidence.bats` |
| PR / release / onboarding | `plugins/nightshift/runtime/pr-readiness-evidence.sh`, `plugins/nightshift/runtime/release-readiness-evidence.sh`, `plugins/nightshift/runtime/build-onboarding-evidence.sh` | `tests/pr-readiness-evidence.bats`, `tests/release-readiness-evidence.bats`, `tests/build-onboarding-evidence.bats` |
| Migration / operational / specialist | `plugins/nightshift/runtime/migration-evidence.sh`, `plugins/nightshift/runtime/operational-evidence.sh`, `plugins/nightshift/runtime/specialist-evidence.sh` | `tests/migration-evidence.bats`, `tests/operational-evidence.bats`, `tests/specialist-evidence.bats` |
| History / continuity | `plugins/nightshift/runtime/history-context.sh`, `plugins/nightshift/runtime/continuity-handoff.sh` | `tests/history-context.bats`, `tests/continuity-handoff.bats` |

Schemas: `plugins/nightshift/skills/nightshift/references/schemas/v1/`. Fixtures: `tests/fixtures/`.

## Capabilities and catalog

| Surface | Tests |
| --- | --- |
| Applicability detection (bash + PowerShell) | `tests/capabilities.bats`, `tests/windows/detect-capabilities-logic.ps1` |
| Catalog contracts | `tests/catalog.bats`, `tests/shifts/` |
| Contract schema and size budgets | `evals/run.sh`, `evals/validate.sh`, `tests/evals.bats` |

## Host parity and recovery

| Host | Watchman | Hardhat / gate | E2E |
| --- | --- | --- | --- |
| Claude Code (POSIX) | `plugins/nightshift/runtime/claude/watchman.sh` | `plugins/nightshift/hooks/`, `tests/hardhat.bats`, `tests/clock-out-gate.bats` | `tests/e2e-lifecycle.bats` |
| Codex | `plugins/nightshift/runtime/codex/watchman.sh` | `tests/codex/` | `tests/e2e-lifecycle.bats` |
| Cursor | `plugins/nightshift/runtime/cursor/watchman.sh` | `tests/cursor/` | — |
| Native Windows | `plugins/nightshift/runtime/windows/watchman.ps1` | `plugins/nightshift/hooks/windows/`, `tests/windows-hardhat.bats` | `tests/windows/run.ps1` (Windows CI) |

## Work modes and safety boundaries

| Boundary | Enforced by | Tests |
| --- | --- | --- |
| Repository vs artifact mode | `plugins/nightshift/runtime/write-receipt.sh` | `tests/work-mode.bats`, `tests/artifact-receipts.bats` |
| Elevation categories (`sudo`, containers, …) | hardhat + policy resolver | `tests/hardhat.bats`, `tests/precedence.bats` |
| Owner-only actions | evidence helpers + contracts | `tests/shifts/`, fixture refusal paths |
| jq-or-python3 JSON prerequisite | hooks fail closed | `tests/hardhat.bats`, `tests/shift-policy.bats` |
| No Python on basic Windows paths | skill-paths guard | `tests/skill-paths.bats` |

## Evaluation commands (quick smoke)

```text
evals/run.sh
bats tests/evals.bats
claude plugin validate . --strict
git ls-files '*.sh' | xargs shellcheck -x   # full pass in 09A
```

## Non-goals (enforced, not shipped)

- Central telemetry or hosted accounts in the MIT core
- Mandatory npm/Homebrew/MCP for Setup → Start → tick
- Independent proof of self-reported ticks (by design)
- Competitor comparisons in public artifacts

Public documentation: [`docs/evidence-capabilities.md`](evidence-capabilities.md),
[`docs/how-it-works.md`](how-it-works.md#three-policy-layers-and-one-resolved-view).
