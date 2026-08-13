# A verified Nightshift shift in Codex

Nightshift 0.9.2 was hardened in Codex using Nightshift's own workflow. The run started from an
11-item punch list, kept all work on one branch, and committed each finished item separately. This
receipt links to the permanent merged history; it does not depend on the deleted working branch or
local `.nightshift/` files.

## Outcome

- **11 of 11 items completed.** The shift covered host parity, session identity, scheduler safety,
  coverage reporting, contract tests, contributor guidance, security wording, first-night guidance,
  parent-workspace setup, state-file roles, and shared hook decision cores.
- **One commit per item.** Every item remained independently reviewable after the normal merge.
- **Verification passed before handoff.** The complete Bats suite reported 248 passing tests;
  ShellCheck and strict Claude plugin validation also passed.
- **Merged and released.** The work landed through
  [PR #53](https://github.com/orwa-mahmoud/nightshift/pull/53) and shipped in
  [v0.9.2](https://github.com/orwa-mahmoud/nightshift/releases/tag/v0.9.2).

## Item receipts

All timestamps are Dubai time (UTC+04:00) on 2026-08-12. Each line links to the preserved commit:

- `21:17` · [fix(hardhat): align active-shift detection across hosts](https://github.com/orwa-mahmoud/nightshift/commit/0374ac876fb66706da67fa33cd1622ce76f9f67c)
- `21:19` · [fix(session): always record the Claude host in shift identity](https://github.com/orwa-mahmoud/nightshift/commit/bdfb0aaad57369e9f2eceb9be17efef31da0f0af)
- `21:22` · [fix(schedule): safely encode generated cron and launchd paths](https://github.com/orwa-mahmoud/nightshift/commit/e713d3c1ee8a696d4a7b8ebfaba46410ec433e55)
- `21:32` · [fix(test): measure coverage from current plugin paths](https://github.com/orwa-mahmoud/nightshift/commit/0a3e6f7742ebf1a1342b75e47a1b9b5063a891e1)
- `21:33` · [test(contracts): cover remaining shifts and lifecycle invariants](https://github.com/orwa-mahmoud/nightshift/commit/e32066604cde27c463697aa3d7cb18b99727511b)
- `21:37` · [docs(github): align templates with dual-host support](https://github.com/orwa-mahmoud/nightshift/commit/884f8caa0464370bc40faa5dac2111bef478c389)
- `21:39` · [docs(security): clarify runtime and notification side effects](https://github.com/orwa-mahmoud/nightshift/commit/11fa0423434ea2630242c8c56de6025945d7501f)
- `21:40` · [docs: add unattended first-night checklist](https://github.com/orwa-mahmoud/nightshift/commit/89e01d788e17eaa864c44f2b9bda38358da51d83)
- `21:48` · [fix(setup): resolve a single repository inside parent workspaces](https://github.com/orwa-mahmoud/nightshift/commit/20424b1432bc55f2e06be75d2c4a4cfbedacb031)
- `21:52` · [fix(skills): clarify state-file roles across model workflows](https://github.com/orwa-mahmoud/nightshift/commit/6ef701409774d2dc4eff5c3186fa6f785b875f55)
- `21:56` · [refactor(hooks): share gate and hardhat decision cores across hosts](https://github.com/orwa-mahmoud/nightshift/commit/7c89a474f9aefb414e751066e974c59e78bb8162)

## Permanent handoff

The item commits were merged without squashing, so the reviewable history survived. The merge is
[2ebfce5](https://github.com/orwa-mahmoud/nightshift/commit/2ebfce5ceaa2b3daf7f803e2c49a9887b4762ebb),
and the released tree is pinned by the
[v0.9.2 tag](https://github.com/orwa-mahmoud/nightshift/tree/v0.9.2).

This proves the bounded claim: Nightshift can keep a real Codex maintenance run anchored to an
explicit punch list and leave a reviewable commit trail. It does not claim that Codex has Claude
Code's identical session lifecycle or revival behavior.
