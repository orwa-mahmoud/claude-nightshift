load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/hardhat-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/windows/hardhat.ps1"
CORE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/shared/hardhat-core.sh"

@test "Windows expected-email denials match POSIX wording" {
  grep -qF "committer identity ('" "$CORE"
  grep -qF "committer identity ('" "$HELPER"
  grep -qF 'Fix git config user.email, then retry.' "$CORE"
  grep -qF 'Fix git config user.email, then retry.' "$HELPER"
  grep -qF "repository's configured identity" "$CORE"
  grep -qF "repository's configured identity" "$HELPER"
}

@test "Windows CI runs the portable hardhat expected-email suite" {
  [ -f "$LOGIC" ]
  grep -qF 'hardhat-logic.ps1' "$RUN"
  grep -qF 'NIGHTSHIFT_EXPECTED_EMAIL' "$RUN"
  grep -qF 'committer identity' "$LOGIC"
  grep -qF "repository's configured identity" "$LOGIC"
}

@test "Windows hardhat expected-email logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
