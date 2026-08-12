load ../helpers

# The Codex watchman is the outside half for codex-owned shifts. Everything here runs with
# NIGHTSHIFT_WATCH_SLEEP=0 (the test speed lever) and small --max-wakes bounds. The agent is
# always stubbed: these tests prove the DECISIONS, not the codex CLI.

setup() {
  WATCHMAN="$BATS_TEST_DIRNAME/../../plugins/nightshift/runtime/codex/watchman.sh"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.nightshift"
  cp "$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json" "$P/.nightshift/rules.json"
  printf '## Items\n- [ ] **1.**\n' >"$P/.nightshift/punch-list.md"

  # a recorded codex shift whose rollout is a plain file the tests control
  ROLLOUT="$BATS_TEST_TMPDIR/rollout.jsonl"
  printf '{"type":"session_meta"}\n' >"$ROLLOUT"
  printf 'dead-sid\n%s\n99999\nnever\ncodex\n' "$ROLLOUT" >"$P/.nightshift/.shift-session"

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  cat >"$BIN/tick.sh" <<'STUB'
#!/usr/bin/env bash
echo "called $NIGHTSHIFT_REVIVAL" >>.nightshift/agent-calls
awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
mv .nightshift/pl.tmp .nightshift/punch-list.md
STUB
  chmod +x "$BIN"/*.sh
}

watch() { # watch [extra args...] — fast defaults, stubbed agent
  env NIGHTSHIFT_WATCH_SLEEP=0 NIGHTSHIFT_WATCH_RETRY="0 0" \
    "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" "$@"
}

calls() { grep -c called "$P/.nightshift/agent-calls" 2>/dev/null || echo 0; }

@test "interval 0 is the disabled spelling: exits at once, arms nothing" {
  run "$WATCHMAN" --project "$P" --interval 0
  [ "$status" -eq 0 ]
  [ ! -f "$P/.nightshift/.watchman" ]
}

@test "a missing rules file refuses to arm" {
  rm "$P/.nightshift/rules.json"
  run "$WATCHMAN" --project "$P"
  [ "$status" -eq 1 ]
}

@test "refuses to double-arm while another watchman is alive" {
  printf '%s\n' "$$" >"$P/.nightshift/.watchman"
  run watch --max-wakes 1
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'already watching'
}

@test "a stop-work order stands it down" {
  touch "$P/.nightshift/STOP"
  run watch --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

# The mirror of the Claude watchman's host guard: a shift another host owns is never revived
# from here — its own watchman minds it.
@test "a claude-owned shift stands the codex watchman down" {
  printf 'sid\n\n\n\nclaude\n' >"$P/.nightshift/.shift-session"
  run watch --max-wakes 1
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
  grep -q 'owned by claude' "$P/.nightshift/shift-log.md"
}

@test "a record with no host line is claude's — stood down, never adopted" {
  printf 'sid\n\n\n\n' >"$P/.nightshift/.shift-session"
  run watch --max-wakes 1
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

@test "a dead record with open boxes is revived, marked as a revival" {
  run watch --max-wakes 1
  [ "$status" -eq 0 ]
  [ "$(calls)" -ge 1 ]
  grep -q 'called 1' "$P/.nightshift/agent-calls" # NIGHTSHIFT_REVIVAL=1 reached the child
  grep -q 'resume attempt 1' "$P/.nightshift/shift-log.md"
}

@test "the recorded pid alive with a matching start time stands it by" {
  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'sid\n%s\n%s\n%s\ncodex\n' "$ROLLOUT" "$$" "$start" >"$P/.nightshift/.shift-session"
  run watch --max-wakes 2
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

@test "a growing rollout is a pulse: stood by, not revived" {
  # The appender must provably beat every wake, or the first zero-sleep wake reads a quiet
  # rollout and revives — a race, not a verdict. It writes every 0.1s and the watchman sleeps a
  # full second per wake, and the test waits for the first append before arming.
  ( while sleep 0.1; do echo x >>"$ROLLOUT"; done ) &
  appender=$!
  base="$(wc -c <"$ROLLOUT")"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(wc -c <"$ROLLOUT")" != "$base" ] && break
    sleep 0.2
  done
  run env NIGHTSHIFT_WATCH_SLEEP=1 NIGHTSHIFT_WATCH_RETRY="0 0"     "$WATCHMAN" --project "$P" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 3
  kill "$appender" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}

@test "all boxes ticked with no .ended gets one clock-out spawn, then down" {
  printf '## Items\n- [x] **1.**\n' >"$P/.nightshift/punch-list.md"
  run watch --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
  grep -q 'never clocked out' "$P/.nightshift/shift-log.md"
}

@test "a spent deadline with a dead session gets the clock-out spawn" {
  echo $(($(date +%s) - 60)) >"$P/.nightshift/deadline"
  run watch --max-wakes 1
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
  grep -q 'past the deadline' "$P/.nightshift/shift-log.md"
}

@test ".ended stands it down before anything else spawns" {
  touch "$P/.nightshift/.ended"
  run watch --max-wakes 3
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 0 ]
}
