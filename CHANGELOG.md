# Changelog

Installs pin to the `version` in `plugins/nightshift/.claude-plugin/plugin.json`, so every entry here is a
version users receive. Dates are release dates; the tags carry the exact trees.

## [0.14.4](https://github.com/orwa-mahmoud/nightshift/compare/v0.14.3...v0.14.4) (2026-08-23)


### Bug Fixes

* clarify persistent workspace guidance ([629e3b3](https://github.com/orwa-mahmoud/nightshift/commit/629e3b32d873322903de665079b5ee17d2eca0b9))

## [0.14.3](https://github.com/orwa-mahmoud/nightshift/compare/v0.14.2...v0.14.3) (2026-08-19)


### Bug Fixes

* stop treating the process-lease id as a secret ([6eb196d](https://github.com/orwa-mahmoud/nightshift/commit/6eb196df2d814ecff2da0b2333672158c5d68c15))

## [0.14.2](https://github.com/orwa-mahmoud/nightshift/compare/v0.14.1...v0.14.2) (2026-08-19)


### Bug Fixes

* qualify Nightshift paths and pair native Windows helpers ([7232b3d](https://github.com/orwa-mahmoud/nightshift/commit/7232b3db49987eef200bb40e4c1e9887c336ba66))

## [0.14.1](https://github.com/orwa-mahmoud/nightshift/compare/v0.14.0...v0.14.1) (2026-08-18)


### Bug Fixes

* **hardhat:** check Git paths for protectedDirs ([f1f3d26](https://github.com/orwa-mahmoud/nightshift/commit/f1f3d2675104aa896ac19693cdc40dfc6898c5df))
* **hardhat:** inspect the commit Git would write ([a84c225](https://github.com/orwa-mahmoud/nightshift/commit/a84c2257afb5ae0b02f52564dbf5258ccfdb8636))
* **hardhat:** protect armed-shift control files ([bc2e047](https://github.com/orwa-mahmoud/nightshift/commit/bc2e04712c536625d0dc17b20027f9e159a402e9))

## [0.14.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.13.1...v0.14.0) (2026-08-18)


### Features

* **compatibility:** verify remote development environments ([4051f7c](https://github.com/orwa-mahmoud/nightshift/commit/4051f7cd579f0ab25a1e645b8ab4432b6ed9b7f6))
* **recovery:** fence concurrent shift processes ([3efbac8](https://github.com/orwa-mahmoud/nightshift/commit/3efbac87f0f25a3d66e8339f405fb39f9b0eab65))
* **windows:** add native runtime support ([7d80a66](https://github.com/orwa-mahmoud/nightshift/commit/7d80a664ece3592910699b28b233968d9c1f829e))


### Bug Fixes

* share shift ownership and close review gaps ([e3643e9](https://github.com/orwa-mahmoud/nightshift/commit/e3643e9730013dd4dfc026cd53adf1c1885c0290))
* **skills:** align host roots and shift lifecycle ([46287d1](https://github.com/orwa-mahmoud/nightshift/commit/46287d1ccc3b1ebfb337440c362d82ce5ab3978c))

## [0.13.1](https://github.com/orwa-mahmoud/nightshift/compare/v0.13.0...v0.13.1) (2026-08-15)


### Bug Fixes

* preserve the directory subtitle in uploads ([c230e7d](https://github.com/orwa-mahmoud/nightshift/commit/c230e7d9c0eacb98041bca47ddd551363e158f7e))

## [0.13.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.12.0...v0.13.0) (2026-08-15)


### Features

* **shifts:** add custom timed owner walkthroughs ([4e484ed](https://github.com/orwa-mahmoud/nightshift/commit/4e484edc8ac5e4bdc88aaa7a04baa25cae1ffcf8))

## [0.12.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.11.0...v0.12.0) (2026-08-14)


### Features

* **archive:** add explicit history retention ([1e4cc4f](https://github.com/orwa-mahmoud/nightshift/commit/1e4cc4fa2c6647a1cc56935e49cef2fbb7b6f92b))
* **catalog:** add GitHub issue hunts ([c2257d7](https://github.com/orwa-mahmoud/nightshift/commit/c2257d72a94c330673cc8ab3472e1f5e3c35784a))
* **doctor:** export redacted support bundles ([f63deb8](https://github.com/orwa-mahmoud/nightshift/commit/f63deb84eb144a8fc5ea4378ef236f65bc4a3539))
* **github:** stage selected issues for shifts ([c182ef2](https://github.com/orwa-mahmoud/nightshift/commit/c182ef2cb8d9b2f07d12d6193e3266876c5d29b0))
* **rules:** add opt-in local profiles ([d2ddbe7](https://github.com/orwa-mahmoud/nightshift/commit/d2ddbe7ba9edd6cb57fec4e52c9777b9f1a222aa))
* **schedule:** generate systemd user timers ([7c6a010](https://github.com/orwa-mahmoud/nightshift/commit/7c6a010f74d2d522bad1e93006e4c24519c45def))
* **state:** version Nightshift workspaces ([45cfeb9](https://github.com/orwa-mahmoud/nightshift/commit/45cfeb98a4dab19ca0054e65c6ea7f55d1c8e316))


### Bug Fixes

* **ci:** align Linux portability checks ([9162265](https://github.com/orwa-mahmoud/nightshift/commit/9162265736f3117e0fa0381b433a33122fb4de22))
* **ci:** harden Linux runtime portability ([2c47003](https://github.com/orwa-mahmoud/nightshift/commit/2c470031c03c1c73a8039e802aefbc72d592db18))
* **github:** roll back partial queue promotion ([f090099](https://github.com/orwa-mahmoud/nightshift/commit/f090099425a10b87dbafe391a9c1f0fb60fc71b1))
* **recovery:** support minimal process environments ([4391c1f](https://github.com/orwa-mahmoud/nightshift/commit/4391c1f773ba35769ade9d89c131651aa5cda4e2))

## [0.11.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.10.0...v0.11.0) (2026-08-14)


### Features

* **catalog:** add accessibility repair shift ([aa1c0e4](https://github.com/orwa-mahmoud/nightshift/commit/aa1c0e454339cddf0e620e978087e4112a39900a))
* **catalog:** add API contract drift shift ([8c12b05](https://github.com/orwa-mahmoud/nightshift/commit/8c12b0545bbb3491b9e66ffc2965d62dda212fd4))
* **catalog:** add dead-code cleanup shift ([410bd66](https://github.com/orwa-mahmoud/nightshift/commit/410bd66e6dce250e93ff04012b9c37d9a9326c34))
* **catalog:** add flaky-test repair shift ([f289d53](https://github.com/orwa-mahmoud/nightshift/commit/f289d5332b0999e2c1b11a05dc1c08fd5735296e))
* **catalog:** add localization parity shift ([323d21f](https://github.com/orwa-mahmoud/nightshift/commit/323d21fff370902a838425e7c9ed8968bf6fc79c))
* **catalog:** add TODO debt shift ([593ea7b](https://github.com/orwa-mahmoud/nightshift/commit/593ea7bd380ffafeb5ef03b8a8f508147cf70049))
* **shifts:** add guided and automatic execution modes ([52946d1](https://github.com/orwa-mahmoud/nightshift/commit/52946d1d946774cf149294cca173c0ffea4584c5))

## [0.10.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.9.4...v0.10.0) (2026-08-14)


### Features

* **catalog:** add a CI warning cleanup shift ([c26b6b0](https://github.com/orwa-mahmoud/nightshift/commit/c26b6b0821fadaf8c4c1371d34a37cef389192b8))
* **catalog:** add a documentation drift shift ([3ae803b](https://github.com/orwa-mahmoud/nightshift/commit/3ae803b4e79ff95ff6b608ba15bd26268abbb4a6))
* **community:** add a catalog shift proposal form ([ce24c61](https://github.com/orwa-mahmoud/nightshift/commit/ce24c61e03491fc6459388a09da89601167ccc24))
* **community:** add a safe failed-shift report form ([20681e1](https://github.com/orwa-mahmoud/nightshift/commit/20681e12596355a78f524e70c8218a4018e3d529))
* **config:** add a schema for Nightshift rules ([0b22de5](https://github.com/orwa-mahmoud/nightshift/commit/0b22de58d636a54cd78c190a7289486f2e4cb81a))
* **diagnostics:** add a read-only Nightshift Doctor ([28c22eb](https://github.com/orwa-mahmoud/nightshift/commit/28c22eb075aea62e2dcc1b63fb4ea7f00ae1f66a))
* harden Nightshift diagnostics and cross-host reliability ([#92](https://github.com/orwa-mahmoud/nightshift/issues/92)) ([08e3263](https://github.com/orwa-mahmoud/nightshift/commit/08e32636f3843ee6116f37f668837ea4f20a2fa1))
* **recovery:** expose reason-coded watchman outcomes ([16bc18d](https://github.com/orwa-mahmoud/nightshift/commit/16bc18d5f36567aa2b47e4e4b79220df4505f71a))
* **schedule:** add a no-install preflight check ([e0f3b83](https://github.com/orwa-mahmoud/nightshift/commit/e0f3b8300d53f6500b53b5dc27b57e00171a1fb8))


### Bug Fixes

* **codex:** reject non-resumable session identities ([1227a01](https://github.com/orwa-mahmoud/nightshift/commit/1227a01b6f6275f8ef72dc1016637a296510ead3))
* **runtime:** close shift review gaps ([e530363](https://github.com/orwa-mahmoud/nightshift/commit/e530363e0d5e1bf39224ae4fb37288998190222b))

## [0.9.4](https://github.com/orwa-mahmoud/nightshift/compare/v0.9.3...v0.9.4) (2026-08-13)


### Bug Fixes

* **codex:** park native user questions during shifts ([a058e36](https://github.com/orwa-mahmoud/nightshift/commit/a058e369f849fef7f23223646ded38cdfdea0f1c))
* **codex:** park native user questions during shifts ([#58](https://github.com/orwa-mahmoud/nightshift/issues/58)) ([a39626e](https://github.com/orwa-mahmoud/nightshift/commit/a39626e1eee5433749492f9b7e64fa4c8086e32d))

## [0.9.3](https://github.com/orwa-mahmoud/nightshift/compare/v0.9.2...v0.9.3) (2026-08-12)


### Bug Fixes

* **state:** align remaining active-shift checks ([7108184](https://github.com/orwa-mahmoud/nightshift/commit/7108184233697097c4f70eabfbfc3999e0dcc593))
* **workspace:** link tasks to authoritative shift state ([a3a1992](https://github.com/orwa-mahmoud/nightshift/commit/a3a19927bd7fd53371a653df8594d670d31e5423))
* **workspace:** reject ambiguous link files ([13235d6](https://github.com/orwa-mahmoud/nightshift/commit/13235d6a219ea1b4d373f9b43277c02a070d0b04))

## [0.9.2](https://github.com/orwa-mahmoud/nightshift/compare/v0.9.1...v0.9.2) (2026-08-12)


### Bug Fixes

* harden Nightshift across Claude Code and Codex ([#53](https://github.com/orwa-mahmoud/nightshift/issues/53)) ([2ebfce5](https://github.com/orwa-mahmoud/nightshift/commit/2ebfce5ceaa2b3daf7f803e2c49a9887b4762ebb))
* **hardhat:** align active-shift detection across hosts ([0374ac8](https://github.com/orwa-mahmoud/nightshift/commit/0374ac876fb66706da67fa33cd1622ce76f9f67c))
* **schedule:** safely encode generated cron and launchd paths ([e713d3c](https://github.com/orwa-mahmoud/nightshift/commit/e713d3c1ee8a696d4a7b8ebfaba46410ec433e55))
* **session:** always record the Claude host in shift identity ([bdfb0aa](https://github.com/orwa-mahmoud/nightshift/commit/bdfb0aaad57369e9f2eceb9be17efef31da0f0af))
* **setup:** resolve a single repository inside parent workspaces ([20424b1](https://github.com/orwa-mahmoud/nightshift/commit/20424b1432bc55f2e06be75d2c4a4cfbedacb031))
* **skills:** clarify state-file roles across model workflows ([6ef7014](https://github.com/orwa-mahmoud/nightshift/commit/6ef701409774d2dc4eff5c3186fa6f785b875f55))
* **test:** measure coverage from current plugin paths ([0a3e6f7](https://github.com/orwa-mahmoud/nightshift/commit/0a3e6f7742ebf1a1342b75e47a1b9b5063a891e1))

## [0.9.1](https://github.com/orwa-mahmoud/nightshift/compare/v0.9.0...v0.9.1) (2026-08-12)


### Bug Fixes

* redirect temporary ChatGPT workspaces ([809c906](https://github.com/orwa-mahmoud/nightshift/commit/809c9066288a5f2d5c397d05d88e27c3fce20970))

## [0.9.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.8.1...v0.9.0) (2026-08-12)


### Features

* add evidence-backed product evolution to the ready-made hunt catalog
* preserve active opportunity progress across compaction and resumed sessions
* integrate product research and opportunity tracking with setup, status, and archive
* make Codex a first-class host alongside Claude Code ([7f62a2d](https://github.com/orwa-mahmoud/nightshift/commit/7f62a2dd1e59f1653b363191c1d9d7d3afad3a12))

## [0.8.1](https://github.com/orwa-mahmoud/nightshift/compare/v0.8.0...v0.8.1) (2026-08-05)


### Bug Fixes

* Codex packaging and host wording catch up to the release ([a1ab3a1](https://github.com/orwa-mahmoud/nightshift/commit/a1ab3a1fb5063c86051f13641d2d5ac9ab1afa93))

## [0.8.0](https://github.com/orwa-mahmoud/nightshift/compare/v0.7.4...v0.8.0) (2026-08-05)

nightshift runs on OpenAI Codex. One package, a manifest per host, and the same night either
way — the gate, the guards, the skills, the scheduler, and the watchman.

### Features

* the Codex clock-out gate and hardhat enforce the same shift — Claude's decisions behind Codex's own hook wiring, verified in a live session ([2bac060](https://github.com/orwa-mahmoud/nightshift/commit/2bac06066a4a72b2a6ce13e7ab1e89935ab77450))
* the night watchman works Codex shifts — a killed session is revived into its own conversation and the list is finished with nobody attached, verified with a live SIGKILL mid-shift ([fc3510f](https://github.com/orwa-mahmoud/nightshift/commit/fc3510f2b0ae6437763bb70467f327237b9852cb))
* the shift record names its host, so each watchman minds only its own shifts ([19d619f](https://github.com/orwa-mahmoud/nightshift/commit/19d619f18f451cd57e90b39d2ef9c9ee637d7f47))
* the skills speak both hosts — permissions, liveness and the watchman step fork per host, and the schedule generator takes `--agent` so one entry serves either runner ([349bfed](https://github.com/orwa-mahmoud/nightshift/commit/349bfedc775aab94364f92136de75f357428f7e6))
* Codex install is advertised: the `.agents` marketplace entry and the README's `codex plugin` commands ([e52c18a](https://github.com/orwa-mahmoud/nightshift/commit/e52c18a29b1238f4562eda3ea121bd8cdc2ce598))

Unattended Codex runs that commit use the `danger-full-access` sandbox — `workspace-write`
blocks `git commit`. nightshift's guards hold in every mode. A Codex session alive at an API
error is stood by, not revived.

## v0.7.4 — the plugin is a subdirectory

The plugin ships from `plugin/`. Tests, CI workflows and the README's screenshots no longer
install with it: an install is 216 KB, down from 876 KB.

## v0.7.3 — a shift is a file

Catalog entries live one per file in `skills/nightshift/references/shifts/`, and
`/nightshift:hunt` lists that directory rather than reading a single page. Adding a shift is two
new files — the entry and its test — with no edit to anything shared, so two people can contribute
one the same week without meeting in a diff. The structural rules glob the directory, so a new
entry is checked the moment it lands: its title declares its ending, and it carries a pasteable
item, a Verify line and a stated ending condition.

Two entries join the catalog, both finite, both working from a list the project's own tooling
produces:

- **Dependency upgrade sweep** — direct dependencies brought current one at a time, patches before
  majors, each behind the item gate and its own commit. The release notes are the work: a version
  bump that compiles is not an upgrade. A major that sprawls past a bounded attempt is reverted
  clean and parked, because a half-migrated major leaves the tree worse than the old version did.
  Prereleases are refused, and the lockfile, the package manager and the runtime version are the
  owner's.
- **Vulnerability sweep** — advisories cleared critical-first, so an interrupted night cleared what
  mattered. It never downgrades to satisfy an advisory and never adds a suppression: where the only
  offered fix is an older version, or the advisory sits in a transitive dependency, it parks the
  decision with the link and the severity.

## v0.7.2 — a shift starts when you start it

`/nightshift:start` is what puts a session on shift. It writes `.nightshift/.shift-armed`, and
until that marker exists the punch list is an ordinary to-do file — the clock-out gate holds
nobody, hardhat's guards apply to no one, and a session that writes items while planning still
stops freely. Every way in already runs start: interactively, from the scheduler's
`claude -p '/nightshift:start'`, and through a revival that re-claims the record it left behind.

- **The gate binds the session start hands it.** The hooks read the shift record; they no longer
  create one, so the shift is never inherited by whichever session happens to trip a hook first.
  Ending a shift disarms the site, so the guards leave with the night that needed them.
- **Boxes count under the `## Items` heading only.** A checkbox anywhere above it is contract
  prose — an owner's note, an example — and holds nothing. The watchman counts the same range as
  the gate, so the two can't disagree about whether work remains.
- **The contract names the Items list without repeating its heading**, leaving one `## Items` in
  the file for anything that splits on it.
- **Every path that starts a shift arms it** — `/nightshift:hunt` answering *now* and
  `/nightshift:quality` answering *fix now* both begin the shift where they stand, so both write
  the marker. A stop-work order disarms the site whether or not a list survived to summarise.
- **`/nightshift:status` says whether a shift is running**, rather than leaving open boxes to imply
  it, and counts the same range the gate does.
- Fifteen tests cover the arming boundary from both sides.

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
