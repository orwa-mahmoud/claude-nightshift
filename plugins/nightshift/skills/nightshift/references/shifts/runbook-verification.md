# Runbook verification — finite — safe procedure replay with existing observability

Use when the owner names a runbook or operational procedure and supplies logs, metrics, traces,
or failure-surface evidence to verify it in a declared safe environment — not vendor shopping,
not assumed production telemetry, and not destructive emergency steps.

Supported when a named procedure and safe/disposable environment are declared. Observability and
diagnostics work as modes below before separate catalog entries. Requires repository mode. Never
select this entry in artifact mode. Typical hours: 1–3.

## Observability/diagnostics mode

When the primary gap is missing logs, metrics, traces, or failure-surface visibility, run
a receipt from `receipt-templates.md` first. Record absent signals honestly;
never assume emitted telemetry reached production.

```text
- [ ] **Runbook verification — replay a named safe procedure with supplied evidence.**
  - Discovery: record the procedure name, declared safe/disposable environment, and supplied
    logs/metrics/traces or failure-surface samples. For observability gaps, run
    a receipt from `receipt-templates.md` before proposing instrumentation.
    Run a receipt from `receipt-templates.md` on each step cluster.
  - Never select this entry when work mode is artifact.
  - Verify one step cluster per cycle in the named safe environment; fix repository automation or
    docs when a declared step fails; park production-only steps. Run the item gate, commit.
  - Never impose a vendor, assume telemetry reached production, execute destructive emergency
    steps, or run production-only steps without explicit owner authority.
  - Never certify full operational readiness from one script — record verified, refused, and
    production-only steps separately.
  - Finish with a receipt from `receipt-templates.md` for every signal and step.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every in-scope step is verified, refused with reason, or parked as production-only,
    and observability gaps are recorded absent — not inferred.
  - Verify: the item gate is green at every commit; runbook-verify and observability-surface
    helpers re-run clean; measured-summary states measured versus unmeasured for each surface.
```
