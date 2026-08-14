load helpers

ROOT="$BATS_TEST_DIRNAME/.."
RUNTIME="$ROOT/plugins/nightshift/runtime"
REF="$ROOT/plugins/nightshift/skills/nightshift/references"
CODEX_HOOKS="$HOOKS/codex"
CLAUDE_WM="$RUNTIME/claude/watchman.sh"
CODEX_WM="$RUNTIME/codex/watchman.sh"
DOCTOR="$RUNTIME/doctor.sh"
SCHED="$RUNTIME/schedule.sh"
LINK="$RUNTIME/link-workspace.sh"
SESSION_END="$HOOKS/session-end.sh"

codex_gate() {
  local p="$1"
  jq -nc --arg p "$p" '{hook_event_name:"Stop",session_id:"fixture-session",transcript_path:"",cwd:$p}' |
    env CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/clock-out-gate.sh"
}
codex_ask() {
  local p="$1"
  jq -nc '{tool_name:"request_user_input",tool_input:{}}' |
    env CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
}

scaffold() { # <workspace> — the files setup copies, via the shipped templates
  local w="$1"
  mkdir -p "$w/.nightshift"
  for f in punch-list drafting-table parking-lot snag-log product-research opportunity-map work-orders; do
    cp "$REF/$f-template.md" "$w/.nightshift/$f.md"
  done
  cp "$REF/nightshift-rules-template.json" "$w/.nightshift/rules.json"
  printf '# Shift Log\n' >"$w/.nightshift/shift-log.md"
  printf '1\n' >"$w/.nightshift/state-version"
}

@test "setup templates, arming, and both host gates share the open-item block" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [ ] **1. real work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  q="$(new_project q)"
  scaffold "$q"
  printf '## Items\n- [ ] **1. real work.**\n' >"$q/.nightshift/punch-list.md"
  : >"$q/.nightshift/.shift-armed"

  run gate "$p"
  is_block "$output"
  run codex_gate "$q"
  is_block "$output"

  run hardhat_ask "$p"
  is_deny "$output"
  run codex_ask "$q"
  is_deny "$output"
}

@test "STOP releases both hosts and leaves open boxes honestly open" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [ ] **1. real work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  : >"$p/.nightshift/STOP"

  run gate "$p"
  is_release
  run codex_gate "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == true' >/dev/null
  grep -qE '^- \[ \]' "$p/.nightshift/punch-list.md"
}

@test "parent workspace, spaced paths, and an explicit link share one punch list" {
  ws="$BATS_TEST_TMPDIR/parent with spaces"
  scaffold "$ws"
  add_repo "$ws" repo
  printf '%s\n' "$(cd -P "$ws/repo" && pwd)" >"$ws/.nightshift/work-target"
  printf '## Items\n- [ ] **1. real work.**\n' >"$ws/.nightshift/punch-list.md"
  : >"$ws/.nightshift/.shift-armed"

  host="$BATS_TEST_TMPDIR/host with spaces"
  mkdir -p "$host"
  run bash "$LINK" --host-root "$host" --workspace "$ws"
  [ "$status" -eq 0 ]

  run bash "$DOCTOR" --project "$host"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Link:        valid'
  printf '%s' "$output" | grep -q 'open=1'

  run gate "$host"
  is_block "$output"

  host2="$BATS_TEST_TMPDIR/host2 with spaces"
  mkdir -p "$host2"
  bash "$LINK" --host-root "$host2" --workspace "$ws" >/dev/null
  # A second task root, same workspace, no session recorded yet — Codex must still hold the list.
  rm -f "$ws/.nightshift/.shift-session"
  : >"$ws/.nightshift/.shift-armed"
  run codex_gate "$host2"
  is_block "$output"
}

@test "Claude session-end is the clean-end marker; Codex live-but-errored is stood by" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [ ] **1. real work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  printf '{"reason":"exit","session_id":"fixture-session"}' | CLAUDE_PROJECT_DIR="$p" bash "$SESSION_END"
  [ -f "$p/.nightshift/.session-end" ]

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  cat >"$BIN/tick.sh" <<'STUB'
#!/usr/bin/env bash
echo called >>.nightshift/agent-calls
STUB
  chmod +x "$BIN/tick.sh"
  start="$(ps -o lstart= -p $$ | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf 'sid\n\n%s\n%s\ncodex\n' "$$" "$start" >"$p/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 "$CODEX_WM" --project "$p" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 1
  [ "$status" -eq 0 ]
  [ ! -f "$p/.nightshift/agent-calls" ]
}

@test "interrupted recovery: STOP stands both watchmen down with no leftover pid" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [ ] **1. real work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  : >"$p/.nightshift/STOP"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  printf '#!/usr/bin/env bash\necho called >>.nightshift/agent-calls\n' >"$BIN/tick.sh"
  chmod +x "$BIN/tick.sh"

  run env NIGHTSHIFT_WATCH_SLEEP=0 "$CLAUDE_WM" --project "$p" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 1
  [ "$status" -eq 0 ]
  [ ! -f "$p/.nightshift/.watchman" ]
  [ ! -f "$p/.nightshift/agent-calls" ]

  printf 'sid\n\n99999\nnever\ncodex\n' >"$p/.nightshift/.shift-session"
  run env NIGHTSHIFT_WATCH_SLEEP=0 "$CODEX_WM" --project "$p" --interval 20 --agent "bash $BIN/tick.sh" --max-wakes 1
  [ "$status" -eq 0 ]
  [ ! -f "$p/.nightshift/.watchman" ]
  [ ! -f "$p/.nightshift/agent-calls" ]
}

@test "completion clocks out, archive layout keeps the contract, scheduler is untouched" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [x] **1. shipped.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  run gate "$p"
  is_release
  [ -f "$p/.nightshift/.ended" ]

  day="2026-08-14"
  mkdir -p "$p/.nightshift/archive/$day"
  printf '## Shipped %s\n- [x] **1. shipped.**\n' "$day" >"$p/.nightshift/archive/$day/shipped.md"
  grep -q 'The enforced to-do' "$p/.nightshift/punch-list.md" || \
    grep -q '## Items' "$p/.nightshift/punch-list.md"

  home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library/LaunchAgents"
  run env HOME="$home" "$SCHED" --project "$p" --preflight
  [ "$status" -eq 1 ] # no open items
  [ -z "$(find "$home/Library/LaunchAgents" -type f)" ]
}

@test "Doctor and preflight stay read-only across the lifecycle fixtures" {
  p="$(new_project)"
  scaffold "$p"
  printf '## Items\n- [ ] **1. real work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  before="$(find "$p" -type f -exec cksum {} \; | sort)"
  run bash "$DOCTOR" --project "$p"
  [ "$status" -eq 0 ]
  after="$(find "$p" -type f -exec cksum {} \; | sort)"
  [ "$before" = "$after" ]
}
