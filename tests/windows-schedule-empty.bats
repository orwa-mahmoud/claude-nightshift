load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/schedule-empty-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/schedule.ps1"

@test "Windows CI runs the portable Schedule empty-list parked-work suite" {
  [ -f "$LOGIC" ]
  grep -qF 'schedule-empty-logic.ps1' "$RUN"
  grep -qF 'NOTE 1 parked Hunt work order' "$LOGIC"
  grep -qF 'Parked Hunt work orders: 1' "$LOGIC"
  grep -qF 'Drafting-table items: 1' "$LOGIC"
  grep -qF 'Note: the punch list has no open items' "$HELPER"
  grep -qF '/nightshift:setup on Claude Code; ask Nightshift to set up on Codex' "$HELPER"
}

@test "Windows Schedule empty-list parked-work logic passes when Task Scheduler identity is available" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  # Task Scheduler XML names [WindowsIdentity]::GetCurrent(); macOS pwsh cannot.
  if ! pwsh -NoProfile -NonInteractive -Command \
    'try { $null = [Security.Principal.WindowsIdentity]::GetCurrent().Name; exit 0 } catch { exit 1 }'
  then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
