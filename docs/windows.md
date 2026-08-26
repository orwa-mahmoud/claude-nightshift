# Native Windows

Nightshift has a native PowerShell path for setup, hooks, process ownership, recovery, and Task
Scheduler generation. It does not use WSL or depend on Git Bash, Node.js, Python, `jq`, a proxy, or
a second agent runtime.

## Choose the runtime deliberately

- **Native Windows has a bundled PowerShell path** for setup, hooks, process ownership, recovery,
  and Task Scheduler generation when Claude Code or Codex run in PowerShell, Git is installed
  natively, PowerShell 5.1 or later is present, and the workspace is on a local NTFS volume. CI
  verifies that path with local host fixtures; it does not load an authenticated host session.
- **WSL is supported as Linux.** Install and run the host, plugin, repository, and watchman inside
  the same WSL distribution, then use the POSIX commands documented elsewhere.
- **A split Windows/WSL run is unsupported.** Do not keep the host process on one side and the
  workspace, hooks, or watchman on the other.
- **Network shares and filesystems without Windows ACLs or hard links are unsupported for an
  active shift.** Atomic session claims and private lease files fail closed there.

Installing Git for Windows is optional for Claude Code itself, but Nightshift's work-target,
commit, and receipt behavior requires native Git. If Git Bash is installed, Claude Code may choose
it as the hook shell. The bundled launcher is written to detect Windows and transfer the hook to
PowerShell. That Git Bash transfer is not yet a CI-verified claim; prefer a native PowerShell host
session until it is.

## What has parity

The native path uses the same on-disk contract and marker names as macOS and Linux:

- setup copies only absent templates, writes `state-version`, records the selected Git work
  target, and can create the optional local-only receipts repository;
- PreToolUse binds one session, creates and enforces the process lease, protects `rules.json` and
  lease state, applies exact `toolDeny` keys, and enforces configured command and commit guards;
- Stop honors `STOP` first, releases completed or expired shifts, records stalls, commits optional
  receipts, and blocks while open Items remain;
- the watchman advances the lease before every child, passes the generation and nonce in that
  child's environment, and runs recovery in the persisted work target;
- the scheduler emits a daily Task Scheduler definition with `IgnoreNew`, so Task Scheduler and
  the process lease both refuse overlapping starts;
- Doctor, status's lease inspector, import-issues, archive retention, migrate-state,
  apply-profile, and export-support use bundled PowerShell helpers beside the POSIX scripts.
  Native Windows does not call `.sh` for those, and does not require `jq`, Python, Node, or a
  package manager. If `gh` is already on PATH, import-issues uses it; Nightshift never installs it.

Claude Code has no Windows-only command field in a plugin hook manifest. Nightshift therefore
dot-sources a small shell/PowerShell launcher from the shared manifest. POSIX hosts continue into
the existing shell hook; every Windows shell path continues into the bundled `.ps1` hook. Codex
uses its documented `commandWindows` override; the cmd.exe entrypoint launches the bundled hook
with Windows PowerShell and an explicit execution-policy bypass.

## Setup and start

Use the normal host skill: `/nightshift:setup` and `/nightshift:start` on Claude Code, or ask
Nightshift to set up and start on Codex. The skills select their PowerShell commands when the host
is native Windows.

The mechanical scaffold is also available without a model turn:

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\setup.ps1" `
  -Project (Get-Location) -WorkTarget C:\path\to\repository
```

Setup still asks before choosing gates, changing project permissions, migrating legacy state, or
creating a receipts repository. The script itself asks nothing.

When the opened folder is not the Nightshift workspace, the same plugin-root helper writes the
explicit link after the owner confirms both absolute paths:

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\link-workspace.ps1" `
  -HostRoot C:\path\to\task -Workspace C:\path\to\workspace
```

The panic stop from the Nightshift workspace — the folder that contains `.nightshift/`,
not a linked task root — is:

```powershell
New-Item -ItemType File -Force .nightshift\STOP
```

## Task Scheduler

Generate and inspect a task without registering it:

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\schedule.ps1" `
  -Project C:\path\to\workspace -Preflight
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\schedule.ps1" `
  -Project C:\path\to\workspace -At 04:05
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\schedule.ps1" `
  -Project C:\path\to\workspace -List
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\schedule.ps1" `
  -Project C:\path\to\workspace -Remove
