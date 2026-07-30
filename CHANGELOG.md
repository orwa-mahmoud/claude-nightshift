# Changelog

Installs pin to the `version` in `.claude-plugin/plugin.json`, so every entry here is a version
users receive. Dates are release dates; the tags carry the exact trees.

## v0.5.1 — the shift knows its own session

Live dogfooding with two tabs in one project exposed the guess in v0.5.0: the watchman read "the
newest transcript" for the Esc tell and revived with `--continue`, and with a second session in
the project both could point at the wrong conversation.

- **The shift records its own identity.** Every hook receives the session id and transcript path;
  the first session to work under an active shift writes them to `.nightshift/.shift-session`,
  once. A second tab never overwrites the record.
- **The Esc tell reads the shift's own transcript** — a helper tab's interrupt proves nothing and
  is ignored. No record yet falls back to the newest transcript in the project.
- **The revival is `claude --resume <that id> -p`** — the shift's exact conversation, with
  everything it knew before the crash: hours of context, decisions, where it stood mid-item. A
  vanished session degrades to `--continue`, and the last retry of a wake still falls back to a
  fresh session.
- **The clean-exit marker is the shift's alone** — `SessionEnd` writes it only when the ending
  session matches the record, so closing an unrelated tab in the same project no longer stands
  the watchman down.
- `start` and the hunt cut clear the record with the other markers; setup gitignores it in the
  receipts repo.

## v0.5.0 — the night watchman

A Stop hook can only act inside a living session. A session killed by an API outage, a crash, or
a closed terminal fires no hooks — the punch list survived on disk, but nothing re-invoked the
agent, and the night was lost. The watchman is the outside half.

### The watchman

- `adapters/watchman.sh`, armed in the background by `/nightshift:start` and the hunt cut. It
  wakes every 20 minutes (`NIGHTSHIFT_WATCH=N` minutes; `0` disarms) and, only when boxes are
  open **and** nothing in the project has changed since the last wake, sends the conversation
  back to work.
- It stands down at every honest ending: a stop-work order, an ended shift, every box ticked, a
  spent deadline, or a clean session exit. A crash at the finish line still gets its clock-out —
  all-ticked-but-never-released and dead-past-deadline each spawn one closing run, so receipts
  and the morning whistle happen even when the session died first.
- An API outage costs a handful of logged attempts, not one per tick: 2–3 spawn tries per wake
  spaced ~30s/2m, then the interval backs off, doubling per failed wake up to 8×.
- One watchman per site (a pid file; a stale one is taken over). **Esc still means stop**:
  Claude Code records a user interrupt in the session transcript and a 500 or a crash never
  does — that is the tell. At a quiet wake the watchman reads the transcript tail: interrupt
  there, it stands by; none, it revives. Unreadable defaults to reviving — waking a paused
  session costs an apology, a lost night costs the night.
- The revival is `claude --continue -p` by default — it chains onto the **same conversation**,
  so the morning transcript is one unbroken thread in the terminal and the IDE extension alike.
  On the default agent, the last retry of a wake falls back to a fresh `claude -p`: if the
  transcript itself is what broke, `--continue` would fail every wake forever, and the punch
  list on disk is enough for a fresh session to carry on. `NIGHTSHIFT_WATCH_AGENT` overrides
  the command entirely.

### Hooks

- A `SessionEnd` hook writes `.nightshift/.session-end` when a session ends **cleanly** during an
  active shift. Crashes and kills never reach the hook — which is the tell: marker means the
  owner's hand closed the session and the watchman stands down; no marker means it died and the
  watchman revives it. `start` and the hunt cut clear the marker, re-arming the night.

## v0.4.2 — overrides the guards can't read are denied

### Guards

- A commit that relocates itself with `--git-dir` or `--work-tree` is denied whenever a commit
  guard is configured. The guards resolve `git -C <dir>` and `cd <dir> &&`, but those two flags
  point the commit past that resolution — the guard would inspect one repository while the commit
  lands in another. Unverifiable means denied, exactly like the ambiguous-repo case.
- With an expected identity configured, a commit that overrides identity on the command line —
  `-c user.email=`, `--author`, or a `GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_EMAIL` prefix — is denied.
  The guard reads the repository's configuration, and with an override present that read
  describes nothing.
- The no-push recipe is now `git .*push`, so config injection (`git -c k=v push`) cannot slip
  between the words. Commit messages remain scrubbed first: a message *mentioning* a flag is not
  a use of it.

### Docs

- The fine print states what the gate re-injects: the full working standard, at every stop
  attempt, so it never decays out of context — alongside what it cannot prove.

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
