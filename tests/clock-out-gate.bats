load helpers

@test "blocks while a box is open" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
}

@test "clock-out reinjection qualifies punch-list against the workspace" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
  printf '%s' "$output" | grep -qF "$p/.nightshift/punch-list.md"
  printf '%s' "$output" | grep -qF "$p/.nightshift/parking-lot.md"
  printf '%s' "$output" | grep -qF "$p/.nightshift/STOP"
  ! printf '%s' "$output" | grep -qF '$NIGHTSHIFT_WORKSPACE'
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
  [ -f "$p/.nightshift/.ended" ]
  [ ! -f "$p/.nightshift/.shift-armed" ]
}

@test "clock-out replaces a symlink ended marker with a regular file" {
  p="$(new_project)"
  punch_done "$p"
  printf 'plant\n' >"$p/.nightshift/ended-plant"
  ln -s ended-plant "$p/.nightshift/.ended"
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/.ended" ]
  [ ! -L "$p/.nightshift/.ended" ]
}

@test "morning whistle replaces a symlink notified marker" {
  p="$(new_project)"
  punch_done "$p"
  printf 'plant\n' >"$p/.nightshift/notified-plant"
  ln -s notified-plant "$p/.nightshift/.notified"
  wl="$BATS_TEST_TMPDIR/notified-plant.log"
  run gate "$p" NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl"
  is_release
  [ -f "$p/.nightshift/.notified" ]
  [ ! -L "$p/.nightshift/.notified" ]
  grep -q 'shift done: 2/2' "$wl"
  grep -qF 'plant' "$p/.nightshift/notified-plant"
}

@test "stop-work order releases even with open boxes" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run gate "$p"
  is_release
}

@test "panic STOP releases a leftover recovery nonce" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\nclaude\n' >"$p/.nightshift/.shift-session"
  bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" the-shift claude' \
    nightshift "$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh" "$p" >/dev/null
  printf 'stopped by owner\n' >"$p/.nightshift/STOP"
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/.ended" ]
  [ ! -f "$p/.nightshift/.shift-lease" ]
}

@test "the recorded session can clock out after a restored interactive lease" {
  p="$(new_project)"
  punch_done "$p"
  printf 'test-shift-session\n\n\n\nclaude\n' >"$p/.nightshift/.shift-session"
  bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" test-shift-session claude; ns_lease_restore_interactive "$2/.nightshift"' \
    nightshift "$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh" "$p"
  [ -z "$(sed -n 4p "$p/.nightshift/.shift-lease")" ]
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/.ended" ]
  [ ! -f "$p/.nightshift/.shift-lease" ]
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
  jq '.receiptsAutoCommit = true' "$p/.nightshift/rules.json" >"$p/.nightshift/rules.tmp"
  mv "$p/.nightshift/rules.tmp" "$p/.nightshift/rules.json"
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
  jq '.receiptsAutoCommit = true' "$p/.nightshift/rules.json" >"$p/.nightshift/rules.tmp"
  mv "$p/.nightshift/rules.tmp" "$p/.nightshift/rules.json"
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

@test "a symlink deadline never ends the shift by accident" {
  p="$(new_project)"
  punch_open "$p"
  echo $(($(date +%s) - 60)) >"$p/.nightshift/deadline-plant"
  ln -s deadline-plant "$p/.nightshift/deadline"
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

@test "a symlink stall does not auto-end the shift" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p" NIGHTSHIFT_STALL_MAX=2
  is_block "$output"
  fp="$(sed -n 1p "$p/.nightshift/.stall")"
  printf '%s\n99\n' "$fp" >"$p/.nightshift/stall-plant"
  rm -f "$p/.nightshift/.stall"
  ln -s stall-plant "$p/.nightshift/.stall"
  run gate "$p" NIGHTSHIFT_STALL_MAX=2
  is_block "$output"
  [ -f "$p/.nightshift/.stall" ]
  [ ! -L "$p/.nightshift/.stall" ]
  [ "$(sed -n 2p "$p/.nightshift/.stall")" = "1" ]
  [ ! -f "$p/.nightshift/STOP" ]
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

@test "an artifact receipt resets the stall counter" {
  p="$(new_project art-stall)"
  printf 'artifact\n' >"$p/.nightshift/work-mode"
  punch_open "$p"
  run gate "$p"
  run gate "$p"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "2" ]
  printf 'ok\n' >"$p/note.md"
  run bash "$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/write-receipt.sh" \
    --project "$p" --item 'x' --verify 'ok' --output "$p/note.md"
  [ "$status" -eq 0 ]
  run gate "$p"
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "1" ]
}

