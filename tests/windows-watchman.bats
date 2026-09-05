load helpers

HELPER="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/watchman.ps1"
CLAUDE="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/claude/watchman.sh"
CODEX="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/codex/watchman.sh"
OWNERSHIP="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/ownership.sh"
PSM1="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/Nightshift.psm1"

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

@test "watchmen skip a symlink deadline" {
  grep -qF '[ -L "$NS/deadline" ]' "$CLAUDE"
  grep -qF '[ ! -L "$NS/deadline" ]' "$CODEX"
  awk '/function Test-NSDeadlinePassed/,/^function Test-NSRealEnded/' "$HELPER" | grep -qF 'Test-NSReparsePoint $path'
}

@test "watchmen skip a symlink ended marker" {
  grep -qF '[ ! -L "$NS/.ended" ]' "$CLAUDE"
  grep -qF '[ ! -L "$NS/.ended" ]' "$CODEX"
  grep -qF 'function Test-NSRealEnded' "$HELPER"
}

@test "watchmen skip a symlink session-end marker" {
  grep -qF '[ ! -L "$NS/.session-end" ]' "$CLAUDE"
  grep -qF '[ ! -L "$NS/.session-end" ]' "$CODEX"
  grep -qF 'function Test-NSRealSessionEnd' "$HELPER"
}

@test "watchmen skip a symlink shift-session" {
  grep -qF '[ -L "$NS/.shift-session" ]' "$CLAUDE"
  grep -qF '[ -L "$NS/.shift-session" ]' "$CODEX"
  grep -qF 'ns_session_line' "$OWNERSHIP"
  grep -qF 'ns_session_present' "$OWNERSHIP"
  grep -qF '[ ! -L "$rec" ]' "$OWNERSHIP"
  grep -qF '[ -L "$ns/.shift-session" ]' "$OWNERSHIP"
  awk '/function Read-NSSession/,/^function Write-NSSession/' "$PSM1" | grep -qF 'Test-NSReparsePoint $path'
  awk '/function Claim-NSSession/,/^function Read-NSSession/' "$PSM1" | grep -qF 'Test-NSReparsePoint $path'
  awk '/function Write-NSSession/,/^function Read-NSLease/' "$PSM1" | grep -qF 'Test-NSReparsePoint $path'
}

@test "watchmen skip a symlink watchman pidfile" {
  grep -qF '[ -L "$PIDFILE" ]' "$CLAUDE"
  grep -qF '[ -L "$PIDFILE" ]' "$CODEX"
  grep -qF 'Test-NSReparsePoint $pidFile' "$HELPER"
}

@test "watchmen bound terminal clock-out to one attempt" {
  grep -qF 'clock-out attempt 1/1' "$CLAUDE"
  grep -qF 'clock-out attempt 1/1' "$CODEX"
  grep -qF 'clock-out attempt 1/1' "$HELPER"
  grep -qF 'note clock-out-failed' "$CLAUDE"
  grep -qF 'note clock-out-failed' "$CODEX"
  grep -qF "Write-NSReason \$ns 'clock-out-failed'" "$HELPER"
  grep -qF 'ns_lease_restore_interactive' "$OWNERSHIP"
  grep -qF 'function Restore-NSLeaseInteractive' "$PSM1"
  grep -qF 'Restore-NSLeaseInteractive $ns' "$HELPER"
  grep -qF 'Release-NSLease $ns' "$HELPER"
  grep -qF 'ns_lease_release' "$OWNERSHIP"
  if grep -q 'retrying next wake' "$CLAUDE"; then
    return 1
  fi
  if grep -q 'retrying next wake' "$CODEX"; then
    return 1
  fi
}
