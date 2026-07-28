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

## What gets merged

Fixes that make the gate harder to fool, adapters for more harnesses, and docs
that shorten the path to a first successful shift. Features that widen scope
(schedulers, dashboards, integrations) will usually be declined — the plugin's
value is that it does one thing strictly.

## License

MIT — by contributing you agree your work ships under it.
