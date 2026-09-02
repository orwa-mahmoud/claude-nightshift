# Maintainer verification matrix

Shipped architecture for the evidence-aware capability system on branch
`feat/evidence-aware-capability-system`. Run these checks after changes that touch the listed
surfaces. Full program verification is `bats -r tests/` (item 09A).

## Policy and shift lifecycle

| Surface | Schemas | Host paths | Authoritative tests |
| --- | --- | --- | --- |
| Three-layer policy (`rules.json`, `shift-defaults.json`, `shift-policy.json`) | `references/schemas/v1/shift-*.json` | `runtime/policy.sh`, `runtime/shift-policy.sh`, `runtime/apply-profile.sh`; Windows: `runtime/windows/*.ps1` | `tests/shift-policy.bats`, `tests/precedence.bats`, `tests/policy-matrix.bats`, `tests/rule-profiles.bats`, `tests/windows-shift-policy.bats` |
| Resolved policy view | — | `runtime/doctor.sh`, `runtime/status.sh`, `runtime/export-support.sh` | `tests/doctor.bats`, `tests/status.bats`, `tests/support-bundle.bats` |
| Permission preflight | — | `runtime/preflight-needs.sh` | `tests/preflight-needs.bats` |
| Provisioning transaction | — | `runtime/provision*.sh`, `runtime/provision-recover.sh` | `tests/provision.bats`, `tests/provisioning-recover.bats` |

## Evidence ledger and helpers

| Helper | Runtime | Tests |
| --- | --- | --- |
| Findings ledger | `runtime/evidence.sh`, `runtime/windows/evidence.ps1` | `tests/evidence.bats`, `tests/windows-evidence.bats` |
| Quality / coverage / defect | `quality-workflow.sh`, `coverage-risk.sh`, `defect-cycle.sh` | `tests/quality-workflow.bats`, `tests/coverage-risk.bats`, `tests/defect-cycle.bats` |
| Engineering | `engineering-evidence.sh` | `tests/engineering-evidence.bats` |
| Product truth | `product-truth-evidence.sh` | `tests/product-truth-evidence.bats` |
| Source policy / research | `source-policy-evidence.sh` | `tests/source-policy-evidence.bats`, `tests/redaction-malicious.bats` |
| SEO | `seo-evidence.sh` | `tests/seo-evidence.bats`, `tests/seo-fixtures.bats` |
| Owner work | `owner-work-evidence.sh` | `tests/owner-work-evidence.bats` |
| PR / release / onboarding | `pr-readiness-evidence.sh`, `release-readiness-evidence.sh`, `build-onboarding-evidence.sh` | matching `tests/*-evidence.bats` |
| Migration / operational / specialist | `migration-evidence.sh`, `operational-evidence.sh`, `specialist-evidence.sh` | matching `tests/*-evidence.bats` |
| History / continuity | `history-context.sh`, `continuity-handoff.sh` | `tests/history-context.bats`, `tests/continuity-handoff.bats` |

Schemas: `plugins/nightshift/skills/nightshift/references/schemas/v1/`. Fixtures: `tests/fixtures/<area>/`.

## Capabilities and catalog

| Surface | Tests |
| --- | --- |
| Applicability detection (bash + PowerShell, no Python on basic path) | `tests/capabilities.bats`, `tests/windows/capability-detector-logic.ps1` |
| Catalog contracts | `tests/catalog.bats`, `tests/shifts/*.bats` |
| Contract eval toolkit | `evals/run.sh`, `evals/validate.sh`, `tests/evals.bats` |

## Host parity and recovery

| Host | Watchman | Hardhat / gate | E2E |
| --- | --- | --- | --- |
| Claude Code (POSIX) | `runtime/claude/watchman.sh` | `hooks/`, `tests/hardhat.bats`, `tests/clock-out-gate.bats` | `tests/e2e-lifecycle.bats` |
| Codex | `runtime/codex/watchman.sh` | `tests/codex/` | `tests/codex/e2e-lifecycle.bats` |
| Cursor | `runtime/cursor/watchman.sh` | `tests/cursor/` | — |
| Native Windows | `runtime/windows/watchman.ps1` | `hooks/windows/`, `tests/windows-hardhat.bats` | `tests/windows/run.ps1` (Windows CI) |

## Work modes and safety boundaries

| Boundary | Enforced by | Tests |
| --- | --- | --- |
| Repository vs artifact mode | `write-receipt.sh`, skills | `tests/work-mode.bats`, `tests/write-receipt.bats` |
| Elevation categories (`sudo`, containers, …) | hardhat + policy resolver | `tests/hardhat.bats`, `tests/precedence.bats` |
| Owner-only actions | evidence helpers + contracts | per-shift bats + fixture refusal paths |
| jq-or-python3 JSON prerequisite | hooks fail closed | `tests/json-parser.bats` |
| No Python on basic Windows paths | skill-paths guard | `tests/skill-paths.bats` |

## Evaluation commands (quick smoke)

```bash
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
