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
  is_release
}

@test "releases when there is no punch list" {
  p="$(new_project)"
  run gate "$p"
  is_release
}

@test "stop-work order releases even with open boxes" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run gate "$p"
  is_release
}

@test "quitting time releases, writes STOP and a shift-log line" {
  p="$(new_project)"
  punch_open "$p"
  echo $(($(date +%s) - 60)) >"$p/.nightshift/deadline"
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/STOP" ]
  grep -q 'quitting time' "$p/.nightshift/shift-log.md"
}

# The done and stop-work releases assert their receipts and whistle below; quitting time and the
# stall opt-in are shift-ending too, and shipped without the same proof.
@test "quitting time leaves receipts, a whistle and the ended marker" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  wl="$BATS_TEST_TMPDIR/qt.log"
  echo $(($(date +%s) - 60)) >"$p/.nightshift/deadline"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  is_release
  [ -f "$p/.nightshift/.ended" ]
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 2 ]
  grep -q 'quitting time' "$wl"
}

@test "the stall auto-end leaves receipts, a whistle and the ended marker" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  wl="$BATS_TEST_TMPDIR/st.log"
  nc="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc" NIGHTSHIFT_STALL_MAX=2
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc" NIGHTSHIFT_STALL_MAX=2
  is_release
  [ -f "$p/.nightshift/.ended" ]
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 2 ]
  grep -q 'stalled' "$wl"
}

@test "a held shift is not an ended one" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
  [ ! -f "$p/.nightshift/.ended" ]
}

# The deadline accepts an epoch or an ISO timestamp. The ISO branch resolves through GNU `date -d`
# or BSD `date -j -f` — one of the two is always the fallback, so these pin both platforms.

@test "an ISO deadline in the past releases the shift" {
  p="$(new_project)"
  punch_open "$p"
  printf '2020-01-01T00:00:00\n' >"$p/.nightshift/deadline"
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/STOP" ]
  grep -q 'quitting time' "$p/.nightshift/shift-log.md"
}

@test "an ISO deadline in the future keeps the shift open" {
  p="$(new_project)"
  punch_open "$p"
  printf '2999-01-01T00:00:00\n' >"$p/.nightshift/deadline"
  run gate "$p"
  is_block "$output"
  [ ! -f "$p/.nightshift/STOP" ]
}

@test "an unparseable deadline never ends the shift by accident" {
  p="$(new_project)"
  punch_open "$p"
  printf 'not-a-date\n' >"$p/.nightshift/deadline"
  run gate "$p"
  is_block "$output"
  [ ! -f "$p/.nightshift/STOP" ]
}

@test "a stalled shift is held by default: block stands, no STOP, warning logged" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  run gate "$p"
  run gate "$p"
  is_block "$output"
  [ ! -f "$p/.nightshift/STOP" ]
  grep -q 'stall warning' "$p/.nightshift/shift-log.md"
}

@test "the hold-mode warning repeats every third stuck attempt" {
  p="$(new_project)"
  punch_open "$p"
  for _ in 1 2 3 4 5 6; do run gate "$p"; done
  is_block "$output"
  [ ! -f "$p/.nightshift/STOP" ]
  [ "$(grep -c 'stall warning' "$p/.nightshift/shift-log.md")" -eq 2 ]
}

@test "the stall opt-in ends the shift after N no-progress stop attempts" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p" NIGHTSHIFT_STALL_MAX=3
  is_block "$output"
  run gate "$p" NIGHTSHIFT_STALL_MAX=3
  is_block "$output"
  run gate "$p" NIGHTSHIFT_STALL_MAX=3
  is_release
  grep -q 'stalled' "$p/.nightshift/STOP"
  grep -q 'stalled — auto-ended' "$p/.nightshift/shift-log.md"
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

@test "workspace layout: a commit in the repo below still counts as progress" {
  w="$(new_workspace)"
  punch_open "$w"
  run gate "$w"
  run gate "$w"
  git -C "$w/repo" commit -q --allow-empty -m progress
  run gate "$w"
  is_block "$output"
  [ "$(sed -n '2p' "$w/.nightshift/.stall")" = "1" ]
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
  is_release
  [ ! -f "$p/.nightshift/.notified" ]
}

@test "morning whistle fires on an opted-in stall release" {
  p="$(new_project)"
  punch_open "$p"
  wl="$BATS_TEST_TMPDIR/w.log"
  nc="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc" NIGHTSHIFT_STALL_MAX=3
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc" NIGHTSHIFT_STALL_MAX=3
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc" NIGHTSHIFT_STALL_MAX=3
  is_release
  grep -q 'stalled' "$wl"
  [ "$(wc -l <"$wl" | tr -d ' ')" -eq 1 ]
}

@test "hold mode never fires the whistle" {
  p="$(new_project)"
  punch_open "$p"
  wl="$BATS_TEST_TMPDIR/held.log"
  nc="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="$nc"
  is_block "$output"
  [ ! -f "$wl" ]
}

@test "morning whistle fires on a stop-work release" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  wl="$BATS_TEST_TMPDIR/w.log"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  is_release
  grep -q 'shift ended' "$wl"
}

@test "a done release commits the receipts repo when one exists" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  punch_done "$p"
  run gate "$p"
  is_release
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 2 ]
  git -C "$p/.nightshift" log -1 --format=%s | grep -q 'shift done: 2/2'
}

@test "a stop-work release snapshots the receipts repo" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  printf 'stopped by owner\n' >"$p/.nightshift/STOP"
  printf 'parked: pick the DB\n' >"$p/.nightshift/parking-lot.md"
  run gate "$p"
  is_release
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 2 ]
}

@test "the stop reason keeps its spacing in the whistle summary" {
  p="$(new_project)"
  punch_open "$p"
  printf 'stopped by owner · 2026-07-19T02:40:00\n' >"$p/.nightshift/STOP"
  wl="$BATS_TEST_TMPDIR/w.log"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  is_release
  grep -q 'stopped by owner' "$wl"
}

@test "the gate records the shift session while blocking" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "test-shift-session" ]
}
