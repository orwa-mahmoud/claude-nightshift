# Changelog

Installs pin to the `version` in `.claude-plugin/plugin.json`, so every entry here is a version
users receive. Dates are release dates; the tags carry the exact trees.

## v0.7.1 — the site is where the owner put it

Every skill resolves `.nightshift/` and `.claude/` against `$CLAUDE_PROJECT_DIR`, so the site stays
the site no matter where a shell has wandered. The working directory persists between commands and
follows gates, builds, and stack detection into the code repo; on the recommended layout — the code
repo a level below the project root — anything written relative to it lands in the repo instead of
the site.

- **Permissions reach the project.** `/nightshift:setup` writes
  `$CLAUDE_PROJECT_DIR/.claude/settings.local.json`, the file a headless revival inherits. A copy
  anywhere else grants the project nothing, and the night finds out at its first prompt.
- **Scaffolding, rules, gates, and the receipts repo are placed by path, not by proximity.** The
  receipts repo is created with `git -C`, since `git init` follows the working directory too.
- Six tests hold the rule across every skill, including ones not written yet.

## v0.7.0 — one place composes work, one place starts it

`/nightshift:start` asks nothing. Everything it needs was decided when the work was composed, so
the same command serves an interactive start, a headless revival, and a scheduled one. That single
property is what makes an unattended night schedulable at all, and it is why the ready shifts
moved: a command that prompts cannot run while its owner sleeps.

- **`/nightshift:hunt` composes the shift.** It offers the whole catalog rather than three fixed
  presets, takes more than one entry per night, asks for hours only where the ending needs them,
  and takes one free-text answer for scope — *"only `packages/api/`"*, *"use the in-memory test
  harness"* — added as its own bullet beneath the entry's contract, never in place of it. The
  assembled shift is shown exactly as it will be written before anything is armed, and answering
  *now* starts it there — no second command to type.
- **`/nightshift:quality` closes the same way.** After the read-only scan it offers three answers:
  **fix now**, which writes the items and starts the shift; **draft for later**, which stages them
  on the drafting table and arms nothing; or **ignore**. The punch list is written on nothing but
  an explicit *fix now* — an open box arms the gate for the current session, so the box and the
  start belong together or neither happens.
- **`/nightshift:start` executes what it finds.** With open items in the punch list it asks
  nothing and promotes nothing — parked orders and drafts stay where the owner left them, and the
  list is the shift exactly as written. Only when the punch list is empty does it speak: it shows
  what is parked and asks which to work. A cut is a move, never a copy, so an item never exists in
  two files. The deadline is read rather than requested, a spent one is swept as a leftover while
  one still in the future survives as tonight's plan, and an open-ended walkthrough with no clock
  is refused rather than started.
- **The shift catalog is the contribution surface.** `shift-catalog.md` gains a finite entry,
  *clear quality debt*, beside the three open-ended hunts, and `catalog-recipe.md` states what a
  new entry must declare: its ending, how it discovers work, its definition of done, what it will
  never do, its verification, and the stacks it supports. Entries are markdown; they touch no
  hooks, so the catalog can grow without the product growing.
- **`/nightshift:schedule` — the scheduler nightshift will not become.** It checks what an owner
  would otherwise discover at 4am — that work is actually queued in the punch list, that headless
  permissions will not stall the run, that nothing is registered twice — then prints the launchd
  plist or crontab line for the project and the single command that installs it. It registers
  nothing itself, because waiting for a clock stays the operating system's job: a process that
  sleeps for hours dies to a closed lid.
  Underneath it, `adapters/schedule.sh` is plain shell that spends no model tokens and needs no
  session. That is not an implementation detail — the moment an owner most wants to schedule a run
  is the moment their quota is gone, and a slash command is read by the model. The README documents
  the script directly for exactly that day. It refuses a second entry where one exists (two
  scheduled starts on one punch list is two agents on one shift), identifies a project by path
  rather than folder name so two checkouts named `api` never collide, and says plainly that a
  sleeping machine runs nothing.
- **foreman is removed.** It existed because Claude Code was once the only agent with hooks; Cursor,
  Codex and Kimi now ship lifecycle hooks of their own, so a generic outer loop is the weakest
  possible way to serve any of them. nightshift extends Claude Code through Claude Code's own
  extension points, and the README and CONTRIBUTING now say so as a scope rule: no schedulers, no
  dashboards, no second install channel.

## v0.6.1 — one copy

