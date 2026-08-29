load ../helpers

ROOT="$BATS_TEST_DIRNAME/../../"
HOW="$ROOT/docs/how-it-works.md"
KNOBS="$ROOT/docs/knobs.md"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
README="$ROOT/README.md"
MARKET="$ROOT/.claude-plugin/marketplace.json"
CODEX_MARKET="$ROOT/.agents/plugins/marketplace.json"
CURSOR_MARKET="$ROOT/.cursor-plugin/marketplace.json"

@test "docs name the Cursor IDE and CLI store split" {
  grep -qF '~/.cursor/projects/' "$HOW"
  grep -qF 'agent-transcripts' "$HOW"
  grep -qF '~/.cursor/chats' "$HOW"
  grep -qF 'agent --resume' "$HOW"
  grep -qF 'Never pass the IDE id to `agent --resume`' "$KNOBS"
}

@test "docs forbid resuming an IDE conversation_id" {
  grep -qF 'never pass the IDE' "$HOW"
  grep -qF 'conversation_id' "$HOW"
  ! grep -qE 'agent --resume .*conversation_id' "$HOW" "$KNOBS" "$START"
}

@test "docs name the Cursor CLI file-hook limitation" {
  grep -qF 'currently ignores' "$HOW"
  grep -qF 'marketplace and local plugin hooks' "$HOW"
  grep -qF 'a Cursor limitation' "$HOW"
  grep -qF 'not a Nightshift skip' "$HOW"
}

@test "public install copy still waits on a verified Cursor shift" {
  ! grep -qE '^### Cursor' "$README"
  grep -qF 'marketplace listing waits' "$HOW"
  ! grep -qi cursor "$MARKET"
  ! grep -qi cursor "$CODEX_MARKET"
}

@test "the Cursor marketplace file points at the shipped plugin" {
  [ -f "$CURSOR_MARKET" ]
  [ "$(jq -r '.plugins[0].name' "$CURSOR_MARKET")" = "nightshift" ]
  [ "$(jq -r '.plugins[0].source' "$CURSOR_MARKET")" = "./plugins/nightshift" ]
  [ -f "$ROOT/plugins/nightshift/.cursor-plugin/plugin.json" ]
}

@test "Release Please bumps the Cursor host manifest with the others" {
  cfg="$ROOT/release-please-config.json"
  jq -e '.packages["."]."extra-files" | map(.path) | index("plugins/nightshift/.claude-plugin/plugin.json")' "$cfg" >/dev/null
  jq -e '.packages["."]."extra-files" | map(.path) | index("plugins/nightshift/.codex-plugin/plugin.json")' "$cfg" >/dev/null
  jq -e '.packages["."]."extra-files" | map(.path) | index("plugins/nightshift/.cursor-plugin/plugin.json")' "$cfg" >/dev/null
}
