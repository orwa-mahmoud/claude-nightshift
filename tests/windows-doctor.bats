load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/doctor-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/doctor.ps1"

@test "Windows CI runs the portable Doctor leftover and staged-work suite" {
  [ -f "$LOGIC" ]
  grep -qF 'doctor-logic.ps1' "$RUN"
  grep -qF 'leftover Shift contract and Gates' "$LOGIC"
  grep -qF 'staged drafting-table items=' "$LOGIC"
  grep -qF 'pending Hunt work orders=1' "$LOGIC"
  grep -qF 'STOP leftover' "$LOGIC"
  grep -qF 'leftover Shift contract and Gates still bind the next Hunt or Start cut' "$HELPER"
  grep -qF 'deadline=none' "$HELPER"
  grep -qF 'Get-NSUnixTime' "$HELPER"
  grep -qF 'artifact receipts' "$HELPER"
  grep -qF 'Get-NSReceiptsCount' "$HELPER"
  grep -qF 'Get-NSLatestReceipt' "$HELPER"
  grep -qF 'latest artifact receipt' "$HELPER"
  grep -qF 'deadline is not a UNIX epoch' "$HELPER"
  grep -qF 'Test-NSRecordedProcess $spid $sstart' "$HELPER"
  grep -qF 'Test-NSRecordedProcess $wpid $wstart' "$HELPER"
  grep -qF 'watchRetrySeconds is empty' "$HELPER"
  grep -qF 'revivalPrompt is empty' "$HELPER"
  grep -qF 'freshRevivalPrompt is empty' "$HELPER"
  grep -qF 'revivalPrompt is empty' "$LOGIC"
}

@test "Windows Doctor leftover and staged-work logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
