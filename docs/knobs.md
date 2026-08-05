# Owner knobs

Zero-config by default; every knob below is off until you set it (unset ⇒ the default described).

The contract itself is a knob too: the punch-list text above `## Items` and the rules file's
`clockOutMessage` are the owner's words. The shipped default asks one commit per item — the
receipts story — but the gate releases on ticks, and the stall guard counts a tick as progress
on its own, so a contract with the commit rule stripped runs a full night with no commits at
all (on Codex, such a night needs only the `workspace-write` sandbox).

**One file drives them all:** setup copies a ready template to `.nightshift/rules.json` —
clean JSON, yours to edit: the tool-deny map, the guard patterns, the cadences, the watchman's
revival orders, the gate's clock-out text. The hooks read the file directly on every tool call,
so an edit applies from your very next action — no sync, no restart, no second copy. During a
shift the file itself is guarded: the session working the night is denied touching it, so only
you set or lift a rule. The env vars below remain as session-start overrides for tests and
one-off exceptions.

| Env var | Effect |
|---|---|
| `NIGHTSHIFT_TOOL_RULES` | JSON map of tool name → denial message (rules file: `toolDeny`). A key denies that tool with your wording; an empty message lifts the rule; absent keys mean the default — AskUserQuestion parked, everything else allowed |
| `NIGHTSHIFT_REVIVAL_PROMPT` | your wording for the order a **resumed** conversation gets — default is one line ("you were cut off, continue"), because the thread carries its own context (rules file: `revivalPrompt`) |
| `NIGHTSHIFT_FRESH_PROMPT` | your wording for the **fresh-session** fallback's order — the only rung that starts with no context, so its default points at the punch list (rules file: `freshRevivalPrompt`) |
| `NIGHTSHIFT_GATE_MESSAGE` | your wording for the clock-out gate's DO-NOT-STOP reinjection (rules file: `clockOutMessage`) |
| `NIGHTSHIFT_STALL_WARN` | hold-mode stall warning cadence — warn every N stuck stop attempts (rules file: `stallWarnEvery`; default 3) |
| `NIGHTSHIFT_FORBIDDEN_COMMANDS` | deny any Bash command matching this `grep -E` pattern during a shift — your own site rules. `git .*push` keeps pushing yours for the night (the `.*` also catches `git -c k=v push`); `rm -rf\|docker\|terraform` fences the rest. The rules file is guarded during a shift, so only you set or lift a rule — never the agent working the night |
| `NIGHTSHIFT_EXPECTED_EMAIL` | during a shift, deny commits authored under any other identity |
| `NIGHTSHIFT_PROTECTED_DIRS` | during a shift, space/pipe-separated dir names never to `git add/commit/tag/remote` |
| `NIGHTSHIFT_NEVER_COMMIT_PATTERNS` | during a shift, deny a commit whose diff matches this `grep -E` pattern — the index, widened to the working tree when the command stages implicitly (`git commit -a`) |
| `NIGHTSHIFT_WATCH` | minutes between night-watchman wakes; `0` disarms it. Unset, the interval is the rules file's `watchMinutes` — shipped as **10** — and an unreadable rules file refuses to arm the watchman rather than guessing. The revival resumes **the shift's own conversation by id** (`claude --resume <recorded session> -p`) — one unbroken thread in the terminal and the IDE extension alike — degrading per attempt to `claude --continue -p` and last to a fresh `claude -p` in case the conversation itself is what broke. `NIGHTSHIFT_WATCH_AGENT="claude -p"` makes every revival a fresh session instead. On a codex-owned shift the codex watchman revives with `codex exec resume <recorded session>` and falls back to a fresh `codex exec` |
| `NIGHTSHIFT_STALL_MAX` | by default a stuck agent is held and red-flagged in the shift log, never clocked out; set `=N` to clock the shift out after N stuck attempts. |
| `NIGHTSHIFT_NOTIFY_CMD` | shift-end ping; runs with `$NIGHTSHIFT_SUMMARY` set (e.g. `say "$NIGHTSHIFT_SUMMARY"`). The watchman rings it too — once per outage — when a dead session could not be revived: the one night event that needs you. A successful revival never pages; it lands as a notice in `parking-lot.md` with the thread's resume command and deep links |

Every rule above is **shift-scoped**: it applies while `.nightshift/punch-list.md` has an open
`- [ ]` and the gate has not yet ended the shift. With no punch list, or once the last box is
ticked, your session is ordinary again and none of them are watching. They are site rules for the
night, not a background scanner.

The two commit knobs read git, so they work against the repository the commit lands in — one the
command names itself (`git -C <dir>`, `cd <dir> &&`), else the tool's working directory, the
project dir, or the single repo below it. Where that is genuinely ambiguous, such as a workspace
holding two repos with the commit run from the root, they deny and say so rather than guess.

**Changed in v0.4.0:** the commit guards resolve the repository they inspect, so they hold in the
recommended layout below as well as in-place. Commits there count as shift progress too.

**Changed in v0.3.0:** by default a stalled agent is now held and red-flagged, never clocked out —
in the clock-out gate. Set `NIGHTSHIFT_STALL_MAX=N` to restore
auto-clock-out after N stuck attempts.
