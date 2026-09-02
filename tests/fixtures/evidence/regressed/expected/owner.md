# Morning receipt — d4e6f8a0c2e4f6a8

## Shift

- Shift `d4e6f8a0c2e4f6a8` · host `claude` · work target `/repo`
- Started `2026-08-27T20:55:00Z` · Ended `2026-08-27T21:20:00Z` · Ending: **stop**
- Items: `0/1` ticked · Commits: `0`
- Policy: verification `final` · tooling `existing-tools` · mode `clear-all` · source `composition`
- Allowances: none
- Verified: none — stopped before the final gate ran
- Disabled by owner: none
- Unavailable: none

## Baseline

- `pytest` — environment `ec335e659d09443b6d2646ff80df40137eb54fc2a24cb363ddcd724c37ce9cfb` · raw `323a7e7eeb800f96f8e04b7ab57d4a8d97b9e9f24a18fb93e10a6b8cc3d34269`

## What changed

| id | sources | status | locator |
|---|---|---|---|
| `f-test-301` | pytest | regressed | `tests/test_totals.py::test_sum_totals` |

f-test-301 was fixed on 2026-08-20 (`verified-after-change`) and is open again tonight at the same
digest — a regression, never rendered as new or as an improvement.

## Parked

- **f-test-301 regressed after the 08-20 fix.** Default: stop before touching the rounding code a
  second time; hand the bisect to the owner. Rollback: nothing was changed tonight — the working
  tree matches checkpoint `chk-0002`, so there is nothing to undo.

## Next

- Investigate why the 2026-08-20 rounding fix (round each line before summing) no longer holds for
  f-test-301 (item 1, open) before writing another patch to `tests/test_totals.py::test_sum_totals`.
