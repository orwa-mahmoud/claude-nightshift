load helpers

# The watchman is the outside half of the product: hooks cannot fire in a dead session, so a
# separate process revives a site that is mid-shift AND quiet. Everything here runs with
# NIGHTSHIFT_WATCH_SLEEP=0 (the test speed lever) and small --max-wakes bounds.

setup() {
  WATCHMAN="$BATS_TEST_DIRNAME/../adapters/watchman.sh"
  SESSION_END="$BATS_TEST_DIRNAME/../hooks/session-end.sh"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.nightshift"
  printf '## Items\n- [ ] **1.**\n' >"$P/.nightshift/punch-list.md"

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  # logs the call, then ticks the first open box (CWD is the project — watchman cd's there)
  cat >"$BIN/tick.sh" <<'STUB'
#!/usr/bin/env bash
echo called >>.nightshift/agent-calls
awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
mv .nightshift/pl.tmp .nightshift/punch-list.md
STUB
  # logs the call and fails — the API-down shape
  cat >"$BIN/fail.sh" <<'STUB'
#!/usr/bin/env bash
echo called >>.nightshift/agent-calls
exit 1
STUB
  chmod +x "$BIN"/*.sh
}

watch() { # watch [extra watchman args...] — fast defaults
  env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    "$WATCHMAN" --project "$P" --interval 20 "$@"
}

calls() { grep -c called "$P/.nightshift/agent-calls" 2>/dev/null || echo 0; }

@test "interval 0 is the disabled spelling: exits at once, arms nothing" {
  run "$WATCHMAN" --project "$P" --interval 0
  [ "$status" -eq 0 ]
  [ ! -f "$P/.nightshift/.watchman" ]
}

@test "refuses to double-arm while another watchman is alive" {
  printf '%s\n' "$$" >"$P/.nightshift/.watchman"
  run watch --max-wakes 1
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'already watching'
}

@test "a stop-work order stands it down" {
  touch "$P/.nightshift/STOP"
  run watch --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 0 ]
  grep -q 'stop-work order — standing down' "$P/.nightshift/shift-log.md"
  [ "$(calls)" -eq 0 ]
}

@test "an already-ended shift stands it down" {
  touch "$P/.nightshift/.ended"
  run watch --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

@test "a clean session end stands it down — the owner closed it on purpose" {
  echo 'clean session end (exit)' >"$P/.nightshift/.session-end"
  run watch --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 0 ]
  grep -q 'the owner closed it' "$P/.nightshift/shift-log.md"
  [ "$(calls)" -eq 0 ]
}

@test "a quiet site with open boxes is resumed, then clocked out" {
  run watch --agent "bash $BIN/tick.sh" --max-wakes 5
  [ "$status" -eq 0 ]
  ! grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
  [ "$(calls)" -eq 2 ] # one resume that ticked the box, one clock-out spawn
  grep -q 'resume attempt 1' "$P/.nightshift/shift-log.md"
  grep -q 'never clocked out — spawning the clock-out' "$P/.nightshift/shift-log.md"
}

@test "a live site is never resumed" {
  ( while :; do touch "$P/beat"; sleep 0.15; done ) &
  toucher=$!
  run env NIGHTSHIFT_WATCH_SLEEP=1 NIGHTSHIFT_WATCH_RETRY="0 0" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 2
  kill "$toucher" 2>/dev/null || true
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
}

@test "an API-down agent gets exactly 3 tries per wake, then backs off" {
  run watch --agent "bash $BIN/fail.sh" --max-wakes 2
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 6 ]
  grep -q 'attempts failed' "$P/.nightshift/shift-log.md"
}

@test "all boxes ticked without .ended spawns exactly one clock-out" {
  printf '## Items\n- [x] **1.**\n' >"$P/.nightshift/punch-list.md"
  run watch --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
}

@test "quitting time with a dead site spawns the clock-out and stands down" {
  printf '%s' "$(( $(date +%s) - 60 ))" >"$P/.nightshift/deadline"
  run watch --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
  grep -q 'quitting time passed' "$P/.nightshift/shift-log.md"
}

@test "an option with no value exits instead of spinning" {
  run "$WATCHMAN" --interval
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q -- '--interval needs a value'
}

@test "session-end hook writes the marker only during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  printf '{"reason":"exit"}' | CLAUDE_PROJECT_DIR="$p" bash "$SESSION_END"
  grep -q 'clean session end (exit)' "$p/.nightshift/.session-end"
}

@test "session-end hook is inert when the shift is done or absent" {
  p="$(new_project)"
  punch_done "$p"
  printf '{"reason":"exit"}' | CLAUDE_PROJECT_DIR="$p" bash "$SESSION_END"
  [ ! -f "$p/.nightshift/.session-end" ]
  q="$(new_project other)"
  printf '{"reason":"exit"}' | CLAUDE_PROJECT_DIR="$q" bash "$SESSION_END"
  [ ! -f "$q/.nightshift/.session-end" ]
}

@test "the default agent continues the conversation, with a fresh-session final fallback" {
  # A fake `claude` on PATH: --continue always fails (a broken transcript), plain -p succeeds
  # and ticks the box — proving the last retry saves the night when the transcript cannot.
  cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
if printf '%s' "$*" | grep -q -- '--continue'; then
  echo continue >>.nightshift/agent-calls
  exit 1
fi
echo fresh >>.nightshift/agent-calls
awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
mv .nightshift/pl.tmp .nightshift/punch-list.md
STUB
  chmod +x "$BIN/claude"
  run env PATH="$BIN:$PATH" NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    "$WATCHMAN" --project "$P" --interval 20 --max-wakes 4
  [ "$status" -eq 0 ]
  ! grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
  [ "$(grep -c continue "$P/.nightshift/agent-calls")" -eq 3 ] # 2 wake retries + the clock-out
  [ "$(grep -c fresh "$P/.nightshift/agent-calls")" -eq 1 ]    # the fallback that revived it
  grep -q 'fresh-session fallback' "$P/.nightshift/shift-log.md"
}

# Esc means stop, platform-wide. Claude Code writes "Request interrupted by user" into the
# session transcript; a 500 or a crash never does. That marker in the tail is how the watchman
# tells an owner's pause from a dead site.
@test "an Esc-paused session is stood by, never resumed" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n{"type":"message","content":"[Request interrupted by user]"}\n' >"$T/session.jsonl"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'owner pressed Esc — standing by' "$P/.nightshift/shift-log.md"
  [ "$(grep -c 'standing by' "$P/.nightshift/shift-log.md")" -eq 1 ] # logged once, not every wake
}

@test "a transcript without an interrupt in its tail is revived" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"[Request interrupted by user]"}\n' >"$T/session.jsonl"
  for i in $(seq 1 30); do printf '{"type":"message","content":"work %s"}\n' "$i" >>"$T/session.jsonl"; done
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 5
  [ "$status" -eq 0 ]
  ! grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
  [ "$(calls)" -eq 2 ]
}

# The Esc tell reads the SHIFT'S recorded transcript — a second tab's interrupt proves nothing.
@test "the shift's own transcript decides Esc, not the newest in the project" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"[Request interrupted by user]"}\n' >"$T/shift.jsonl"
  sleep 0.01
  printf '{"type":"message","content":"other tab, still working"}\n' >"$T/other.jsonl" # newer, clean
  printf 'sid-shift\n%s\n' "$T/shift.jsonl" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'standing by' "$P/.nightshift/shift-log.md"
}

@test "another tab's Esc does not block the revival of a dead shift session" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n' >"$T/shift.jsonl"
  sleep 0.01
  printf '{"type":"message","content":"[Request interrupted by user]"}\n' >"$T/other.jsonl" # newer!
  printf 'sid-shift\n%s\n' "$T/shift.jsonl" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 5
  [ "$status" -eq 0 ]
  ! grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
}

# The default revival is the shift's exact conversation, by id — with the layered fallback.
@test "the default agent resumes the recorded session by id" {
  printf 'abc-123\n\n' >"$P/.nightshift/.shift-session"
  cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *--resume*) echo "resume:$1 $2" >>.nightshift/agent-calls; exit 1 ;;
  *--continue*) echo "continue" >>.nightshift/agent-calls; exit 1 ;;
  *) echo fresh >>.nightshift/agent-calls
     awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
     mv .nightshift/pl.tmp .nightshift/punch-list.md ;;
esac
STUB
  chmod +x "$BIN/claude"
  run env PATH="$BIN:$PATH" NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --max-wakes 4
  [ "$status" -eq 0 ]
  grep -q 'resume:--resume abc-123' "$P/.nightshift/agent-calls"
  [ "$(grep -c fresh "$P/.nightshift/agent-calls")" -eq 1 ]
}

@test "session-end writes the marker only for the shift's own session" {
  p="$(new_project)"
  punch_open "$p"
  printf 'right-id\n\n' >"$p/.nightshift/.shift-session"
  printf '{"reason":"exit","session_id":"wrong-id"}' | CLAUDE_PROJECT_DIR="$p" bash "$SESSION_END"
  [ ! -f "$p/.nightshift/.session-end" ]
  printf '{"reason":"exit","session_id":"right-id"}' | CLAUDE_PROJECT_DIR="$p" bash "$SESSION_END"
  grep -q 'clean session end (exit)' "$p/.nightshift/.session-end"
}

# ---- v0.5.2: the liveness ladder — strong positive evidence of death, or stand by ----

# Primary pulse: a session streams every turn into its transcript even when the work writes no
# project files. Transcript movement alone means alive.
@test "transcript activity alone keeps the watchman standing by" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n' >"$T/shift.jsonl"
  printf 'sid-shift\n%s\n' "$T/shift.jsonl" >"$P/.nightshift/.shift-session"
  ( while :; do printf '{"type":"message","content":"x"}\n' >>"$T/shift.jsonl"; sleep 0.15; done ) &
  toucher=$!
  run env NIGHTSHIFT_WATCH_SLEEP=1 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 2
  kill "$toucher" 2>/dev/null || true
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
}

@test "a helper transcript's activity is not the shift's pulse" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n' >"$T/shift.jsonl"
  printf 'sid-shift\n%s\n' "$T/shift.jsonl" >"$P/.nightshift/.shift-session"
  ( while :; do printf '{"type":"message","content":"other"}\n' >>"$T/other.jsonl"; sleep 0.15; done ) &
  toucher=$!
  run env NIGHTSHIFT_WATCH_SLEEP=1 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 4
  kill "$toucher" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ] # revived despite the helper's noise, then clocked out
}

# The process witness: the recorded pid alive with a quiet, unerrored transcript is long silent
# work — a 25-minute test run writes nothing anywhere. Never spawn beside it.
@test "the shift's own live process holds the watchman through a silent stretch" {
  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'sid-shift\n\n%s\n%s\n' "$$" "$start" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'long silent work; standing by' "$P/.nightshift/shift-log.md"
  [ "$(grep -c 'standing by' "$P/.nightshift/shift-log.md")" -eq 1 ] # logged once, not every wake
}

# The wedge: process alive, transcript quiet, and the host's own API-error event at the tail —
# a session sitting at an errored prompt with nobody there. This one is revived.
@test "a live shift process at an errored prompt is the wedge — revived" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n{"type":"error","content":"API Error: 500 Internal server error"}\n' >"$T/shift.jsonl"
  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'sid-shift\n%s\n%s\n%s\n' "$T/shift.jsonl" "$$" "$start" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 4
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ]
  grep -q 'probable wedge' "$P/.nightshift/shift-log.md"
}

# A session merely TALKING about API errors is not the wedge — the escaped quote of prose
# never matches the host's own event string.
@test "prose mentioning API errors does not read as the wedge" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"we should handle the \\"API Error: 500\\" case"}\n' >"$T/shift.jsonl"
  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'sid-shift\n%s\n%s\n%s\n' "$T/shift.jsonl" "$$" "$start" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 2
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'long silent work; standing by' "$P/.nightshift/shift-log.md"
}

@test "a dead recorded pid is strong evidence — revived" {
  bash -c ':' &
  deadpid=$!
  wait "$deadpid" 2>/dev/null || true
  printf 'sid-shift\n\n%s\n\n' "$deadpid" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 4
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ]
}

# A pid wears the number but not the birthday: a mismatched start time means the shift's
# process is gone and something else inherited its pid.
@test "a reused pid is not the shift's process — revived" {
  printf 'sid-shift\n\n%s\n%s\n' "$$" "Thu Jan  1 00:00:00 1970" >"$P/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 4
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ]
}

# No pid recorded: any claude process working in this project is reason enough not to spawn.
# Not identity — just the conservative reading of an uncertain site.
@test "with no recorded pid, a claude process in the project stands the watchman by" {
  cat >"$BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
echo 999999
STUB
  cat >"$BIN/ps" <<'STUB'
#!/usr/bin/env bash
echo "/fake/bin/claude"
STUB
  cat >"$BIN/lsof" <<STUB
#!/usr/bin/env bash
echo "p999999"
echo "n$P"
STUB
  chmod +x "$BIN/pgrep" "$BIN/ps" "$BIN/lsof"
  run env PATH="$BIN:$PATH" NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 3
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'a claude session is live in this project — standing by' "$P/.nightshift/shift-log.md"
}

# ---- v0.5.2: pre-spawn re-checks and the honest retry baseline ----

@test "site activity during the retry sleep cancels the remaining attempts" {
  ( sleep 1; touch "$P/came-back" ) &
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="2" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/fail.sh" --max-wakes 1
  wait 2>/dev/null || true
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 1 ]
  grep -q 'site activity during retries — holding the remaining attempts' "$P/.nightshift/shift-log.md"
}

# A failed resume may append its own API-error event to the shift transcript. Re-baselining
# after each attempt keeps the watchman from mistaking its own noise for site life.
@test "the watchman's own failed attempt cannot fool the retry check" {
  T="$BATS_TEST_TMPDIR/transcripts"
  mkdir -p "$T"
  printf '{"type":"message","content":"working"}\n' >"$T/shift.jsonl"
  printf 'sid-shift\n%s\n' "$T/shift.jsonl" >"$P/.nightshift/.shift-session"
  cat >"$BIN/fail-noisy.sh" <<STUB
#!/usr/bin/env bash
echo called >>.nightshift/agent-calls
printf '{"type":"error","content":"API Error: 500"}\n' >>"$T/shift.jsonl"
exit 1
STUB
  chmod +x "$BIN/fail-noisy.sh"
  run env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" NIGHTSHIFT_WATCH_TRANSCRIPTS="$T" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/fail-noisy.sh" --max-wakes 1
  [ "$status" -eq 7 ]
  [ "$(calls)" -eq 3 ] # all three attempts ran; none was fooled by the previous one's writes
  ! grep -q 'during retries' "$P/.nightshift/shift-log.md"
}

# ---- v0.5.2: the revival chain — recorded conversation, --continue, fresh session ----

@test "a failed resume degrades to --continue before the fresh session" {
  printf 'abc-123\n\n\n\n' >"$P/.nightshift/.shift-session"
  cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *--resume*) echo resume >>.nightshift/agent-calls; exit 1 ;;
  *--continue*) echo continue >>.nightshift/agent-calls; exit 1 ;;
  *) echo fresh >>.nightshift/agent-calls
     awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
     mv .nightshift/pl.tmp .nightshift/punch-list.md ;;
esac
STUB
  chmod +x "$BIN/claude"
  run env PATH="$BIN:$PATH" NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --max-wakes 4
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$P/.nightshift/agent-calls")" = "resume" ]
  [ "$(sed -n 2p "$P/.nightshift/agent-calls")" = "continue" ]
  [ "$(sed -n 3p "$P/.nightshift/agent-calls")" = "fresh" ]
  grep -q 'resuming the recorded conversation' "$P/.nightshift/shift-log.md"
  grep -q -- '--continue fallback' "$P/.nightshift/shift-log.md"
  grep -q 'fresh-session fallback' "$P/.nightshift/shift-log.md"
}

@test "a successful resume never falls to --continue or a fresh session" {
  printf 'abc-123\n\n\n\n' >"$P/.nightshift/.shift-session"
  cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *--resume*) echo resume >>.nightshift/agent-calls
     awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
     mv .nightshift/pl.tmp .nightshift/punch-list.md ;;
  *--continue*) echo continue >>.nightshift/agent-calls ;;
  *) echo fresh >>.nightshift/agent-calls ;;
esac
STUB
  chmod +x "$BIN/claude"
  run env PATH="$BIN:$PATH" NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    NIGHTSHIFT_WATCH_TRANSCRIPTS=/tmp/nowhere \
    "$WATCHMAN" --project "$P" --interval 20 --max-wakes 4
  [ "$status" -eq 0 ]
  ! grep -q continue "$P/.nightshift/agent-calls"
  ! grep -q fresh "$P/.nightshift/agent-calls"
  [ "$(grep -c resume "$P/.nightshift/agent-calls")" -eq 2 ] # the revival and the clock-out
}
