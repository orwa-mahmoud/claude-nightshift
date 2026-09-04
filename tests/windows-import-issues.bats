load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/import-issues-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/import-issues.ps1"

@test "Windows CI runs the portable import-issues list/promote suite" {
  [ -f "$LOGIC" ]
  grep -qF 'import-issues-logic.ps1' "$RUN"
  grep -qF -- '-ListProposed' "$LOGIC"
  grep -qF -- '-Promote' "$LOGIC"
  grep -qF 'Review flags: destructive' "$LOGIC"
  grep -qF 'PositionalBinding = $false' "$HELPER"
  grep -qF '[IO.FileAttributes]::ReparsePoint' "$HELPER"
  if grep -qF -- '-Recurse' "$HELPER"; then
    return 1
  fi
}

@test "Windows import-issues usage errors name native flags" {
  grep -qF -- '-Repo requires' "$HELPER"
  grep -qF -- '-AuthorizedRepo must be' "$HELPER"
  grep -qF -- '-AllowClosed' "$HELPER"
  if grep -qF 'import-issues: --repo' "$HELPER"; then
    return 1
  fi
  if grep -qF '--authorized-repo' "$HELPER"; then
    return 1
  fi
  if grep -qF '--allow-closed' "$HELPER"; then
    return 1
  fi
  grep -qF 'gh issue view' "$HELPER"
}

@test "Windows import-issues list/promote logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
