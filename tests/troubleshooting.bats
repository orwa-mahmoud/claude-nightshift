README="$BATS_TEST_DIRNAME/../README.md"
DOC="$BATS_TEST_DIRNAME/../docs/troubleshooting.md"
COMMANDS="$BATS_TEST_DIRNAME/../docs/commands.md"
CHECKLIST="$BATS_TEST_DIRNAME/../docs/first-night-checklist.md"
HOW="$BATS_TEST_DIRNAME/../docs/how-it-works.md"
KNOBS="$BATS_TEST_DIRNAME/../docs/knobs.md"

@test "README and command docs link the troubleshooting tree" {
  grep -qF '[**Troubleshooting**](docs/troubleshooting.md)' "$README"
  grep -qF '[Troubleshooting](troubleshooting.md)' "$COMMANDS"
  grep -qF '[Troubleshooting](troubleshooting.md)' "$CHECKLIST"
}

@test "troubleshooting covers the decision branches against live paths" {
  for phrase in 'Where is the site?' 'Unsupported or malformed `state-version`' \
    'Invalid `.nightshift-link`' 'Wrong workspace' \
    'Unreadable rules' 'STOP vs stale arming' 'Missing session identity' \
    'Watchman stood down'; do
    grep -qF "$phrase" "$DOC" || { echo "missing branch: $phrase"; return 1; }
  done
  grep -qF 'migrate-state.sh' "$DOC"
  grep -qF 'link-workspace.sh' "$DOC"
  grep -qF '.nightshift-link' "$DOC"
  grep -qF 'work-target' "$DOC"
  grep -qF 'rules.json' "$DOC"
  grep -qF 'touch .nightshift/STOP' "$DOC"
  grep -qF '.shift-armed' "$DOC"
  grep -qF '.shift-session' "$DOC"
  grep -qF 'watchMinutes' "$DOC"
  grep -qF 'leftover Shift contract' "$DOC"
  grep -qF 'leftover Shift contract' "$HOW"
}

@test "troubleshooting marks checks before repairs and splits the hosts" {
  grep -qF 'Read-only checks first' "$DOC"
  grep -qF '**Check.**' "$DOC"
  grep -qF '**Repair.**' "$DOC"
  grep -qF 'Claude Code' "$DOC"
  grep -qF 'Codex' "$DOC"
  grep -qF 'alive but errored is stood by' "$DOC"
  grep -qF 'owner pressed Esc — standing by' "$DOC"
  grep -qF 'shift is owned by' "$DOC"
}

@test "troubleshooting links resolve" {
  [ -f "$BATS_TEST_DIRNAME/../docs/knobs.md" ]
  [ -f "$BATS_TEST_DIRNAME/../docs/commands.md" ]
  [ -f "$BATS_TEST_DIRNAME/../docs/first-night-checklist.md" ]
  [ -f "$BATS_TEST_DIRNAME/../SECURITY.md" ]
  [ -f "$BATS_TEST_DIRNAME/../.github/ISSUE_TEMPLATE/failed_shift.yml" ]
  grep -qF 'issues/new?template=failed_shift.yml' "$DOC"
  grep -qF '/workspace/scratch/' "$DOC"
}

@test "recovery docs separate unattended work from the manual UI refresh" {
  grep -qF 'owner does not need to watch it' "$README"
  grep -qF 'needs no owner monitoring' "$HOW"
  grep -qF 'owner does not need to watch the recovery' "$DOC"
  grep -qF 'without being watched' "$CHECKLIST"
  grep -qF 'does not require an owner to monitor it' "$KNOBS"

  for issue in 82655 28259 21743; do
    grep -q "/issues/$issue" "$README"
    grep -q "/issues/$issue" "$HOW"
    grep -q "/issues/$issue" "$DOC"
  done
  grep -qF 'not merely interface polish' "$HOW"
}
