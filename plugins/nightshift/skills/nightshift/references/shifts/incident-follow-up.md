# Incident follow-up — finite — repository actions from supplied incident evidence

Use when the owner supplies a postmortem, timeline, logs, linked issues, or narrative about a
real incident and wants verified repository follow-ups — not a invented story, not production
changes outside repository authority, and not closure of owner or system actions.

Supported when explicit incident evidence is attached or referenced in the punch-list scope.
Requires repository mode. Never select this entry in artifact mode. Typical hours: 2–6.

```text
- [ ] **Incident follow-up — implement verified repository actions from supplied evidence.**
  - Discovery: inventory supplied evidence (postmortem, timeline, logs, issues, owner narrative).
    Run `runtime/operational-evidence.sh incident-actions` before editing. Preserve impact and timeline
    verbatim; separate root, contributing, detection, and recovery factors. Never invent an incident,
    symptom, or owner decision.
  - Never select this entry when work mode is artifact.
  - Implement only verified repository actions one cluster at a time; leave owner and system
    actions open with explicit status. Run focused gates after each fix, commit, refresh the
    action map.
  - Never rewrite impact or timeline, claim detection/recovery fixes without evidence, or close
    owner/system tickets.
  - Never run destructive emergency steps or production-only remediation without explicit owner
    authority in scope.
  - Finish with `runtime/operational-evidence.sh measured-summary` for every follow-up surface.
  - Dedupe against snag-log.md (ALL seen — fixed and rejected).
  - Ends when every verified repository action is implemented or parked, owner/system actions
    remain explicitly open, and incomplete evidence is refused — not guessed.
  - Verify: the item gate is green at every commit; incident-actions reports
    `inventedIncidentRefused` false only when evidence is complete; measured-summary lists
    repository versus unmeasured actions honestly.
```
