# nightshift was built by nightshift

This plugin was built as one nightshift shift. The build was an enforced punch list of items 0–9,
each finished to its own verify, gated, and landed as its own conventional commit. The clock-out
gate held every session; hardhat enforced the site rules chosen for this build — pushes denied,
committer identity vetted, the staged diff swept on every commit; every hook was linted before its
commit landed. The live `.nightshift/` state stayed local — private by default, the same default
the plugin sets for you — so this is a curated snapshot, not the live files.

The one-commit-per-item history below is the proof: read it top to bottom and you read the shift.

## The punch list — final

| # | Item | Result |
|---|---|---|
| 0 | Preflight — verify repo init, identity, layout | done (verify only, no commit) |
| 1 | Schema truth — pin plugin/hook/marketplace schemas to the live docs | done (private notes, no commit) |
| 2 | Scaffold + manifests + license + CI | done — 2 commits |
| 3 | The hooks — clock-out gate + hardhat + bats suite | done — 7 commits |
| 4 | Templates — punch list, drafting table, parking lot, snag log, walkthrough | done — 1 commit |
| 5 | The skill + commands (setup / start / status / stop) | done — 2 commits |
| 6 | Gates catalog + foreman + tests | done — 3 commits |
| 7 | Example + final README | done — 2 commits |
| 8 | Dogfood proof — this snapshot | done — 1 commit |
| 9 | SonarQube site inspection | done |

## The receipts — one conventional commit per item, real timestamps

```text
2026-07-13 21:57 · chore: plugin scaffold, manifests, license
2026-07-13 21:57 · ci: shellcheck + test workflow
2026-07-13 22:03 · feat(hooks): clock-out gate — punch-list file is the only truth
2026-07-13 22:04 · feat(hooks): stall red-tag + stop-work order + quitting time — bounded, interruptible runs
2026-07-13 22:08 · feat(hooks): hardhat — mechanical safety, zero-config core
2026-07-13 22:09 · feat(hooks): park-don't-ask — a question can't kill the shift
2026-07-13 22:11 · feat(hooks): morning whistle — optional shift-end ping
2026-07-13 22:27 · test: bats coverage for gate + hardhat + stall + stop-work + deadline + degradation
2026-07-13 22:36 · feat(templates): punch list, parking lot, snag log, walkthrough presets
2026-07-13 22:38 · feat(skill): the nightshift brain
2026-07-13 22:42 · feat(commands): setup, start, status, stop
2026-07-13 22:44 · feat(gates): stack-aware inspections — item gates + site inspections
2026-07-13 22:47 · feat(adapters): foreman — universal outer loop for any agent cli
2026-07-13 22:47 · test: gates detection + foreman termination paths
2026-07-13 22:49 · docs: example shift
2026-07-13 22:50 · docs: readme — story, vocabulary, honest caveats
```

The shift then closed with `docs: nightshift built nightshift — the receipts` (this file) and the
SonarQube site inspection. For the live, complete list, run `git log --oneline` in this repo.

## What enforced it

- **clock-out gate** — no session ended while a box was open; the contract was re-injected on every
  premature stop.
- **hardhat** — the site rules set for this build: every `git push` denied, every commit checked for
  the expected identity and swept for private identifiers before it was allowed. The guard even
  refused a Bash command that merely contained the word push, so the build had to route around its
  own rules.
- **the item gate** — each hook `bash -n`'d and shellcheck'd before its commit landed.

Structure, safety, and receipts — demonstrated on the plugin itself.