```

The generator prints one PowerShell registration command and the complete XML. The action invokes
`powershell.exe` with an encoded command, preserves paths containing spaces, writes output to
`.nightshift\scheduled.log`, and registers nothing itself. The deterministic `Nightshift-*` task
name lives in Task Scheduler's existing root folder, so first registration needs no separate folder
creation.

The generated task uses the current user's interactive token. It can start a missed run when that
user is next logged in, but it does not wake or power on the machine and does not survive a logout
as a credentialed background account. Configure a credentialed task yourself only if that broader
Windows trust boundary is intentional.

## Doctor and other helpers

The same plugin-root PowerShell helpers cover Doctor, archive retention, import-issues, rule
profiles, and a local support bundle:

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\doctor.ps1" -Project C:\path\to\workspace
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\retain-history.ps1" -Project C:\path\to\workspace
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\import-issues.ps1" -Project C:\path\to\workspace -ListProposed
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\apply-profile.ps1" -Project C:\path\to\workspace -List
& "$env:CLAUDE_PLUGIN_ROOT\runtime\windows\export-support.ps1" -Project C:\path\to\workspace
```

## Process evidence and recovery

Windows hooks walk native process ancestry through `Win32_Process`; a recorded holder is identified
by both PID and UTC process start time. The watchman treats an access-denied or unavailable process
query as uncertainty and stands down. It never converts missing evidence into permission to spawn.

Claude can also consult its session roster and transcript. Codex has no equivalent Windows cwd
oracle for arbitrary peer processes, so when no recorded PID exists the native watchman treats any
exact-name Codex process as conservative live evidence. That can delay recovery when an unrelated
Codex session is open elsewhere, but it cannot create a second writer.

The host UI has the same display boundary on Windows as on other systems: a headless resume can
continue the durable conversation without refreshing an already-open panel. Reopen the recorded
thread to inspect or interact with it; the process lease already fences stale observed tool calls.

## Rule and filesystem details

PowerShell parses `rules.json` exactly with `ConvertFrom-Json`. `forbiddenCommands` and
`neverCommitPatterns` run through .NET regular expressions. Nightshift translates the common POSIX
classes used by existing rules (`[[:space:]]`, `[[:digit:]]`, `[[:alnum:]]`, and related classes)
and fails closed on any class it cannot map. `neverCommitPatterns` is case-insensitive, matching
the POSIX `grep -qiE` guard. Implicitly staging commits (`-a`, `--all`, or a pathspec after `--`)
inspect `git diff HEAD`, the same content those commits would write.

Session and lease files are written in one directory, claimed atomically, and protected with a
non-inherited ACL for the current user and Local System before capability content is written.
The ignored, private `.mutex-scope` file gives every path alias to that directory the same named
mutex identity, so junction, symlink, and substituted-drive paths serialize lease changes and
watchman ownership together. The named mutex uses the machine-wide namespace, with access limited
to the current Windows user and Local System, so separate console, RDP, and scheduler sessions
serialize against the same identity. Existing local receipts repositories exclude and untrack the
identity before it is used. A volume that cannot provide the required ACL and hard-link primitives
is refused rather than silently weakening the lease.

## Verification

The `windows-native` CI job runs the lifecycle suite under both Windows PowerShell 5.1 and
PowerShell 7. It uses local host fixtures—no account or model subscription—to cover:

- setup and paths containing spaces;
- workspace links and persisted work targets;
- Doctor, migrate-state, retain-history, import-issues, apply-profile, and export-support helpers;
- PID/start-time evidence;
- atomic session and lease ownership;
- command, rules-file, and lease-file denials;
- Stop release behavior;
- Task Scheduler XML, encoded command generation, and disposable native registration;
- normal Codex recovery through an npm-style `codex.cmd` launcher;
- recovery-child placement, generation/nonce inheritance, and live-process stand-down.

The checked Windows runner is x64. Native Windows on ARM64 is not yet a verified claim.

An authenticated first shift remains part of the
[first-night safety checklist](first-night-checklist.md), because CI can verify Nightshift's host
boundary without pretending to verify an owner's account, permissions, or desktop UI.
