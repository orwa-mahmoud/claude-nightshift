# Codex hooks

Empty on purpose. The manifest at `../../.codex-plugin/plugin.json` points here, so Codex loads
this file instead of `../hooks.json` — the two hosts never read each other's wiring.

The gate lands first: a `Stop` handler that refuses to end a session while `## Items` holds an
open box. It reads the same punch list and the same `lib/lib.sh` as Claude's; only the payload it
parses and the response it writes are Codex's.

Nothing here is advertised until that gate works — `.agents/plugins/marketplace.json` does not
exist yet, so a Codex user cannot install a plugin that would enforce nothing.
