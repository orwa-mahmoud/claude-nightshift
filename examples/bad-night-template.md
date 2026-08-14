# Bad-night receipt template

Use this when a shift was interrupted, stalled, owner-stopped, revived incorrectly, or ended with
work that did not match the punch list. Successful nights belong in a filled example (see
[`adapttable-overnight.md`](adapttable-overnight.md) and
[`codex-hardening-shift.md`](codex-hardening-shift.md)).

A ticked box is the agent's own claim that the item is done. It is not independent proof. Link
public commits, pull requests, or logs when they exist; do not paste private repository content
to make a tick look verified.

Contribute filled receipts against
[#22](https://github.com/orwa-mahmoud/nightshift/issues/22). Gate-bypass reports go to a
[private advisory](https://github.com/orwa-mahmoud/nightshift/security/advisories/new), not here.

Copy from **Host** downward. Delete unused bullets. Keep **Facts** and **Interpretation** in
separate sections.

## Redaction checklist

Before anything leaves your machine:

- [ ] No prompts, system instructions, or tool-call payloads
- [ ] No credentials, tokens, `.env` values, or notification-command output
- [ ] No private source, customer data, or unpublished product plans
- [ ] No full session transcript or rollout file
- [ ] Paths trimmed to `.nightshift/` marker names unless the path is already public
- [ ] Punch-list titles rewritten if they name private work; keep the open/ticked counts

## Host

- Date (timezone):
- Nightshift version:
- Host and host version (Claude Code / Codex):
- OS:

## What was contracted

- Shift kind (your list / hunt entry name):
- Open items at start / ticked at end (counts only):
- Deadline, if any:
- Public punch-list or PR link (only if the run is public):

## Facts (observed)

What you can point at. Timestamps, marker names, watchman log *lines* after redaction, commit SHAs
that already exist on a public remote. No guesses.

- How the shift started (interactive / scheduled / revived):
- Markers present when you looked (`.shift-armed`, `STOP`, `.ended`, `.stall`, `.shift-session`, …):
- Watchman or gate lines (redacted; see [troubleshooting](../docs/troubleshooting.md)):
- Public commits or PR, if any:
- Whether you issued `touch .nightshift/STOP`:

## Interpretation (yours, not the agent's)

What you think it means. Keep this separate so a reader can disagree without discarding the facts.

- Interrupted / stalled / incorrectly completed / owner-stopped / failed revival / other:
- What you expected:
- What you changed in the morning (rewrote an item, restored a file, ignored a tick):

## Outcome

- Open boxes left open: yes / no / n/a
- Same conversation resumed: yes / no / n/a / unknown
- Would you run this list again? What would you word differently?

---

This file is a template, not a recorded night. Do not fill it with invented timestamps or commits.
