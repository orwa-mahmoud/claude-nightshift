load helpers

@test "blocks while a box is open" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
}

@test "releases when every box is ticked" {
  p="$(new_project)"
  punch_done "$p"
  run gate "$p"
  [ -z "$output" ]
}

@test "releases when there is no punch list" {
  p="$(new_project)"
  run gate "$p"
  [ -z "$output" ]
}

@test "stop-work order releases even with open boxes" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run gate "$p"
  [ -z "$output" ]
}

@test "quitting time releases, writes STOP and a shift-log line" {
  p="$(new_project)"
  punch_open "$p"
  echo $(($(date +%s) - 60)) >"$p/.nightshift/deadline"
  run gate "$p"
  [ -z "$output" ]
  [ -f "$p/.nightshift/STOP" ]
  grep -q 'quitting time' "$p/.nightshift/shift-log.md"
}

@test "stall red-tag ends the shift after N no-progress stop attempts" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
  run gate "$p"
  is_block "$output"
  run gate "$p"
  [ -z "$output" ]
  [ -f "$p/.nightshift/STOP" ]
  grep -q 'stalled' "$p/.nightshift/shift-log.md"
}

@test "a ticked box resets the stall counter" {
  p="$(new_project)"
  printf '## Items\n- [ ] **1.**\n- [ ] **2.**\n' >"$p/.nightshift/punch-list.md"
  run gate "$p"
  run gate "$p"
  printf '## Items\n- [x] **1.**\n- [ ] **2.**\n' >"$p/.nightshift/punch-list.md"
  run gate "$p"
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "1" ]
}

@test "a commit resets the stall counter" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  run gate "$p"
  git -C "$p" commit -q --allow-empty -m progress
  run gate "$p"
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "1" ]
}

@test "morning whistle fires once with a summary on a shift-ending release" {
  p="$(new_project)"
  punch_done "$p"
  wl="$BATS_TEST_TMPDIR/whistle.log"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  [ "$(wc -l <"$wl" | tr -d ' ')" -eq 1 ]
  grep -q 'shift done: 2/2' "$wl"
}

@test "morning whistle is a silent no-op when unset" {
  p="$(new_project)"
  punch_done "$p"
  run gate "$p"
  [ -z "$output" ]
  [ ! -f "$p/.nightshift/.notified" ]
}

@test "morning whistle fires on a stall red-tag release" {
  p="$(new_project)"
  punch_open "$p"
  wl="$BATS_TEST_TMPDIR/w.log"
  nc="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  [ -z "$output" ]
  grep -q 'stalled' "$wl"
  [ "$(wc -l <"$wl" | tr -d ' ')" -eq 1 ]
}

@test "morning whistle fires on a stop-work release" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  wl="$BATS_TEST_TMPDIR/w.log"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  [ -z "$output" ]
  grep -q 'shift ended' "$wl"
}