The rules file is the config, and it lives with everything else nightshift owns:
`.nightshift/rules.json`, copied as-is from the shipped template by setup, read by the hooks
directly on every tool call — an owner's edit applies from the very next action, nothing is
synced into settings, nothing needs a restart, and deleting `.nightshift/` removes all of
nightshift, rules included. Env vars of the matching names remain session-start overrides —
the test suite's lever and the one-off exception, never a copy to maintain.

- **The night never touches its own leash.** During a shift, the working session is denied
  the rules file — file tools and shell commands alike, the same pattern-match honesty as
  every guard here. A rule that must change mid-shift changes by the owner's hand and reads
  from the next tool call.
- **Setup migrates and cleans.** A pre-0.6.1 `.claude/nightshift-rules.json` is moved into
  `.nightshift/` (the hooks read the old home as a fallback until then), and setup offers to
  strip the `NIGHTSHIFT_*` env keys an earlier version synced. The receipts-repo question is
  asked neutrally: its default is no, and it is never presented as recommended.
- **The watchman reads its own cadence** (`watchMinutes`, `watchRetrySeconds`,
  `notifyCommand`, both revival orders) from the rules file at arm time; start no longer
  passes an interval.
- **No hidden defaults.** Every shipped value — both revival orders, the clock-out
  reinjection, the park message, the cadences — lives visibly in the template setup copies;
  the hooks carry no fallback copies. A missing or unreadable rules file fails loudly and
  closed: the gate still blocks, questions stay parked, the watchman refuses to arm — each
  naming the repair.

## v0.6.0 — the 500 night, start to finish

Start a shift, watch the very first call come back `API Error: 500`, and go to sleep anyway:
the watchman now carries that night from the first error to the morning receipts, and the
whole story — the 500, the revival, the finished work — is one conversation you open with
one click.

- **The wedge is the transcript's last word, read structurally.** Claude Code records an API
  failure as its own synthetic event, flagged `isApiErrorMessage:true`; the watchman requires
  that flag on the last conversation event before calling a live-but-quiet session wedged. An
  owner pasting an error report as a prompt, or an error the session already retried past, no
  longer reads as a wedge — if anything followed the error, somebody was there, and that
  session is not the watchman's to touch. The owner's Esc is read by the same rule: an
  interrupt is a pause only as the last conversation event — one the owner already resumed
  past is history, and a real death after that resume reads as death.
- **A 500 before first work is still the wedge.** The shift records its identity at the first
  tool call — but an outage can land before any tool runs, leaving no record. A project whose
  newest conversation ends in the host's error event now revives via `--continue`, which
  resumes that very conversation, instead of standing by all night behind "a live claude
  session in the project".
- **Session-first, and only the session.** The verdict reads the session's own signals in
  order — the owner's Esc above all, the shift's transcript, the recorded process, then the
  host's registry: `claude agents --json` listing the recorded id is the host saying alive
  (it even rescues a stale pid), and a clean roster without it is death evidence no folder
  churn can drown out. Project files never vote — a detached loop, a build, or a sync can
  neither mute the owner's Esc nor mask a dead session as alive.
- **Revival orders match what the session knows.** A resumed conversation carries its own
  context, so its order is one line: cut off, continue — the contract already lives in the
  thread, and the gate enforces the ending. The fresh-session fallback starts empty and gets
  the full pointer at the punch list. Both texts are the owner's (`revivalPrompt`,
  `freshRevivalPrompt`).
- **The morning is one click away.** A successful revival leaves a notice in
  `parking-lot.md` — the file the owner reads — with the thread's handles: `claude --resume
  <id>` for the terminal, the `cursor://` and `vscode://` deep links for the IDE panel. The
  first thing you open is the exact conversation: the error, the revival, and everything it
  finished. The one night event that needs the owner — a dead session no attempt could bring
  back — rings the morning whistle instead, once per outage.
- **Tighter cadence.** The watch interval defaults to 10 minutes (`NIGHTSHIFT_WATCH=N` still
  sets it), and a dead API never stretches the rhythm: three tries per wake, every wake,
  until the API answers.
- **The night cannot click Allow.** Setup now asks to enable `bypassPermissions` in the
  project's settings (recommended; written to `.claude/settings.local.json` so revivals
  inherit it), start warns once when no frictionless grant exists, and the README says the
  trade plainly. nightshift's guards are hooks and stay armed in every permission mode.
