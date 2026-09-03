#!/usr/bin/env bats
# History context — skill writes the receipt. Wrapper removed.

ROOT="$BATS_TEST_DIRNAME/.."
ARCHIVE="$ROOT/plugins/nightshift/skills/archive/SKILL.md"
SETUP="$ROOT/plugins/nightshift/skills/setup/SKILL.md"
TEMPLATES="$ROOT/plugins/nightshift/skills/nightshift/references/receipt-templates.md"

@test "history-context python wrapper is gone" {
  [ ! -e "$ROOT/plugins/nightshift/runtime/history-context.sh" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/history-context.py" ]
}

@test "archive and setup write history from the template" {
  grep -qF 'Do not call `history-context.sh`' "$ARCHIVE"
  grep -qF 'history-context' "$SETUP"
  grep -qF 'Do not call' "$SETUP"
  grep -qF '# history-context / preset' "$TEMPLATES"
}
