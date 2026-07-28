# Changelog

Installs pin to the `version` in `.claude-plugin/plugin.json`, so every entry here is a version
users receive. Dates are release dates; the tags carry the exact trees.

## v0.4.1 — a page of its own

- `homepage` in both manifests points at <https://orwamahmoud.com/nightshift/>, which explains what
  the plugin does and what it deliberately does not. `repository` still points at the source, so the
  two fields no longer say the same thing.

## v0.4.0 — guards look where the commit lands

### Guards

- Commit guards inspect the repository a command names — `git -C <dir>`, `cd <dir> &&` — instead
  of the session's working directory, so a commit aimed at a sibling repo is checked where it
  lands. Where the target is genuinely ambiguous they deny rather than guess.
- The never-commit sweep widens from the index to the working tree against `HEAD` whenever a
  command stages implicitly. `git commit -a` and pathspec commits stage as they run, so the index
  alone never described them.
- Guards resolve correctly for projects under a dotted path. The child-skipping rule matched any
  hidden component anywhere in the path, which denied every commit in such a project.
- A stop-work order keeps the site rules armed. The agent works on until its next stop attempt,
  and the gate now writes `.nightshift/.ended` when it truly releases — that alone stands the
  rules down.
- An unparseable `NIGHTSHIFT_FORBIDDEN_COMMANDS` or `NIGHTSHIFT_NEVER_COMMIT_PATTERNS` is refused
  with a message instead of reading as "no match".
- `NIGHTSHIFT_PROTECTED_DIRS` matches whole path components, so `ai_docs` no longer condemns
  `ai_docs_public`, and only a commit message is blanked before matching — a forbidden command
  inside quotes is still seen.

### Shifts

- `/nightshift:start` and `/nightshift:hunt` clear the same five stale markers before anything
  writes a new deadline. A spent deadline used to end the next shift at its first stop attempt
  with nothing done; a leftover stop-work order made a hunt a no-op.
- `/nightshift:quality` puts accepted proposals on the drafting table. Writing them straight into
  the punch list armed the clock-out gate for every session in the project, including the one
  that ran the command.
- A commit in the repo below the project dir counts as progress, in the clock-out gate and in
  foreman alike — the recommended layout puts it there.
- Receipts commit with signing disabled, so a global `commit.gpgsign` cannot silently discard the
  night's record, and a failed receipts commit is logged rather than swallowed.
- `foreman.sh` rejects an option with no value instead of spinning forever on a `shift` that
  cannot move.

### Packaging and docs

- Slash commands live in `skills/`, the layout the plugin docs recommend. Invocation names are
  unchanged.
- Every guard is documented as shift-scoped, the stop-work order as landing at the next stop
  attempt, and the deadline as a whistle rather than an axe.
- Releases are tagged from the manifest version by CI, and a pull request that changes shipped
  files without bumping it fails.

## v0.3.0 — a stalled shift is held, never sent home

- A stalled shift is held and red-flagged by default instead of being clocked out; `NIGHTSHIFT_STALL_MAX=N`
  restores auto-clock-out, in the gate and the foreman loop alike.
- `/nightshift:hunt` stages the ready-made overnight jobs as work orders — the item and its hours
  park together, and the cut starts the clock.
- Hook and foreman hardening from a review pass, each finding with a test.

## v0.2.0 — nothing is blocked out of the box

- Nothing is blocked out of the box. Every safety rule became the owner's opt-in, replacing the
  built-in denials.
- `/nightshift:quality` added; the spot-check hook retired.
- CI validates the plugin and marketplace manifests on every push.

## v0.1.0 — the clock-out gate

- First release: the clock-out gate (Stop hook), hardhat (PreToolUse guard), park-don't-ask, the
  morning whistle, the nightshift skill, the punch-list/parking-lot/snag-log templates,
  stack-aware gates, `/nightshift:setup|start|status|stop`, and `adapters/foreman.sh` for other
  agent CLIs.
