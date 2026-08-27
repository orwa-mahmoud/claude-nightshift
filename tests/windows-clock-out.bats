load helpers

HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/windows/clock-out-gate.ps1"
CORE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/clock-out-gate.sh"
CODEX="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/codex/clock-out-gate.sh"

@test "Windows unreadable-rules clock-out names Setup like POSIX" {
  grep -qF '/nightshift:setup' "$CORE"
  grep -qF 'ask Nightshift to set up on Codex' "$CORE"
  grep -qF '.nightshift/rules.json' "$CORE"
  grep -qF '/nightshift:setup' "$HELPER"
  grep -qF 'ask Nightshift to set up on Codex' "$HELPER"
  grep -qF '.nightshift/rules.json clockOutMessage' "$HELPER"
  grep -qF 'stallMax/stallWarnEvery unreadable (.nightshift/rules.json absent or incomplete)' "$HELPER"
}

@test "Windows clock-out receipts commits match POSIX headless identity" {
  grep -qF 'user.email=nightshift@localhost' "$CORE"
  grep -qF 'commit.gpgsign=false' "$CORE"
  grep -qF 'user.email=nightshift@localhost' "$CODEX"
  grep -qF 'commit.gpgsign=false' "$CODEX"
  grep -qF 'user.email=nightshift@localhost' "$HELPER"
  grep -qF 'commit.gpgsign=false' "$HELPER"
}
