# Toil reduction — finite — automate repeated manual work with evidence

Use when the owner supplies evidence of repeated manual work — frequency, failure cost, or
time spent — and wants bounded repository automation for demonstrably recurring tasks, not
one-time annoyances or unmeasured heroics.

Supported when repetition evidence is named in scope (ticket history, runbooks, CI pain, or an
owner list). Requires repository mode. Never select this entry in artifact mode. Typical hours: 2–4.

```text
- [ ] **Toil reduction — automate repeated manual work with bounded evidence.**
  - Discovery: list manual tasks with supplied frequency, failure cost, and minutes per occurrence.
    Run `runtime/operational-evidence.sh toil-assess` before automating anything. Refuse one-time
    annoyances and tasks without repetition evidence.
  - Never select this entry when work mode is artifact.
  - Automate one bounded candidate per cycle when `action` is `automate-bounded`; keep rollback
    and docs explicit; run the item gate, commit.
  - Never automate a one-time annoyance, hide failure cost, or claim savings without measured
    before/after evidence when the repository can supply it.
  - Never broaden automation into production-only or destructive operations without explicit
    owner authority.
  - Finish with `runtime/operational-evidence.sh measured-summary` listing automated, parked, and
    refused tasks.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every in-scope task is automated with bounded evidence, parked with reason, or
    refused as insufficient repetition — and measured-summary is written.
  - Verify: the item gate is green at every commit; toil-assess refuses false repetition and
    one-time tasks; measured-summary distinguishes measured savings from unmeasured claims.
```
