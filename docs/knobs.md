# Owner knobs

The scaffolded rules file carries every supported key. Optional guards are off until you set them;
the two explicit question-tool entries default to parking so an unattended shift does not wait for
the owner.

The contract itself is a knob too: the punch-list text above `## Items` and the rules file's
`clockOutMessage` are the owner's words. The shipped default asks one commit per item in
repository mode, or one artifact receipt per item in artifact mode — the
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

## Editor schema

Editors that honor JSON Schema (VS Code, Cursor, JetBrains) catch invalid names, types, and
values in `.nightshift/rules.json` before a shift. The shipped template sets `$schema` to the
schema file in this repository. If your copy has no `$schema` line, point the editor at
[`nightshift-rules.schema.json`](../plugins/nightshift/skills/nightshift/references/nightshift-rules.schema.json)
with a workspace setting — it does not change runtime behaviour:

```json
{
  "json.schemas": [
    {
      "fileMatch": ["**/.nightshift/rules.json"],
      "url": "https://raw.githubusercontent.com/orwa-mahmoud/nightshift/main/plugins/nightshift/skills/nightshift/references/nightshift-rules.schema.json"
    }
  ]
}
```

## Tool rules

`toolDeny` uses the exact, case-sensitive `tool_name` reported by each host. A non-empty value
denies that tool and becomes the model-facing reason; an empty value explicitly allows it. An
unlisted optional tool is allowed. “Allows” here lifts this map entry; command, commit, protected
directory, and rules-file guards still apply independently.

The generated file always carries three native question names:

```json
{
  "toolDeny": {
    "AskUserQuestion": "Park the question with a sensible default and continue.",
    "request_user_input": "Park the question with a sensible default and continue.",
    "AskQuestion": "Park the question with a sensible default and continue."
  }
}
```

`AskUserQuestion` controls Claude Code; `request_user_input` controls Codex; `AskQuestion`
controls Cursor. They are separate on purpose, so each may have different wording. Keep all three
keys present: delete one and that host's question tool reports an invalid configuration instead of
applying an invisible default. Set its value to `""` to allow the question tool.

Cursor's shell tool reports as `Shell` (not `Bash`). Add a `toolDeny.Shell` entry when you want the
same command-map denial on Cursor; the shared command-pattern guards (`forbiddenCommands` and
friends) already treat `Shell` like `Bash`.

The installed host loads its own hook manifest, so the runtime knows which native name arrived.
Setup does not generate or persist a host-specific rules file; keeping all three entries makes one
workspace portable between Claude Code, Codex, and Cursor.

Workspaces created before `request_user_input` or `AskQuestion` was added are missing that host's
key. After upgrading, re-run setup and accept the offered key; Setup adds nothing without
confirmation.

Allowing the tool removes the mechanical denial. The scaffolded punch-list contract,
`clockOutMessage`, and `freshRevivalPrompt` still say “park, don't ask”; owners who want an
interactive shift must change those instructions before arming it too.

Any other observable tool can use the same map:

```json
{
  "toolDeny": {
    "AskUserQuestion": "",
    "request_user_input": "Park the question and continue.",
    "AskQuestion": "Park the question and continue.",
    "Bash": "Shell commands are disabled for this shift.",
    "mcp__github__delete_file": "Repository deletion is disabled for this shift."
  }
}
```

Codex reports file edits as `apply_patch`; `Edit` and `Write` are matcher aliases, not the
canonical input name. Use `"apply_patch"` when configuring Codex file-edit policy.

