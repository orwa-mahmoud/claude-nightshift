load ../helpers

ROOT="$BATS_TEST_DIRNAME/../../"
HOW="$ROOT/docs/how-it-works.md"
KNOBS="$ROOT/docs/knobs.md"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"

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