- **One rules file, every decision the owner's.** Setup copies a ready template to
  `.claude/nightshift-rules.json` and syncs it into the env block — clean JSON to edit, the
  escaping machine-written. It carries the per-tool denial map (`toolDeny`: your message
  per tool, an empty message lifts a rule, absent keys keep the defaults), every guard
  pattern, the stall cap and warning cadence, the watch cadence, the morning whistle, the
  watchman's revival orders, and the gate's clock-out reinjection. The env stays the enforcement surface, fixed at session start — the file is the
  owner's editor, never the agent's lever — and start warns when the file drifts from the
  running session's rules. Re-running setup after an update offers what the new template added
  — missing keys, a changed contract — and never touches the owner's words.
- **The receipts repo is opt-in.** A git repo living inside the project is not everyone's
  taste: setup now asks before `git init`-ing `.nightshift/`, and the default is no — the
  receipts remain as plain files, and the gate's snapshot commit is a no-op without the repo.
- **`/nightshift:archive` — the finished part becomes a dated record.** Ticked items move into
  `archive/<date>/shipped.md`, the journal rotates whole, snags and parked questions move only
  once they carry the owner's answer. The live files stay lean; what shipped stays on disk as
  plain dated facts. Start auto-rotates a journal past ~500 KB into the same archive.
- **The shift binds one session.** The gate holds, and the site rules govern, the recorded
  shift session alone — a second conversation in the same project chats, stops, and asks
  freely; the night is not its business unless the owner brings it. A watchman revival stays
  bound under whatever id the fallback chain gave it and re-claims the record, so the watchman
  follows the living thread. Start refuses to start a second agent beside a living one — it
  hands the owner the running thread's `claude --resume` and IDE deep link instead.
- **One writer per site.** Two sessions stopping at once could tear the stall counter, double
  the morning whistle, or collide in the receipts repo. The gate's decision tail now runs
  under a per-site lock (mkdir-based — every platform has it; a dead holder's lock is broken
  on sight, a live one is waited on, bounded), and the whistle marker is claimed with an
  exclusive create. The wait can never hang a session: an unlockable site is decided unlocked.

## v0.5.2 — strong evidence of death

The one truly harmful watchman failure is spawning a second agent beside a living one: a resumed
id APPENDS to the same session, so two writers interleave into one conversation while sharing a
working tree. v0.5.0 read liveness from project files alone — long reasoning, research, or a
25-minute test run writes none and looked dead. Revival now requires strong positive evidence of
death, never "looks stuck".

- **Liveness is a ladder.** The shift's transcript is the primary pulse — a live session streams
  every turn into it, project files or not. Project activity stays as the second rung. Then the
  process witness: the hooks record the claude ancestor's pid and start time alongside the
  session id, and the watchman checks that exact process — `kill -0` plus the start time, a pair
  no pid reuse can counterfeit. Alive with a quiet, unerrored transcript is long silent work:
  stand by. Dead is dead even while other tabs live in the project: revive. No pid recorded
  degrades to the conservative reading — any claude process working in the project stands the
  watchman by.
- **The 500 wedge is recognized, not guessed.** Claude Code writes API failures verbatim into
  the transcript ("API Error: 500 …", "529 Overloaded"). A live shift process whose quiet
  transcript ends in one is a session sitting at an errored prompt with nobody there to press
  retry — the night the watchman exists for. That combination revives; prose merely mentioning
  API errors does not match.
- **Every retry re-checks the whole ladder first.** A site that comes back to life mid-wake — or
  an owner who acts — cancels the remaining attempts. Each failed attempt re-baselines the
  sentinel, so the watchman's own error events in the transcript never read as site life.
- **The revival chain is real and logged per rung**: the recorded conversation first, `claude
  --continue` next, a fresh `claude -p` last — the morning log says exactly which recovery level
  carried the night.
- **The identity claim is atomic.** `.shift-session` is taken with an exclusive create — two
  racing first sessions cannot interleave; one record lands whole.
- **A revival's own exit is not the owner's hand on the door.** Spawned sessions carry a mark,
  and the `SessionEnd` hook stays inert for them — without it, the worker finishing (or dying on
  the API again) would write the clean-end marker under the recorded id and stand the watchman
  down mid-outage after the first revival.

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
  everything it knew before the crash: hours of context, decisions, where it stood mid-item. No
  record yet means `--continue`, and the last retry of a wake still falls back to a fresh
  session.
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
