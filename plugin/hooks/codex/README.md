# Codex hooks

The manifest at `../../.codex-plugin/plugin.json` points here, so Codex loads `hooks.json` in
this directory instead of `../hooks.json` — the two hosts never read each other's wiring.

`clock-out-gate.sh` and `hardhat.sh` make the same decisions as Claude's hooks, reading the
same punch list and the same `lib/lib.sh`. Everything Codex-specific — the stdin payload, the
block/deny shapes on stdout, how a hook finds the project — lives in `lib-io.sh`, the one
adaptation seam.

The wire format follows the documented Codex hooks contract
(<https://developers.openai.com/codex/hooks>): one JSON object on stdin carrying `session_id`,
`transcript_path`, `cwd`, `tool_name`, and `tool_input`; the Stop continuation as
`{"decision":"block","reason":…}` (Stop expects JSON on stdout even on exit 0, so a permitted
stop answers `{"continue":true}` rather than silence);
the PreToolUse denial as the `hookSpecificOutput` `permissionDecision` shape; `${PLUGIN_ROOT}`
as the plugin root in commands. Codex-side mapping: shell commands, including unified exec,
match as `Bash`; file edits arrive as `apply_patch` with the patch text in
`tool_input.command`, with `Edit`/`Write` as matcher-side aliases; hosted tools never reach
the hook path.

Two points the docs leave open are held conservatively in `lib-io.sh`: no project-dir env var
is documented for hooks, so the payload's `cwd` locates the shift and `CODEX_PROJECT_DIR` is
honored first as an explicit override; and no ask-the-user tool is documented, so the
`AskUserQuestion` wiring stays armed for any tool that carries the name.

No `.agents/plugins/marketplace.json` is published; Codex reads the repo-root
`.claude-plugin/marketplace.json` as a legacy-compatible marketplace.
