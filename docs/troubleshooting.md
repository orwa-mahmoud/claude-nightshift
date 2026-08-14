# Troubleshooting

Read-only checks first. Do not delete markers, rewrite `rules.json`, or kill processes until the
matching **Repair** says so. `/nightshift:doctor` prints what Nightshift resolved and classifies
offers; invoking it changes nothing. For a failed night you want to report, use the
[Failed shift](https://github.com/orwa-mahmoud/nightshift/issues/new?template=failed_shift.yml)
form — not a paste of the transcript.

Host differences that matter here: Claude Code's Stop hook refuses an early clock-out and its
watchman can revive a live session sitting on a host API-error event. Codex keeps the same files
and guards; a Codex session that is **alive but errored is stood by**, not revived, until that
signature is captured. Closing an interactive Codex session with open boxes hands the night to
the watchman — `touch .nightshift/STOP` is the stop-work order on every host.

## 0. Where is the site?

**Check.** From the folder you opened in Claude Code or Codex:

```sh
pwd
ls -ld .nightshift .nightshift-link 2>/dev/null
```

| You see | Meaning |
|---|---|
| `.nightshift/` directory | This folder owns run state. |
| `.nightshift-link` file, no directory | This task root points at another workspace. |
| neither | Nightshift is not set up here. |

An absent `.nightshift/` is not a crash. Run setup in the real project (`/nightshift:setup` on
Claude Code, or ask Nightshift to set up on Codex). ChatGPT scratch paths under
`/workspace/scratch/` are refused on purpose — open the real repository.

**Repair (link only).** If the task is open on a different folder than the workspace that already
has `.nightshift/`, create an explicit pointer. Nightshift never searches nearby folders:

```sh
plugins/nightshift/runtime/link-workspace.sh \
  --host-root /absolute/task/root \
  --workspace /absolute/nightshift/workspace
```

The target must already contain `.nightshift/`. Relative, missing, multiline, and symlink pointers
are rejected.

## 1. Unsupported or malformed `state-version`

**Check.** After resolving the workspace:

```sh
ls -l .nightshift/state-version
cat .nightshift/state-version
```

A current workspace has a regular file containing the integer `1` and a newline. A missing
file is legacy version `0` — hooks still run. A newer integer, a symlink, extra text, or
anything that is not a single unsigned integer fails closed: start, hooks, status, archive,
and recovery will not guess and will not rewrite the marker.

**Repair.** Upgrade Nightshift when the marker is newer than this plugin supports. Never
downgrade or overwrite a future version. For a missing marker, migrate only while unarmed
and only after an explicit yes:

```sh
plugins/nightshift/runtime/migrate-state.sh --project /absolute/workspace
```

That command writes only `.nightshift/state-version`. Doctor offers it as a confirmation
repair; invoking Doctor does not run it.

## 2. Invalid `.nightshift-link`

**Check.** If `.nightshift-link` exists:

```sh
ls -l .nightshift-link
wc -l .nightshift-link
cat .nightshift-link
```

A valid link is a regular file (not a symlink) with **exactly one absolute path** to a directory
that contains `.nightshift/`. Anything else fails closed: hooks and skills will not guess.

**Repair.** Remove the broken file and run `link-workspace.sh` again, or work from the workspace
that already owns `.nightshift/`. Do not hand-write a relative path.

## 3. Wrong workspace or work target

**Check.** Run state lives in the resolved workspace. The code repository may be that same folder,
or the single git child named in `.nightshift/work-target`:

```sh
# after resolving the workspace (pwd, or the link target)
sed -n '1p' .nightshift/work-target 2>/dev/null
git -C "$(sed -n '1p' .nightshift/work-target 2>/dev/null || pwd)" rev-parse --show-toplevel
```

Two git repositories as siblings of `.nightshift/` with no `work-target` is undecidable: commit
guards deny rather than pick one.

**Repair.** Re-run setup and choose the repository explicitly. Do not invent a `work-target` by
hand unless it is the absolute git top-level of the repo you mean.

## 4. Unreadable rules

**Check.**

```sh
ls -l .nightshift/rules.json
python3 -m json.tool .nightshift/rules.json >/dev/null
```

Watchman refuses to arm when `watchMinutes` is missing or not a whole number, or when
`watchRetrySeconds`, `revivalPrompt`, or `freshRevivalPrompt` are empty. The clock-out stall
guard stands down if `stallMax` / `stallWarnEvery` cannot be read. Editors can validate the file
against the [rules schema](knobs.md) without changing behaviour.

**Repair.** Re-run setup and accept missing keys it offers. Do not paste a half-file over an
owner-edited `rules.json`. During an active shift the session working the night is denied
editing this file — change it yourself between sessions.

## 5. STOP vs stale arming

**Check.**

```sh
ls -l .nightshift/STOP .nightshift/.shift-armed .nightshift/.ended \
  .nightshift/.session-end .nightshift/.stall .nightshift/.watchman 2>/dev/null
sed -n '1,5p' .nightshift/STOP 2>/dev/null
```

| Marker | Meaning |
|---|---|
| `STOP` | Stop-work order. The gate releases at the **next stop attempt**; open boxes stay open. Site rules stay armed until then. |
| `.shift-armed` | A shift was started. Without it, `punch-list.md` is only a to-do file. |
| `.ended` | The gate already clocked the shift out. |
| `.session-end` | Claude Code recorded a clean session end. Watchman stands down; start re-arms. |
| `.stall` | Stuck stop-attempt count. Not an ending. |

A leftover `STOP`, `.ended`, `.session-end`, or `.shift-session` from last night will surprise
tonight. `/nightshift:start` clears stale run-control markers before it arms. Do not delete them
by hand while a session is still working the list.

**Repair (you want the shift ended now).** From any terminal at the workspace that owns
`.nightshift/`:

```sh
touch .nightshift/STOP
```

**Repair (you want a new shift and no session is alive).** Run start. It is what clears last
night's leftovers. Killing `.watchman`'s pid is start's job when that pid is still live.

## 6. Missing session identity

**Check.** `.nightshift/.shift-session` is written on first work. Typical layout: session id,
transcript or rollout path, pid, process start time, host (`claude` or `codex`).

```sh
sed -n '1,5p' .nightshift/.shift-session 2>/dev/null
```

A 500 can land **before** the first tool call, so the file may be missing while the punch list is
open. On Claude Code the watchman then treats the newest conversation ending in the host's API-error
event as the wedge and resumes with `--continue`. On Codex, with no recorded id, revival falls
back to a fresh headless run; the punch list on disk is the handover.

**Repair.** Do not invent a session id. If the shift is still armed and boxes are open, let the
watchman run, or start a fresh session that reads the punch list. Pasting an id from another
project will append to the wrong conversation.

## 7. Watchman stood down or will not revive

**Check (read-only).** Tail the journal; do not truncate it:

```sh
tail -n 40 .nightshift/shift-log.md
ls -l .nightshift/.watchman .nightshift/.watchman-tick 2>/dev/null
```

Stand-down is success when the night already ended honestly. Matching log lines:

| Log (substring) | Host | What it means |
|---|---|---|
| `stop-work order — standing down` | both | `STOP` exists. |
| `shift is owned by` | both | This watchman is the wrong host. The other host's watchman owns the shift. |
| `clean session end` | Claude Code | Owner closed the session on purpose. |
| `owner pressed Esc — standing by` | Claude Code | Interrupt in the transcript tail. Not a death. `STOP` ends the shift. |
| `long silent work; standing by` | Claude Code | Process alive, quiet, no API-error tail. |
| `a claude session is live in this project` | Claude Code | Another Claude process in the project; revival refused to avoid two writers. |
| Codex process or rollout still growing | Codex | Alive; stood by. A live-but-errored Codex session is **not** revived. |
| `watchMinutes missing` / `cannot arm` | both | Unreadable rules. See §4. |
| `all N attempts failed` | Claude Code | API still down; knocks again next wake. |
| `resumed session returned` / `revival returned` | both | Revival succeeded. |

**Repair.** None, if the line is an honest ending. If rules cannot arm, fix `rules.json` and
re-run start. If the wrong-host watchman stood down, leave it — the recorded host's watchman is
the one that should be running. If you pressed Esc and wanted the night to continue, resume that
session yourself; the watchman will not.

To report a revival that should have fired and did not, file a
[Failed shift](https://github.com/orwa-mahmoud/nightshift/issues/new?template=failed_shift.yml)
with sanitized markers only.

## See also

- [Command reference](commands.md) — setup, start, status, doctor, stop, schedule
- [Owner knobs](knobs.md) — `rules.json` and env overrides
- [First-night safety checklist](first-night-checklist.md)
- [Security policy](../SECURITY.md) — gate-bypass reports stay private
