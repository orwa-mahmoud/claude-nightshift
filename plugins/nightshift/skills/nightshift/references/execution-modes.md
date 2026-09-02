# Selection and launch modes

Hunt and Quality use two independent choices. Never infer one from the other.

## Selection

- **Guided** — the owner chooses one or more catalog entries, then may add scope or approach.
- **Automatic** — the owner supplies a time budget; inspect the work target and choose the
  applicable catalog entries that offer the strongest evidenced user value in that time.

Automatic selection is not a generic brainstorm. Read every entry in `shifts/`, then inspect the
work target. In repository mode that is tooling, tests, documentation, issue references available
in the workspace, and recent git history. In artifact mode that is the persistent folder's files
and any existing source manifests or reports; do not require a git history that cannot exist.
Refuse to compose, cut, or arm when `$NS/receipts` exists but is not a usable directory.
If `$NS/work-mode` is missing and Setup would propose artifact, refuse to compose, cut, or arm and send the owner to Setup; do not `git init` a notes folder.
Refuse to compose, cut, or arm when work-mode is malformed.
Refuse to compose, cut, or arm when the work target cannot be resolved.
An entry is applicable only when the work target can supply its discovery surface. Skip coverage,
CI, dependency, and similar quality-debt entries when the folder has no tests, tooling, or
manifests to inspect. Skip the GitHub issue hunt when work mode is artifact or no proposed
imports exist. Skip the defect hunt when work mode is artifact.
Skip documentation drift when work mode is artifact.
Skip TODO and FIXME debt when work mode is artifact.
Skip coverage hunt when work mode is artifact.
Skip tooling quality-debt entries when work mode is artifact.
Do not `git init` a notes folder to make them applicable.
For each applicable entry record one sentence of evidence. Rank by:

1. user or production impact;
2. strength of work-target evidence;
3. ability to finish and verify inside the remaining time;
4. risk and reversibility.

Remove overlaps: one finding belongs to one entry. Run finite entries first. If useful time remains,
choose at most one open-ended entry to use it.
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

## Tooling policy

A third independent choice, folded into composition's one prefilled question (see "One question,
three files" below) so a direct unattended run never discovers a mid-shift owner decision:

- **Existing tools only** — skip contracts whose required capabilities are unavailable and spend
  the time elsewhere. This is the default, including when `$NS/shift-defaults.json` is missing.
- **Review missing tools first** — run a read-only capability scan and show one consolidated plan
  (capability, selected tool, exact writes, commands, enabled shifts, risks, permissions, rollback).
  Wait for approval before arming. The work clock has not begun. Review-first must write nothing.
- **Automatically add standard development tools** — explicit authorization for eligible local
  development tooling. Do not pause again to re-ask the policy. After authorization, call
  `runtime/provision-preflight.sh` then `runtime/provision.sh` (native Windows:
  `provision-preflight.ps1` then `provision.ps1`). Skills never embed install steps. Artifact
  mode is never offered a repository-tool install. Auto-add work runs only under the elevation
  categories the shift policy allows for tonight; a missing provisioning runtime is a skip reason
  and the shift continues under existing tools. Recovery runs before Start, so a shift never
  opens on an unproven baseline.

Artifact mode refuses repository-tool policies (`auto-add`, `review-missing`) and explains why;
only existing-tools is valid there. Inventory in `$NS/capabilities.json` is a cache: re-probe each
new shift or branch.

Unsupported permission modes must be reported before arming.

## One question, three files

Three files hold every setting, and no others exist. `rules.json` is the owner's permanent project
boundary — default denies, protected paths, forbidden commands, and any elevation the owner chose
to remember. `shift-defaults.json` remembers convenience choices (verification profile, typical
hours, tooling policy, review-first vs run-direct) that only prefill the next composition
question; it decides nothing on its own and never carries elevation. `shift-policy.json` is
tonight's authoritative snapshot — deadline, verification level, tooling policy, and every
allowance tagged `rules` or `one-shift` — written before arming and archived with the receipt at
clock-out.

Composition asks exactly one question, prefilled from `shift-policy.sh … defaults-get`: *"Same as
last time: `<profile>`, `<hours>h`, `<toolingPolicy>`, `<no elevation | allowances …>`? Yes, or
change."* A change answer may name a new profile, hour count, or tooling policy, and elevation in
words — *"allow docker tonight"* becomes a one-shift allowance in the shift policy; *"always allow
docker here"* becomes a permanent `rules.json` allowance, written by the composition step while the
shift is unarmed. The same question folds in the permission preflight's gaps
(`runtime/preflight-needs.sh` against every selected item and Hunt order): *"Items 4 and 7 need
`containers`: allow tonight, allow always, or leave them parked?"* Composition writes the resolved
policy with `shift-policy.sh … set --from-json -` before any compose, cut, or arm; review-first
writes nothing else, and run-direct arms immediately once it lands. Start never asks: it consumes
a queued policy, or arms with safe defaults (existing-tools, no allowances, remembered
verification and hours) when none was queued.

## Direct-mode decisions

Run directly means make progress, not avoid judgment:

- choose the strongest production-quality default;
- make reasonable, reversible decisions on the isolated branch or inside the artifact work target;
- preserve compatibility or include migration and rollback where a breaking change is justified;
- implement and verify the decision;
- record every significant choice, evidence, alternatives, shipped result, and rollback in
  `parking-lot.md`; then continue.

Stop for the owner only when the action is outside the granted coding-work boundary: publishing,
merging, deploying, deleting production data, exposing secrets, spending money, or changing legal or licensing policy.
A difficult or potentially breaking code change is not automatically outside the
boundary when it is isolated, tested, reviewable, and reversible.

## One shift contract

Any combination becomes one ordered work order, one punch list, one branch or artifact work target, one deadline where
required, and one set of receipts. In repository mode those receipts are work-target commits. In artifact mode they are files under `.nightshift/receipts/`. Never arm a separate shift per entry. The catalog entry remains
the definition of done; selection and launch modes decide who chooses it and whether discovery
pauses for approval.

A GitHub issue hunt cannot grow past the imported `Status: proposed` set the owner already
staged. Direct mode may rank inside that set; it must not search GitHub or add issues that were
not imported.
