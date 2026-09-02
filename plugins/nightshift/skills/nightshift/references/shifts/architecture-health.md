# Architecture health — finite — concrete dependency and boundary cost from repository evidence

Use when the owner wants a reviewable picture of dependency, boundary, ownership, and cycle cost
in the repository — not architectural taste. Review-first is the default; direct edits are small
and reversible only.

Supported on repositories with inspectable structure (packages, modules, manifests, CI). Never
select this entry in artifact mode. Do not `git init` a notes folder to make findings commitable.

Schema: `references/schemas/v1/specialist-evidence.json`. Gate selection with
`runtime/specialist-evidence.sh specialist-gate` when composing automatic shifts. Build findings
with `runtime/specialist-evidence.sh architecture-findings`.

```text
- [ ] **Architecture health — report concrete dependency and boundary cost.**
  - Never select this entry when work mode is artifact.
  - Discovery: inspect repository-owned structure only — manifests, package boundaries, import
    graphs the project already generates, CI topology, and ownership files. Run
    `runtime/specialist-evidence.sh architecture-findings` and accept only findings with concrete
    dependency, boundary, ownership, or measured cycle cost. Reject taste-only observations.
  - Review first writes the findings report only. Direct mode may apply one small, reversible edit
    per cycle when the helper marks `directEditAllowed`; never perform broad refactors unattended.
  - Park ownership disputes, platform choices, and product tradeoffs in parking-lot.md with evidence.
  - Never present architectural preference as proof or claim whole-system health from one pass.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every accepted finding is dispositioned (fixed, rejected, or parked) and no open
    taste-only rows remain.
  - Verify: the item gate is green at every commit; a second `architecture-findings` pass reports
    no new accepted findings for the scoped area.
```
