---
name: quality
description: Find and work the project's applicable quality debt across tests, code, accessibility, contracts, documentation, dependencies, and security. Supports guided or automatic selection and review-first or run-direct execution.
---

Quality is the broad entry point for this project's quality work. It uses the same selection and
launch modes as Hunt. Work in `$CLAUDE_PROJECT_DIR`.

Resolve `${CLAUDE_PROJECT_DIR:-$PWD}` through its explicit `.nightshift-link` when present; use the
validated absolute target for every `.nightshift/` path, otherwise the task root. Never search or
guess. The shell's working directory persists between Bash calls, so never use a bare path.

Read these before scanning:

- `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/execution-modes.md`
- every applicable entry under `${CLAUDE_PLUGIN_ROOT}/skills/nightshift/references/shifts/`

Quality includes: lint, types, tests, flaky tests, coverage, dead code, TODO/FIXME debt,
accessibility, localization, API contract drift, documentation drift, CI warnings, direct
dependencies, and vulnerability advisories. `clear-quality-debt.md` remains the generic finite
core-tooling entry; specialized entries retain their own safety rules and definitions of done.
GitHub issue hunts are catalogued under Hunt and start from imported drafts. Quality does not import, search, or work GitHub issues.

## 1. Choose selection and launch

Ask two independent choices:

1. **Guided** (the owner chooses quality areas) or **Automatic** (Nightshift selects every
   applicable high-value area that fits the hours).
2. **Review first** or **Run directly**.

Automatic mode requires hours. Guided mode asks for scope and requires hours only when an
open-ended entry is selected. In review-first mode scanning is read-only and the clock starts only
after approval. In run-direct mode the clock begins immediately and findings are implemented
without another pause under the decision policy in `execution-modes.md`.

## 2. Detect and scan

Detect the stack from the gates catalog (monorepo-aware), inspect repository-owned tooling and
evidence, then apply the discovery rules from every relevant quality entry. Never install a tool
merely to manufacture findings. In review-first mode use report-only commands: no fix flags and no
writes. If `.nightshift/` does not exist, review-first may report, but any run-direct request must
stop and point to `/nightshift:setup` before work can be armed.

## 3. Rank and deduplicate

Map each finding to one catalog entry so work is never duplicated. In Automatic mode rank using
the shared mode contract, run finite entries first, and use at most one open-ended entry for useful
remaining time. In Guided mode keep only the areas and scope the owner selected.

## 4. Review first

When review first was chosen, summarize evidence per catalog entry and top-level directory in plain
numbers, then show the exact ordered work order. Offer three answers:

- **fix now** — compose one work order from the selected catalog entries and start it here through
  the Hunt cut and `/nightshift:start` lifecycle. Preserve every entry's contract. Apply the one
  deadline chosen for the combined shift.
- **draft for later** — append them to `.nightshift/drafting-table.md` and arm nothing. The
  drafting table is staging: it is never read by the gate, which is exactly why proposals can wait
  there safely. Tell the owner they can promote what they want into the punch list and run
  `/nightshift:start` after promotion, or compose it later through Hunt.
- **ignore** — write nothing at all; fully respected. A finding the owner does not care about is
  not a defect.

Never write to the punch list on anything but an explicit **fix now** in review-first mode. Items there are the shift
the next start will work, so writing them on a survey puts work in front of the owner that nobody
agreed to — the box and the start belong together, or neither happens.

## 5. Run directly

When run directly was chosen, do not present the three-answer review menu. Compose one ordered work
order, cut it immediately, and arm one shift with
`touch "$NIGHTSHIFT_WORKSPACE/.nightshift/.shift-armed"`; log the start and arm the watchman exactly
as `/nightshift:start` requires. Implement and verify the selected entry contracts, and continue
until the finite work is clear or the shared deadline ends. Record significant decisions and
rollback instructions in `parking-lot.md`; never create a second shift per quality area.

If the stack no longer matches the current `## Gates` block, say so in one line and point to
`/nightshift:setup` — gates belong to setup, not to this command.
