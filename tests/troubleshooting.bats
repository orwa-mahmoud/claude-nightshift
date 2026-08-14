README="$BATS_TEST_DIRNAME/../README.md"
DOC="$BATS_TEST_DIRNAME/../docs/troubleshooting.md"
COMMANDS="$BATS_TEST_DIRNAME/../docs/commands.md"
CHECKLIST="$BATS_TEST_DIRNAME/../docs/first-night-checklist.md"

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

@test "troubleshooting does not replace the README contract" {
  ! grep -qi 'Keep long coding runs on task' "$DOC"
  wc -l <"$DOC" | awk '{ exit ($1 > 220) ? 1 : 0 }'
}
