# Product journey — finite — reproducible user-route gaps from explicit journey evidence

Use when the owner names a persona, goal, starting state, and route to exercise. Fix reproducible
gaps the journey surfaces and retest. Error experience, responsive/cross-browser behavior, and
accessibility observations are modes on this entry — not separate catalog items.

Supported on projects with a local app, static preview, or browser evidence the owner supplies.
Never select this entry in artifact mode. Do not `git init` a notes folder to make journey evidence
commitable. Never claim whole-product usability or accessibility certification from one script.

Schema: `references/schemas/v1/specialist-evidence.json`. Build journey artifacts with
`runtime/specialist-evidence.sh` from owner-supplied persona, steps, and browser observations.

## Evidence modes

Product journey runs in exactly one evidence mode per shift (or a declared combination when the
owner supplies multiple observation surfaces). Discovery records the mode before findings are drafted.

### Journey (default)

Exercise the named route from starting state through each step's expected state. Run
`runtime/specialist-evidence.sh journey-map` with persona, goal, starting state, steps, and
available browser evidence. Record unavailable surfaces explicitly; never claim a platform or
browser behavior that was not observed.

### Error experience

Requires expected error and recovery states on affected steps. Run `journey-map` in
`error-experience` mode. Fix reproducible error-handling gaps; park copy, legal, or product-policy
tradeoffs.

### Responsive / cross-browser

Requires browser evidence and responsive targets. Run `journey-map` in
`responsive-cross-browser` mode. Record layout or behavior differences per target; never claim
cross-browser parity when browser evidence is unavailable.

### Accessibility journey

Keyboard, focus, and journey observations supplement — never replace — automated checks. Run
`journey-map` in `accessibility-journey` mode. Route objective scanner violations to
accessibility-repair; keep judgment-dependent surfaces in the gap report for human review. Never
certify WCAG compliance from automation or one journey alone.

```text
- [ ] **Product journey — exercise a named route and fix reproducible gaps.**
  - Never select this entry when work mode is artifact.
  - Discovery: record persona, goal, starting state, steps, expected/error/recovery states,
    responsive targets, keyboard/accessibility observations, and available browser evidence.
    Run `runtime/specialist-evidence.sh journey-map` in the chosen mode before drafting fixes.
    Write unavailable browser/platform surfaces as explicit rows — never estimate them.
  - Work one reproducible gap cluster per cycle with `runtime/specialist-evidence.sh journey-gap`.
    Fix only gaps the helper marks actionable and fixable in the repository; park product, legal,
    or assistive-technology judgments with evidence.
  - After each cluster, retest with `runtime/specialist-evidence.sh journey-retest` on the same
    route. Rerun the project's configured checks when a fix touches UI code.
  - Review first writes the journey map and gap report only. Direct mode may apply small,
    reversible fixes after the map names them; it never deploys, publishes, or claims certification.
  - Never claim whole-product usability, WCAG, or cross-browser certification from one script or
    unavailable browser evidence.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every reproducible gap is fixed and retested, or every remaining gap is parked with
    evidence and required human review.
  - Verify: the item gate is green at every commit; `journey-retest` reports a finite ending for
    the scoped route and mode.
```
