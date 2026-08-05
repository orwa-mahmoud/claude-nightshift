load helpers

SCHED="$BATS_TEST_DIRNAME/../plugin/runtime/claude/schedule.sh"

setup() {
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.nightshift"
  printf '## Items\n- [ ] **1. real work.**\n' >"$P/.nightshift/punch-list.md"
}

@test "refuses a project with no .nightshift" {
  run "$SCHED" --project "$BATS_TEST_TMPDIR" --at 04:05
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'nightshift:setup'
}

@test "an option with no value exits instead of spinning" {
  run "$SCHED" --at
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q -- '--at needs a value'
}

# A bad time silently accepted becomes a job that never fires, discovered a week later.
@test "a time that is not 24-hour HH:MM is rejected" {
  for t in 25:00 7:30 04:60 "4am" ""; do
    run "$SCHED" --project "$P" --at "$t"
    [ "$status" -eq 1 ] || { echo "accepted bad time: $t"; return 1; }
  done
}

@test "prints config and an install command for a real time" {
  run "$SCHED" --project "$P" --at 04:05
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '04:05'
  printf '%s' "$output" | grep -qE 'launchctl load|crontab'
  printf '%s' "$output" | grep -q "/nightshift:start"
}

# The generator hands over config; installing is the owner's own command, always.
@test "it registers nothing itself" {
  run "$SCHED" --project "$P" --at 04:05
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/LaunchAgents/com.nightshift.proj"*.plist ] || {
    echo "schedule.sh installed a plist by itself"; return 1; }
}

# A scheduled start works the list it finds and promotes nothing, so an empty list is a run that
# does nothing at all — worth saying before the owner walks away.
@test "warns when the punch list it would work is empty" {
  printf '## Items\n' >"$P/.nightshift/punch-list.md"
  run "$SCHED" --project "$P" --at 04:05
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi 'no open items'
}

@test "list and remove are quiet when nothing is registered" {
  run "$SCHED" --project "$P" --list
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi 'nothing registered'
  run "$SCHED" --project "$P" --remove
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi 'nothing registered'
}

# Two scheduled starts on one punch list is two agents on one shift — the failure the shift's own
# one-session rule prevents from the inside, arriving from outside it.
@test "a project already registered is refused a second entry" {
  fake="$BATS_TEST_TMPDIR/fakecron"
  cat >"$BATS_TEST_TMPDIR/bin_crontab" <<STUB
#!/usr/bin/env bash
[ "\$1" = "-l" ] && cat "$fake" 2>/dev/null
exit 0
STUB
  mkdir -p "$BATS_TEST_TMPDIR/bin" && mv "$BATS_TEST_TMPDIR/bin_crontab" "$BATS_TEST_TMPDIR/bin/crontab"
  chmod +x "$BATS_TEST_TMPDIR/bin/crontab"
  # capture the marker this project would use, then pretend it is already installed
  run "$SCHED" --project "$P" --at 04:05
  marker="$(printf '%s' "$output" | grep -o '# nightshift:[A-Za-z0-9-]*' | head -1)"
  if [ -n "$marker" ]; then                 # cron platform
    printf '5 4 * * * true  %s\n' "$marker" >"$fake"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$SCHED" --project "$P" --at 04:05
    [ "$status" -eq 3 ]
    printf '%s' "$output" | grep -qi 'already registered'
  else                                       # macOS platform
    plist="$(printf '%s' "$output" | grep -o "$HOME/Library/LaunchAgents/com.nightshift.[^ ]*\.plist" | head -1)"
    [ -n "$plist" ]
    touch "$plist"
    run "$SCHED" --project "$P" --at 04:05
    rm -f "$plist"
    [ "$status" -eq 3 ]
    printf '%s' "$output" | grep -qi 'already registered'
  fi
}

# Two checkouts named the same must not share an identity, or one silently blocks the other.
@test "two projects with the same folder name get different ids" {
  a="$BATS_TEST_TMPDIR/a/api"; b="$BATS_TEST_TMPDIR/b/api"
  for d in "$a" "$b"; do
    mkdir -p "$d/.nightshift"
    printf '## Items\n- [ ] **1. work.**\n' >"$d/.nightshift/punch-list.md"
  done
  ida="$("$SCHED" --project "$a" --at 04:05 | grep -o 'com.nightshift.[A-Za-z0-9-]*\|# nightshift:[A-Za-z0-9-]*' | head -1)"
  idb="$("$SCHED" --project "$b" --at 04:05 | grep -o 'com.nightshift.[A-Za-z0-9-]*\|# nightshift:[A-Za-z0-9-]*' | head -1)"
  [ -n "$ida" ] && [ -n "$idb" ] && [ "$ida" != "$idb" ]
}

# The skill is the pleasant path; the script is the one that still works at 100% usage. Both must
# exist, and the skill must do the checks an owner would otherwise fail at 4am.
@test "the schedule skill checks the work is queued before printing config" {
  s="$BATS_TEST_DIRNAME/../plugin/skills/schedule/SKILL.md"
  [ -f "$s" ]
  grep -qi 'promotes nothing' "$s"           # an empty list is a run that does nothing
  grep -qi 'nightshift:hunt' "$s"            # and how to fix that
  grep -qi 'cannot answer a prompt' "$s"     # headless permissions
  grep -qi 'nightshift:stop' "$s"            # queuing arms the gate on this session
  grep -qi 'install nothing' "$s"            # generator, never a daemon
}

# A README is reachable with no credit; a skill is not. The offline path has to be documented
# where an owner can still read it on the day they need it.
@test "the README documents the offline generator for a session that cannot run" {
  r="$BATS_TEST_DIRNAME/../docs/commands.md"
  grep -qi 'no credit left' "$r"
  grep -qi 'spends no tokens and needs no session' "$r"
  grep -q 'plugin/runtime/claude/schedule.sh --project . --at' "$r"
}

# One generator serves both hosts: the entry's runner is a parameter, defaulting to Claude's.
@test "--agent swaps the headless runner in the generated entry" {
  p="$BATS_TEST_TMPDIR/proj"; mkdir -p "$p/.nightshift"
  run "$SCHED" --project "$p" --at 04:05 --agent "codex exec -s danger-full-access"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF "codex exec -s danger-full-access '/nightshift:start'"
  ! printf '%s' "$output" | grep -qF "claude -p" || false
}

@test "the default runner stays claude -p" {
  p="$BATS_TEST_TMPDIR/proj2"; mkdir -p "$p/.nightshift"
  run "$SCHED" --project "$p" --at 04:05
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF "claude -p '/nightshift:start'"
}
