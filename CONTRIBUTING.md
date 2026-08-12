# Contributing to claude-nightshift

Thanks for looking under the hood. The plugin is deliberately small — a
punch-list contract, a stop-gate hook, and skills that hold an agent to both —
so contributions should keep that shape.

## Ground rules

- **Open an issue first** for anything beyond a typo or small fix. The gate's
  behaviour is a contract; changes to it need discussion before code.
- **One concern per PR.** A hook fix and a docs fix are two PRs.
- **Shell must stay portable.** Hooks run under bash, and must work on macOS's
  bash 3.2 — no bashisms newer than 3.2, no GNU-only flags (`xargs -d`, `sed -i`
  without a suffix, etc.). Where a GNU tool has no portable equivalent, try it
  and fall back to the BSD form, as the deadline parser does.
- **Test the gate honestly.** If your change touches the stop-gate, include the
  transcript of an actual blocked stop and an actual permitted one in the PR
  description. The tests in `tests/` must pass.

## Setup

```bash
git clone https://github.com/orwa-mahmoud/claude-nightshift.git
# install as a local plugin, then run Nightshift: Setup in Codex or
# /nightshift:setup in Claude Code inside a scratch project
```

## Checks

```bash
bats tests/                          # test suite — brew install bats-core / apt-get install bats
git ls-files '*.sh' | xargs shellcheck -x  # lint — the same set CI checks
tests/coverage.sh                    # line coverage via kcov (runs in docker on non-Linux)
claude plugin validate . --strict    # manifest + marketplace validation
```

CI ([`ci.yaml`](.github/workflows/ci.yaml)) runs shellcheck, the bats suite, and plugin validation
on every push. The Bats suite runs on both Ubuntu and macOS; the macOS job keeps the system Bash
3.2 first on `PATH`.

## Releasing

Nothing is published by merging your pull request. Version numbers and the changelog are not
yours to edit — [release-please](.github/workflows/release-please.yaml) writes both from commit
subjects, and holds them in a pull request titled `chore: release x.y.z` that it refreshes on
every merge. The maintainer merges that pull request when a release is due; that merge tags the
commit and publishes the notes.

What decides the version is the subject line of your commits, so write them to the
[Conventional Commits](https://www.conventionalcommits.org/) spec:

| Subject | Effect |
| --- | --- |
| `fix: …` | patch — `0.7.4` → `0.7.5` |
| `feat: …` | minor — `0.7.4` → `0.8.0` |
| `feat!: …`, or a `BREAKING CHANGE:` footer | major |
| `docs: …` `chore: …` `ci: …` `test: …` `refactor: …` | no release, no changelog entry |

Only `fix:` and `feat:` reach the changelog, so a subject is user-facing text: say what the change
does for someone running a shift, not how it was implemented. Do not tag by hand, and do not edit
`plugins/nightshift/.claude-plugin/plugin.json` or `CHANGELOG.md` — a pull request that does will conflict with
the release it is trying to describe.

## What gets merged

Fixes that make the gate harder to fool, **new entries for the shift catalog**, and
docs that shorten the path to a first successful shift.

Shift catalog entries are the easiest way in: they are markdown, they touch no
hooks, and they grow the catalog without growing the product. Read
[`catalog-recipe.md`](plugins/nightshift/skills/nightshift/references/catalog-recipe.md) first — an
entry must declare its ending, how it discovers work, its definition of done, what
it will never do, its verification, and the stacks it supports. Every catalog PR is
read by a human before merge: a plausible entry can still be a bad night on someone
else's repository, and no automated check catches that.

nightshift supports Claude Code and Codex through each host's own extension points:
hooks, skills, and plugin manifests. Shared behaviour should stay aligned across
both hosts; host-specific code should be a thin integration, not a generic adapter
layer. Changes that stand outside those extension points are declined, however
useful they sound: dashboards, proxies, and second install channels such as npm or
Homebrew. The exceptions are OS scheduling and recovery code that exist only to
keep an *inside* promise when no live session can act.

## License

MIT — by contributing you agree your work ships under it.
