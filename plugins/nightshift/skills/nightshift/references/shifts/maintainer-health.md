# Maintainer health — finite — preset review across onboarding, docs, CI, and release claims

Use when the owner wants a bounded maintainer-facing health pass on an open-source or internal
repository without adding a tool marketplace entry. This preset composes existing catalog contracts
— it does not duplicate their depth.

Supported on repositories with in-tree docs, scripts, and at least one verification surface.
Never select this entry in artifact mode. Do not `git init` a notes folder to make receipts
commitable.

Schema: `references/schemas/v1/specialist-evidence.json`. Resolve the preset with
a receipt from `receipt-templates.md` before running the composed helpers.

```text
- [ ] **Maintainer health — run the onboarding, docs, CI, and public-claims preset.**
  - Never select this entry when work mode is artifact.
  - Discovery: run a receipt from `receipt-templates.md` against available
    contracts. For each available row, run the named helper only — developer onboarding via
    a receipt from `receipt-templates.md`, documentation drift via
    a receipt from `receipt-templates.md`, CI warnings via
    a receipt from `receipt-templates.md`, and public claims via
    a receipt from `receipt-templates.md`. Skip unavailable contracts
    honestly; never invent tooling.
  - Work one preset segment per cycle in the order the preset lists. Fix only mechanical,
    reversible issues within each parent contract's authority. Park positioning, legal, and release
    authority decisions in parking-lot.md.
  - Review first writes the combined report only. Direct mode may apply fixes allowed by each parent
    contract; it never publishes, merges, or claims human release acceptance.
  - Never add new catalog entries for individual tools discovered during the preset.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every available preset segment is `ok` or parked with evidence, or the preset helper
    reports insufficient contracts to continue.
  - Verify: the item gate is green at every commit; `maintainer-health-preset` reports at least
    two available segments completed or explicitly unavailable.
```
