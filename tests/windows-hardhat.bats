load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/hardhat-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/windows/hardhat.ps1"
CORE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/shared/hardhat-core.sh"

WRAPPER="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/hardhat.sh"

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

@test "Windows toolDeny repairs name Setup like POSIX" {
  grep -qF '/nightshift:setup on Claude Code; ask Nightshift to set up on Codex' "$WRAPPER"
  grep -qF '/nightshift:setup on Claude Code; ask Nightshift to set up on Codex' "$CORE"
  grep -qF 'Fix .nightshift/rules.json or run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex).' "$HELPER"
  grep -qF 'run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex) to review the current template.' "$HELPER"
}

@test "Windows forbidden-command denials match POSIX wording" {
  grep -qF "the command matches the owner's forbidden list" "$CORE"
  grep -qF "the command matches the owner's forbidden list" "$HELPER"
  grep -qF 'parking-lot.md and keep working' "$CORE"
  grep -qF 'parking-lot.md and keep working' "$HELPER"
  grep -qF 'forbidden list' "$RUN"
  grep -qF 'forbidden list' "$LOGIC"
}

@test "Windows never-commit denials match POSIX wording" {
  grep -qF 'matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list.' "$CORE"
  grep -qF 'matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list.' "$HELPER"
  grep -qF 'never-commit pattern' "$RUN"
  grep -qF 'never-commit pattern' "$LOGIC"
}

@test "Windows protected-dir git-dir denials match POSIX wording" {
  grep -qF 'somewhere the protected-directory guard cannot verify' "$CORE"
  grep -qF 'somewhere the protected-directory guard cannot verify' "$HELPER"
  grep -qF 'protected-directory guard cannot verify' "$RUN"
  grep -qF 'protected-directory guard cannot verify' "$LOGIC"
}

@test "Windows invalid-pattern denials match POSIX wording" {
  grep -qF 'is not a valid extended regular expression, so the guard it configures cannot run' "$CORE"
  grep -qF 'is not a valid extended regular expression, so the guard it configures cannot run' "$HELPER"
  grep -qF 'NIGHTSHIFT_FORBIDDEN_COMMANDS is not a valid extended regular expression' "$HELPER"
  grep -qF 'NIGHTSHIFT_NEVER_COMMIT_PATTERNS is not a valid extended regular expression' "$HELPER"
  grep -qF 'Fix the pattern in your session settings.' "$CORE"
  grep -qF 'Fix the pattern in your session settings.' "$HELPER"
  grep -qF 'NIGHTSHIFT_FORBIDDEN_COMMANDS is not a valid extended regular expression' "$RUN"
  grep -qF 'NIGHTSHIFT_FORBIDDEN_COMMANDS is not a valid extended regular expression' "$LOGIC"
}
