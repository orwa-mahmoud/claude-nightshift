# Morning receipt — a7b9c1d3e5f7a9b1

## Shift

- Shift `a7b9c1d3e5f7a9b1` · host `codex` · work target `/workspace/blog-site`
- Started `2026-08-30T08:50:00Z` · Ended `2026-08-30T09:40:00Z` · Ending: **done**
- Items: `1/1` ticked · Receipts: `1`
- Policy: verification `final` · tooling `existing-tools` · mode `clear-all` · source `composition`
- Allowances: none
- Verified: `lychee content/` (final, before clock-out)
- Disabled by owner: per-item gate — verification level is `final`, so item 1 ticked without an intermediate check
- Unavailable: none

## Baseline

- `lychee` — environment `cf6880c941ed0ab96f768cff64ca92e1758cab0057b56fe005c95c1d1529e157` · raw `7bb436064b9ab7257ca53598d011eb4936425713a5e4312054f91173e3c50d80`

## What changed

| id | sources | status | locator |
|---|---|---|---|
| `f-lnk-701` | lychee | cleared | `content/posts/roadmap-2026.md:18` |

Fixes:

- **Fix the broken pricing link in `content/posts/roadmap-2026.md` (f-lnk-701).** — receipt
  `.nightshift/receipts/2026-08-30-0930-roadmap-fix.md` — verify: `lychee content/` — after:
  lychee reports 0 broken links

## Parked

- **Retire `/old-pricing` with or without a redirect?** Default: no redirect added tonight —
  rollback: add the redirect later; nothing here is destructive.

## Unsupported / unmeasured

- `f-ux-702` `content/posts/roadmap-2026.md:hero-image` — human-only: hero image text contrast
  against the photo background needs a human design call; no automated contrast tool covers
  art-directed overlays.
