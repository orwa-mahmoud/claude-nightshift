README="$BATS_TEST_DIRNAME/../README.md"
CHECKLIST="$BATS_TEST_DIRNAME/../docs/first-night-checklist.md"

@test "README links the first-night checklist beside first-shift setup" {
  grep -qF '[first-night safety checklist](docs/first-night-checklist.md)' "$README"
}

@test "first-night checklist covers unattended safety boundaries" {
  for phrase in 'Start attended' 'Choose permissions deliberately' 'Prove STOP' \
    'Decide how stalls should end' 'Test notifications' 'Know the host boundary'; do
    grep -qF "$phrase" "$CHECKLIST"
  done
  grep -qF 'touch .nightshift/STOP' "$CHECKLIST"
  grep -qF 'Claude Code' "$CHECKLIST"
  grep -qF 'Codex' "$CHECKLIST"
  grep -qF 'Hunt or Quality that start immediately' "$CHECKLIST"
  grep -qF 'native Windows' "$CHECKLIST"
  grep -qF 'PID plus UTC start time' "$CHECKLIST"
  grep -qF 'runtime/write-receipt.sh' "$CHECKLIST"
  grep -qF 'runtime/windows/write-receipt.ps1' "$CHECKLIST"
  grep -qF 'reviewable commit' "$CHECKLIST"
  grep -qF '$NS/receipts/' "$CHECKLIST"
}

@test "first-night checklist relative links resolve" {
  [ -f "$BATS_TEST_DIRNAME/../docs/knobs.md" ]
  [ -f "$BATS_TEST_DIRNAME/../docs/commands.md" ]
  [ -f "$BATS_TEST_DIRNAME/../docs/shift-modes.md" ]
  grep -qF '[Shift modes](shift-modes.md)' "$CHECKLIST"
}

@test "first-run overnight guidance names persistent folders" {
  grep -qF 'persistent folder' "$README"
  grep -qF 'persistent local folder' "$README"
  grep -qF 'ChatGPT scratch' "$README"
  grep -qF 'artifact receipt (notes folder)' "$README"
  grep -qF '$NS/receipts/' "$README"
  how="$BATS_TEST_DIRNAME/../docs/how-it-works.md"
  grep -qF 'First run attended' "$how"
  grep -qF 'persistent folder' "$how"
  grep -qF 'artifact receipt' "$how"
  grep -qF 'ChatGPT scratch' "$how"
}
