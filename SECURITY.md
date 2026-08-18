# Security Policy

## Supported versions

Only the latest release is supported. Nightshift itself has no telemetry and
does not phone home. A running shift does launch the coding agent selected by
the owner (`claude` or `codex`), whose own network behaviour and policies still
apply. If the owner configures `notifyCommand`, Nightshift also executes that
command locally at the documented shift-ending or recovery-failure events; the
command may access the network because it is unrestricted owner-provided shell.

The primary Nightshift attack surface is therefore its local hook and runtime
scripts, the permissions granted to the coding agent, and any owner-configured
notification command.

## Reporting a vulnerability

Please **do not open a public issue** for security vulnerabilities.

The interesting risks here are of one kind: **a way to make the stop-gate
lie** — clocking out with unticked items, forging receipts, or escaping the
contract via hook manipulation. A stale recovery process bypassing the active
process lease to execute a local tool belongs in the same private channel.

Instead, report privately via GitHub's
[**Report a vulnerability**](https://github.com/orwa-mahmoud/nightshift/security/advisories/new)
flow (Security → Advisories). If that is unavailable, you can open a regular
issue asking the maintainer to contact you, without disclosing details.

A failed or interrupted *night* that is not a bypass — stalled watchman, wrong
workspace, revival that did not fire — belongs on a public
[Failed shift](https://github.com/orwa-mahmoud/nightshift/issues/new?template=failed_shift.yml)
report. That form asks for host/version and sanitized markers; it must not
include prompts, credentials, repository content, or a full transcript.

When reporting, please include:

- The Claude Code version and the plugin version.
- A minimal reproduction of the bypass.

You'll get a reply within a week. Please don't disclose gate-bypass reports
publicly until a fix ships.
