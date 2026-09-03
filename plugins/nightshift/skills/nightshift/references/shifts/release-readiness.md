# Release readiness — finite — baseline vs candidate without publishing

Use when the owner names a release baseline (tag, branch, or supplied manifest) and a candidate
change set and wants a reviewable Ready / Not ready / Conditionally ready verdict — not a publish,
deploy, or marketplace submission. Compare tests, public APIs, package contents and digests,
install/upgrade smoke paths, version/changelog alignment, documentation claims, dependencies and
security advisories, and existing bundle or performance budgets where the repository already tracks
them.

Supported on any repository with a named baseline artifact and candidate tree. Never select this entry in artifact mode. Do not `git init` a notes folder to make release evidence commitable.

Schema: `references/schemas/v1/release-readiness-evidence.json`. Build comparison artifacts with
a receipt from `receipt-templates.md` from owner-supplied manifests, CI outputs, package
inventories, and audit results — then cite provenance on every dimension.

## Public-claims mode

When the primary risk is what the product *claims* publicly, run documentation-drift in
**public-claims mode** first: reconcile website copy, README, manifests, directory listings,
examples, install commands, version strings, privacy/security statements, released package
contents, and observed behavior. Use a receipt from `receipt-templates.md`
for cross-surface claims; use a receipt from `receipt-templates.md` for in-repo
docs only. Fix mechanical drift; park positioning and legal decisions in parking-lot.md.

```text
- [ ] **Release readiness — compare baseline and candidate; never publish.**
  - Never select this entry when work mode is artifact.
  - Discovery: record the named baseline ref and candidate ref. Collect or build manifests for
    tests, public API diff, package file list and digests (respecting declared exclusions),
    install/upgrade smoke results, version/changelog entries, documentation claim checks,
    security advisories, and budget measurements. Run
    a receipt from `receipt-templates.md` before drafting findings.
  - Run a receipt from `receipt-templates.md` when public surfaces are in
    scope; route pure in-tree doc repair to documentation-drift (public-claims mode or default).
  - Fix supported mechanical gaps (broken install commands, manifest/version drift, package
    exclusion mistakes, failing smoke paths, changelog omissions) within repository authority.
    Rerun focused gates after each fix. Never publish, tag, push, deploy, submit to a marketplace,
    or cut a GitHub release without explicit owner authority.
  - Produce a receipt from `receipt-templates.md` with status **Ready**, **Not ready**,
    or **Conditionally ready**, listing blockers, non-blockers, and
    a receipt from `receipt-templates.md` rows. Preserve metric and
    environment provenance on every row. Green CI alone is not complete release evidence; a
    Nightshift verdict is not human acceptance.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every scoped blocker is fixed or parked with reason, non-blockers are dispositioned,
    unmeasured surfaces are recorded, containing checks are green, and the verdict is written to
    the receipt — or the owner explicitly stops.
  - Verify: the item gate is green at every commit; baseline-compare and verdict helpers re-run
    clean on the final candidate; public-claims-matrix rows show no remaining mechanical drift.
```
