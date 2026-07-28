# Security Policy

## Supported versions

Only the latest release is supported. The plugin runs entirely locally — no
network calls, no telemetry — so the attack surface is the hook scripts
themselves.

## Reporting a vulnerability

Please **do not open a public issue** for security vulnerabilities.

The interesting risks here are of one kind: **a way to make the stop-gate
lie** — clocking out with unticked items, forging receipts, or escaping the
contract via hook manipulation.

Instead, report privately via GitHub's
[**Report a vulnerability**](https://github.com/orwa-mahmoud/claude-nightshift/security/advisories/new)
flow (Security → Advisories). If that is unavailable, you can open a regular
issue asking the maintainer to contact you, without disclosing details.

When reporting, please include:

- The harness (Claude Code, or which agent CLI via `adapters/foreman.sh`) and plugin version.
- A minimal reproduction of the bypass.

You'll get a reply within a week. Please don't disclose gate-bypass reports
publicly until a fix ships.
