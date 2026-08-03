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
# install as a local plugin and run /nightshift:setup in a scratch project
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

Installs are pinned to `version` in `.claude-plugin/plugin.json` — users receive updates only when
it changes. Bump it, add the matching `## vX.Y.Z` section to [`CHANGELOG.md`](CHANGELOG.md), and
merge to `main`: CI tags the release and publishes it with that section as the notes. Do not tag by
hand.

Two gates enforce this on a pull request. A change to `hooks/`, `skills/`, `adapters/` or
`.claude-plugin/` without a version bump fails, because installs pinned to the old version would
never receive it. A bump with no changelog section behind it fails too, since the release job reads
its notes from there and a tag with nothing behind it is worse than no tag.

## What gets merged

Fixes that make the gate harder to fool, adapters for more harnesses, and docs
that shorten the path to a first successful shift. Features that widen scope
(schedulers, dashboards, integrations) will usually be declined — the plugin's
value is that it does one thing strictly.

## License

MIT — by contributing you agree your work ships under it.
