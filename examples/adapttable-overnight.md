# Example — an overnight run on a production library

On 2026-07-19 a single nightshift punch list drove one overnight shift on
[AdaptTable](https://github.com/orwa-mahmoud/adapttable), a published React data-table library:
**9 items, 4 issues closed on merge, v1.2.0 on npm the same day.** Every external claim below is
checkable in the public pull request, its commits, and the npm registry.

## The punch list, as the shift left it

Nine top-level boxes (sub-bullets, Verify and Commit lines omitted here):

```markdown
- [x] **1. CSV export button on the toolbar (issue #61).**
- [x] **2. Seven new locales incl. Traditional Chinese (issue #24 — stays open by design).**
- [x] **3. Runnable Tailwind starter for the unstyled adapter (issue #25).**
- [x] **4. Inline editing — core engine (issue #60, part 1 of 3).**
- [x] **5. Inline editing — all seven adapters (issue #60, part 2 of 3).**
- [x] **6. Inline editing — docs, e2e, showcase, changesets (issue #60, part 3 of 3).**
- [x] **7. Row grouping + aggregation — core engine (issue #62, part 1 of 3).**
- [x] **8. Row grouping — all seven adapters (issue #62, part 2 of 3).**
- [x] **9. Row grouping — docs, e2e, showcase, changesets (issue #62, part 3 of 3).**
```

## The night, from the commit log

One branch, one conventional commit per item (plus one lockfile chore), timestamps local:

```
01:50  feat(export): CSV export toolbar button across all adapters (closes #61)
01:54  feat(i18n): add zh-TW, ko, ru, tr, hi, fa, ur locales (refs #24 — never closes)
01:57  feat(starters): runnable Tailwind starter for the unstyled adapter (closes #25)
01:58  chore(starters): add lockfile entry for unstyled-tailwind starter
02:11  feat(core): inline cell editing state machine
02:53  feat(adapters): kit-native inline cell editing across all seven adapters
02:58  feat(editing): docs, e2e smoke, showcase demo + changesets (closes #60)
03:14  feat(core): single-level row grouping with per-group aggregates
04:15  feat(adapters): kit-native group header rows across all seven adapters
04:18  feat(grouping): docs, e2e smoke, showcase demo + changesets (closes #62)
```

## What the contract enforced

- **One gate-green commit per item** — the repo's own `pnpm check` (format, lint, typecheck, 95%+
  coverage thresholds, build, publint) ran before every tick, with zero suppressions; the site
  inspection added a Playwright e2e suite (61/61) and a local Sonar scan at 0 issues.
- **Park, don't ask** — five decisions that belonged to the owner (export scope on server data,
  eight adapters vs the issue's "seven", the editing change-channel, grouping's data tier, an antd
  typing boundary) were logged to `parking-lot.md` with a chosen default, and work continued. All
  five were reviewed and approved over coffee.
- **Pushing stayed the owner's** — the branch sat local until the morning review, then was pushed,
  PR'd, and merged by a human.

## Proof (public links)

- The merged PR — 12 commits, unsquashed, overnight timestamps intact:
  <https://github.com/orwa-mahmoud/adapttable/pull/75>
- First overnight commit (01:50):
  <https://github.com/orwa-mahmoud/adapttable/commit/e36b3eec5adae638cc528bf141a1d27f97455cfd>
- Last overnight commit (04:18, closes the grouping RFC):
  <https://github.com/orwa-mahmoud/adapttable/commit/4546dcdde4654c45e940bff0bebbb650dd3228ba>
- Outcome: issues #61, #25, #60, #62 closed by the merge; the standing locale issue #24 got a
  progress comment and stays open; v1.2.0 published to npm the same day.