The hook manifests use the documented catch-all matcher. Claude Code sends built-in and MCP
`PreToolUse` calls except host-defined exclusions such as `EndConversation`; see the
[Claude Code hook matcher reference](https://code.claude.com/docs/en/hooks#matcher-patterns).
Codex sends shell, file-edit, MCP, and other local function tools, but hosted tools such as its web
search do not enter the hook path; see
[Codex tool coverage](https://developers.openai.com/codex/hooks#tool-coverage).

JSON does not support comments. The file's `$schema` supplies editor descriptions and examples;
this section is the raw-file reference. POSIX hooks normalize `toolDeny` with `jq` or Python;
native Windows hooks use PowerShell's built-in JSON parser. Matching stays exact, and a POSIX
armed shift fails closed when neither parser is available. The bound shift session also cannot use
any observable tool to inspect or change `rules.json`; edit it from the owner session and the next
shift tool call reads the change.

| Env var | Effect |
|---|---|
| `NIGHTSHIFT_TOOL_RULES` | Session override for the exact-name JSON map above (rules file: `toolDeny`). Include both question keys when replacing the map |
| `NIGHTSHIFT_REVIVAL_PROMPT` | your wording for the order a **resumed** conversation gets — default is one line ("you were cut off, continue"), because the thread carries its own context (rules file: `revivalPrompt`) |
| `NIGHTSHIFT_FRESH_PROMPT` | your wording for the **fresh-session** fallback's order — the only rung that starts with no context, so its default points at the punch list (rules file: `freshRevivalPrompt`) |
| `NIGHTSHIFT_GATE_MESSAGE` | your wording for the clock-out gate's DO-NOT-STOP reinjection (rules file: `clockOutMessage`) |
| `NIGHTSHIFT_STALL_WARN` | hold-mode stall warning cadence — warn every N stuck stop attempts (rules file: `stallWarnEvery`; default 3) |
| `NIGHTSHIFT_FORBIDDEN_COMMANDS` | deny any matching command during a shift — POSIX uses `grep -E` against Bash; native Windows uses .NET regular expressions against the host command string. `git .*push` keeps pushing yours for the night (the `.*` also catches `git -c k=v push`); `rm -rf\|docker\|terraform` fences the rest. An invalid pattern fails closed and names this env var; fix it in session settings. The rules file is guarded during a shift, so only you set or lift a rule — never the agent working the night |
| `NIGHTSHIFT_EXPECTED_EMAIL` | during a shift, deny commits whose repository `git config user.email` is not this identity — POSIX and native Windows both read that config. A command-line override (`-c user.email=`, `--author`, `GIT_AUTHOR_EMAIL`) is denied because the guard cannot verify it |
| `NIGHTSHIFT_PROTECTED_DIRS` | during a shift, space/pipe-separated dir names never to `git add/commit/tag/remote`. Matching uses the paths Git would write, with `/`; native Windows also normalizes `\` in those Git paths before comparing |
| `NIGHTSHIFT_NEVER_COMMIT_PATTERNS` | during a shift, deny a commit whose diff matches this pattern — POSIX `grep -E`; native Windows .NET regular expressions, case-insensitive like POSIX `grep -qiE`. The index is widened to the working tree when the command stages implicitly (`git commit -a`). An invalid pattern fails closed and names this env var; fix it in session settings |
| `NIGHTSHIFT_WATCH` | minutes between night-watchman wakes; `0` disarms it. Unset, the interval is the rules file's `watchMinutes` — shipped as **10** — and an unreadable rules file refuses to arm the watchman rather than guessing. The revival resumes **the shift's own conversation by id** (`claude --resume <recorded session> -p`) — the same recorded conversation id in terminal and IDE history. Before each spawn the watchman advances a process lease, so the recovered process owns observable shift tools and older generations are fenced. An IDE panel already open on that thread cannot auto-refresh while the headless revival appends to it; [reopen the thread instead](how-it-works.md#reopening-a-revived-thread). The watchman degrades per attempt to `claude --continue -p` and last to a fresh `claude -p` in case the conversation itself is what broke. On a codex-owned shift the codex watchman revives with `codex exec resume <recorded session>` and falls back to a fresh `codex exec`. Cursor keeps two conversation stores: the IDE Agent tab records a `conversation_id` under `~/.cursor/projects/.../agent-transcripts`, and `agent --resume` talks only to the CLI store under `~/.cursor/chats`. Never pass the IDE id to `agent --resume` — that is a different chat. The Cursor watchman mints a CLI worker on the first IDE death, records it in `.shift-worker`, and `--resume`s that same id on later wakes. The origin IDE tab is pointed at `agent --resume="<cli_id>" --workspace "<abs>"` |
| `NIGHTSHIFT_WATCH_AGENT` | session override for the rules file's `watchAgent`. Empty (shipped) keeps each host's default resume ladder. A non-empty value is the spawn command used verbatim on every revival attempt — for example `claude -p` forces a fresh Claude session and skips resume/`--continue`. Codex uses the same key for a verbatim `codex exec …` override |
| `NIGHTSHIFT_RECEIPTS_AUTO_COMMIT` | session override for `receiptsAutoCommit`. Shipped **false**: even when Setup created a local receipts git under `.nightshift/`, clock-out and Archive do not commit it — the owner does. Set `true` only if you want the headless `nightshift@localhost` snapshot on every shift end / Archive |
| `NIGHTSHIFT_STALL_MAX` | by default a stuck agent is held and red-flagged in the shift log, never clocked out; set `=N` to clock the shift out after N stuck attempts. |
| `NIGHTSHIFT_NOTIFY_CMD` | shift-end ping; runs as unrestricted owner-provided shell with `$NIGHTSHIFT_SUMMARY` set. POSIX uses `sh -c` (e.g. `say "$NIGHTSHIFT_SUMMARY"`); native Windows uses PowerShell `Invoke-Expression` (e.g. `Write-Host $env:NIGHTSHIFT_SUMMARY`). It can access the network if your command does. The watchman rings it too — once per outage — when a dead session could not be revived: the one night event that needs you. A successful Claude revival never pages; after the headless subprocess exits, it lands as a notice in `parking-lot.md`, with the thread's resume command and deep links when a session id was recorded. Successful Codex revivals log to `shift-log.md` only |

**Recovery display.** The watchman does not require an owner to monitor it. Reopening a revived
thread is currently only how the owner refreshes a stale panel before inspecting or interacting;
the linked upstream refresh work would make that handoff smoother, not enable recovery itself.

**Local profiles.** `runtime/apply-profile.sh` (native Windows: `runtime/windows/apply-profile.ps1`)
can preview or copy every version-1 JSON file in
`plugins/nightshift/skills/nightshift/references/profiles/`. That is a
one-time local write, not a policy subscription. Fill keeps every owner value and refuses a file
missing either native question policy. Replace starts from the complete shipped template, applies
the profile, and shows the full next file first. Apply only while unarmed. Native Windows uses
PowerShell's JSON parser; it does not require `jq`.

**Retention** lives in the same rules file under `retention`, and is not shift-scoped: it is
read only by Nightshift Archive. Both `runtimeLogDays` and `archiveDays` default to `0`
(keep forever). A positive integer is an opt-in age in days. Archive prints the exact
eligible paths first; deletion needs an explicit yes and never runs from a hook, start,
status, Doctor, or recovery.

Every rule above is **shift-scoped**: it applies to the bound session while `.shift-armed` exists,
`.nightshift/punch-list.md` has an open `- [ ]`, and the gate has not ended the shift. With no
armed shift, or once the last box is ticked, your session is ordinary again and none of them are
watching. They are site rules for the night, not a background scanner.

The two commit knobs read git, so they work against the repository the commit lands in — one the
command names itself (`git -C <dir>`, `cd <dir> &&`), else the tool's working directory, the
project dir, or the single repo below it. Where that is genuinely ambiguous, such as a workspace
holding two repos with the commit run from the root, they deny and say so rather than guess.

**Changed in v0.4.0:** the commit guards resolve the repository they inspect, so they hold in the
recommended layout below as well as in-place. Commits there count as shift progress too.

**Changed in v0.3.0:** by default a stalled agent is now held and red-flagged, never clocked out —
in the clock-out gate. Set `NIGHTSHIFT_STALL_MAX=N` to restore
auto-clock-out after N stuck attempts.
