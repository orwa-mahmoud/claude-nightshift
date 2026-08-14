# Selection and launch modes

Hunt and Quality use two independent choices. Never infer one from the other.

## Selection

- **Guided** — the owner chooses one or more catalog entries, then may add scope or approach.
- **Automatic** — the owner supplies a time budget; inspect the repository and choose the
  applicable catalog entries that offer the strongest evidenced user value in that time.

Automatic selection is not a generic brainstorm. Read every entry in `shifts/`, then inspect the
project's tooling, tests, documentation, issue references available in the workspace, and recent
git history. For each applicable entry record one sentence of evidence. Rank by:

1. user or production impact;
2. strength of repository evidence;
3. ability to finish and verify inside the remaining time;
4. risk and reversibility.

Remove overlaps: one finding belongs to one entry. Run finite entries first. If useful time remains,
choose at most one open-ended entry — coverage, defect hunting, or product evolution — to use it.
One deadline governs the whole automatic shift, and automatic mode always requires hours.

## Launch

- **Review first** — discovery is read-only. Show the evidence, selected entries, order, scope,
  endings, and hours. Write and arm nothing until the owner approves. The clock starts only after
  that approval.
- **Run directly** — the owner's choice is explicit authority to discover, select, implement, and
  verify within the stated scope and time. Start the clock immediately, assemble and cut one work
  order, arm one shift, and continue selecting applicable work until quitting time.

Guided + run directly still performs the selected entry's discovery, but it does not pause after
showing the findings. Guided + review first does pause. Choosing a category is not by itself approval
to implement; the launch choice decides that.

## Direct-mode decisions

Run directly means make progress, not avoid judgment:

- choose the strongest production-quality default;
- make reasonable, reversible decisions on the isolated branch;
- preserve compatibility or include migration and rollback where a breaking change is justified;
- implement and verify the decision;
- record every significant choice, evidence, alternatives, shipped result, and rollback in
  `parking-lot.md`; then continue.

Stop for the owner only when the action is outside the granted coding-work boundary: publishing,
merging, deploying, deleting real data, exposing secrets, spending money, or changing legal or licensing policy.
A difficult or potentially breaking code change is not automatically outside the
boundary when it is isolated, tested, reviewable, and reversible.

## One shift contract

Any combination becomes one ordered work order, one punch list, one branch, one deadline where
required, and one set of receipts. Never arm a separate shift per entry. The catalog entry remains
the definition of done; selection and launch modes decide who chooses it and whether discovery
pauses for approval.

A GitHub issue hunt cannot grow past the imported `Status: proposed` set the owner already
staged. Direct mode may rank inside that set; it must not search GitHub or add issues that were
not imported.
