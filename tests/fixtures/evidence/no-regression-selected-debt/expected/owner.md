# Morning receipt — b2c4e6f8a0d2e4f6

## Shift

- Shift `b2c4e6f8a0d2e4f6` · host `claude` · work target `/repo`
- Started `2026-08-26T21:50:00Z` · Ended `2026-08-26T23:10:00Z` · Ending: **done**
- Items: `1/1` ticked · Commits: `1`
- Policy: verification `per-item` · tooling `existing-tools` · mode `no-regression-plus-selected-debt` (selected: f-typ-101) · source `composition`
- Allowances: none
- Verified: `mypy src/billing/` (per item, before each commit)
- Disabled by owner: none — per-item gate ran for the one item
- Unavailable: none

## Baseline

- `mypy` — environment `144eb9f3150e3c09d2910ede191b66404fc933ce16635a681bb281b525bfb61b` · raw `b575925b2fef97d9a2a8b468a5d2ae7827f3cc781edde02154bb1ec32f6623ee`

## What changed

| id | sources | status | locator |
|---|---|---|---|
| `f-typ-101` | mypy | cleared | `src/billing/totals.py:41` |
| `f-typ-102` | mypy | unchanged (accepted debt, not selected) | `src/billing/totals.py:88` |
| `f-typ-103` | mypy | unchanged (accepted debt, not selected) | `src/billing/refunds.py:15` |

Fixes:

- **Fix f-typ-101: apply_discount receives a raw str instead of Decimal.** — commit "fix: convert amount to Decimal before apply_discount" — verify: `mypy src/billing/` — after: 2 errors remain (f-typ-102, f-typ-103 — both accepted debt, not required this shift)
