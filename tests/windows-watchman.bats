load helpers

HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/watchman.ps1"
CLAUDE="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/claude/watchman.sh"
CODEX="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/codex/watchman.sh"

@test "Windows watchman unreadable-rules names Setup like POSIX" {
  grep -qF 'watchMinutes missing or not whole minutes' "$CLAUDE"
  grep -qF 'watchMinutes missing or not whole minutes' "$CODEX"
  grep -qF 'watchMinutes missing or not whole minutes' "$HELPER"
  grep -qF '.nightshift/rules.json absent or incomplete; run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex)' "$CLAUDE"
  grep -qF '.nightshift/rules.json absent or incomplete; run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex)' "$CODEX"
  grep -qF '.nightshift/rules.json absent or incomplete; run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex)' "$HELPER"
}

@test "Codex watchman sandbox comment names repository commits and artifact receipts" {
  grep -qF 'one commit per item IS the contract in repository mode' "$CODEX"
  grep -qF 'Artifact mode writes a receipt instead' "$CODEX"
  grep -qF '.git/index.lock' "$CODEX"
  grep -qF 'danger-full-access' "$CODEX"
}
