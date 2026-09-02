# Parking Lot

- **f-test-301 regressed after the 08-20 fix.** The three-line rounding fix from 2026-08-20 no
  longer holds against tonight's order fixture. Default: stop before touching the rounding code a
  second time and hand the bisect to the owner rather than layering another patch on a fix that
  already failed once. Chosen because a second unreviewed rounding change on money-affecting code
  is exactly the kind of repeat fix that hides the real bug.