@test "a symlink work-mode does not treat receipts as stall progress" {
  p="$(new_project mode-link-stall)"
  printf 'artifact\n' >"$p/.nightshift/mode-plant"
  ln -s mode-plant "$p/.nightshift/work-mode"
  punch_open "$p"
  run gate "$p" NIGHTSHIFT_STALL_MAX=10 NIGHTSHIFT_STALL_WARN=1
  run gate "$p" NIGHTSHIFT_STALL_MAX=10 NIGHTSHIFT_STALL_WARN=1
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "2" ]
  mkdir -p "$p/.nightshift/receipts"
  printf 'planted\n' >"$p/.nightshift/receipts/20260101T000000Z-plant.md"
  run gate "$p" NIGHTSHIFT_STALL_MAX=10 NIGHTSHIFT_STALL_WARN=1
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "3" ]
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

@test "a done release commits the receipts repo only when receiptsAutoCommit is true" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  punch_done "$p"
  run gate "$p"
  is_release
  # Default / missing key: receipts git stays at the Setup init commit only.
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 1 ]
  jq '.receiptsAutoCommit = true' "$p/.nightshift/rules.json" >"$p/.nightshift/rules.tmp"
  mv "$p/.nightshift/rules.tmp" "$p/.nightshift/rules.json"
  rm -f "$p/.nightshift/.ended" "$p/.nightshift/.notified"
  : >"$p/.nightshift/.shift-armed"
  run gate "$p"
  is_release
  [ "$(git -C "$p/.nightshift" rev-list --count HEAD)" -eq 2 ]
  git -C "$p/.nightshift" log -1 --format=%s | grep -q 'shift done: 2/2'
  ! git -C "$p/.nightshift" ls-tree -r --name-only HEAD | grep -qxF '.shift-lease'
}

@test "a stop-work release snapshots the receipts repo when receiptsAutoCommit is true" {
  p="$(new_project)"
  punch_open "$p"
  receipts_init "$p"
  jq '.receiptsAutoCommit = true' "$p/.nightshift/rules.json" >"$p/.nightshift/rules.tmp"
  mv "$p/.nightshift/rules.tmp" "$p/.nightshift/rules.json"
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
  [ "$(wc -l <"$p/.nightshift/.shift-session")" -eq 5 ] # id, transcript, pid, start time, host
  # The host is what stops another agent's watchman acting on a shift that is not its own.
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "claude" ]
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

# The fresh-session fallback gives a revival a NEW id. The watchman's generation capability,
# not a forgeable boolean mark, authorizes the rebind.
@test "a leased revival inherits the binding under a new id and re-claims the record" {
  p="$(new_project)"
  punch_open "$p"
  printf 'dead-old-id\n\n\n\n' >"$p/.nightshift/.shift-session"
  lib="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
  claim="$(bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" dead-old-id claude' \
    nightshift "$lib" "$p")"
  run gate "$p" NIGHTSHIFT_REVIVAL=1 \
    NIGHTSHIFT_LEASE_GENERATION="${claim%% *}" NIGHTSHIFT_LEASE_NONCE="${claim#* }"
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
# zero. Serialized, exactly one warns and the counter lands where a sequence of two valid stop
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
  printf '%s' "$output" | grep -qF '/nightshift:setup'
  printf '%s' "$output" | grep -qF 'ask Nightshift to set up on Codex'
  grep -q 'stall guard down' "$p/.nightshift/shift-log.md"
}
