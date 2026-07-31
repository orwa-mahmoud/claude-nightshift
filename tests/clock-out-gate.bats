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
  [ "$(wc -l <"$p/.nightshift/.shift-session")" -eq 4 ] # id, transcript, pid, start time
}

# ---- the shift binds one session: everyone else stops freely ----

@test "another conversation's stop is not the shift's business — released" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\n' >"$p/.nightshift/.shift-session"
  run gate "$p" # this stop arrives as test-shift-session, not the-shift
  is_release
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "the-shift" ] # record untouched
  [ ! -f "$p/.nightshift/.ended" ] # and nothing was ended on the stranger's way out
}

@test "the recorded shift session itself is still held" {
  p="$(new_project)"
  punch_open "$p"
  printf 'test-shift-session\n\n\n\n' >"$p/.nightshift/.shift-session"
  run gate "$p"
  is_block "$output"
}

# The fresh-session fallback gives a revival a NEW id; the mark keeps it bound, and it
# re-claims the record so the watchman follows the living thread.
@test "a marked revival inherits the binding under a new id and re-claims the record" {
  p="$(new_project)"
  punch_open "$p"
  printf 'dead-old-id\n\n\n\n' >"$p/.nightshift/.shift-session"
  run gate "$p" NIGHTSHIFT_REVIVAL=1
  is_block "$output"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "test-shift-session" ]
}

# ---- the site lock: two sessions may stop at once; the bookkeeping must not tear ----

@test "a stale lock from a dead process never blocks the gate" {
  p="$(new_project)"
  punch_open "$p"
  bash -c ':' &
  deadpid=$!
  wait "$deadpid" 2>/dev/null || true
  mkdir "$p/.nightshift/.lock.d"
  printf '%s' "$deadpid" >"$p/.nightshift/.lock.d/pid"
  run gate "$p"
  is_block "$output"
  [ ! -d "$p/.nightshift/.lock.d" ] # broken, taken, released
}

@test "a live foreign lock delays but never hangs the gate — and is never stolen" {
  p="$(new_project)"
  punch_open "$p"
  mkdir "$p/.nightshift/.lock.d"
  printf '%s' "$$" >"$p/.nightshift/.lock.d/pid"
  run gate "$p"
  is_block "$output"
  [ "$(cat "$p/.nightshift/.lock.d/pid")" = "$$" ] # still the foreign holder's
}

# The torn read this lock exists for: both racers read the same counter, both warn, both write
# zero. Serialized, exactly one warns and the counter lands where a sequence of two honest stop
# attempts leaves it.
@test "two racing stop attempts warn the stall exactly once" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p" # let the gate write the real fingerprint
  fp="$(sed -n 1p "$p/.nightshift/.stall")"
  printf '%s\n2\n' "$fp" >"$p/.nightshift/.stall"
  jq -nc '{hook_event_name:"Stop",session_id:"test-shift-session",transcript_path:""}' |
    env CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/clock-out-gate.sh" >/dev/null &
  g1=$!
  jq -nc '{hook_event_name:"Stop",session_id:"test-shift-session",transcript_path:""}' |
    env CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/clock-out-gate.sh" >/dev/null &
  g2=$!
  wait "$g1" "$g2" 2>/dev/null || true
  [ "$(grep -c 'stall warning' "$p/.nightshift/shift-log.md")" -eq 1 ]
  [ "$(sed -n 2p "$p/.nightshift/.stall")" = "1" ]
}

# The reinjected contract is the owner's to word — jq builds the JSON so their text cannot
# break the decision.
@test "the clock-out reinjection is the owner's to word" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p" NIGHTSHIFT_GATE_MESSAGE="back to the bench — boxes are open"
  is_block "$output"
  printf '%s' "$output" | grep -q "back to the bench"
}

@test "the stall warning cadence is the owner's (rules file: stallWarnEvery)" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p" NIGHTSHIFT_STALL_WARN=2
  run gate "$p" NIGHTSHIFT_STALL_WARN=2
  is_block "$output"
  grep -q 'stall warning — 2 attempts' "$p/.nightshift/shift-log.md"
}

@test "the gate reads the stall cadence from the rules file" {
  p="$(new_project)"
  punch_open "$p"
  jq '.stallWarnEvery = 2' "$RULES_TEMPLATE" >"$p/.nightshift/rules.json"
  run gate "$p"
  run gate "$p"
  is_block "$output"
  grep -q 'stall warning — 2 attempts' "$p/.nightshift/shift-log.md"
}

# The block never depends on config: unreadable knobs still gate, fail closed, repair named.
@test "a missing rules file still blocks and names the repair" {
  p="$(new_project)"
  punch_open "$p"
  rm "$p/.nightshift/rules.json"
  run gate "$p"
  is_block "$output"
  printf '%s' "$output" | grep -q "re-run /nightshift:setup"
  grep -q 'stall guard down' "$p/.nightshift/shift-log.md"
}
