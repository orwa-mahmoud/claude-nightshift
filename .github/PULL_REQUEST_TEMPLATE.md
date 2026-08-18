<!-- Thanks for contributing to Nightshift! -->

## What does this PR do?

<!-- A short summary of the change and the motivation. Link any related issue: "Closes #12". -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] Harness parity (shared Claude Code / Codex behaviour)
- [ ] Docs / chore / refactor (no behaviour change)
- [ ] Gate behaviour change (discussed in an issue first — see CONTRIBUTING)

## Checklist

- [ ] I ran the focused checks for this area from the
      [contribution map](https://github.com/orwa-mahmoud/nightshift/blob/main/docs/contribution-map.md).
- [ ] `shellcheck` and the `bats` suite pass locally.
- [ ] Shell stays portable: macOS bash 3.2 / zsh — no newer bashisms, no GNU-only flags.
- [ ] If the stop-gate changed: the PR description shows a transcript of one
      blocked stop and one permitted stop.
- [ ] Docs updated if commands, hooks, or the contract changed.
