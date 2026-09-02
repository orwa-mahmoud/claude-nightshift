load ../helpers

HOOKS="$BATS_TEST_DIRNAME/../../plugins/nightshift/hooks"
CURSOR_HOOKS="$HOOKS/cursor"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/hooks/v1/cursor"

is_cursor_deny() {
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.permission == "deny"' >/dev/null
}

@test "cursor hardhat denies a forbidden Shell command during a shift" {
  p="$(new_project)"
  punch_open "$p"
  run env CURSOR_PROJECT_DIR="$p" NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' \
    bash "$CURSOR_HOOKS/hardhat.sh" <"$FIXTURES/shell-forbidden.json"
  is_cursor_deny
}

@test "cursor hardhat records the cursor host from a cursor transcript path" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"cursor-tab",transcript_path:"/Users/o/.cursor/projects/x/agent-transcripts/u/u.jsonl",cwd:$p,tool_input:{command:"echo hi"}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "cursor-tab" ]
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "cursor" ]
  [ "$(sed -n 2p "$p/.nightshift/.shift-lease")" = "cursor" ]
}

@test "cursor hardhat reclaims a claude-contaminated lease for the same session" {
  p="$(new_project)"
  punch_open "$p"
  printf '%s\n' cursor-tab \
    '/Users/o/.cursor/projects/x/agent-transcripts/u/u.jsonl' '' '' cursor \
    >"$p/.nightshift/.shift-session"
  printf '%s\n' cursor-tab claude 1 '' '' '' >"$p/.nightshift/.shift-lease"
  chmod 600 "$p/.nightshift/.shift-session" "$p/.nightshift/.shift-lease"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"cursor-tab",transcript_path:"/Users/o/.cursor/projects/x/agent-transcripts/u/u.jsonl",cwd:$p,tool_input:{command:"echo hi"}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-lease")" = "cursor-tab" ]
  [ "$(sed -n 2p "$p/.nightshift/.shift-lease")" = "cursor" ]
}

# ---- the site rules bind the shift's session; other conversations keep their tools ----

@test "another conversation is untouched by the site rules" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  out="$(jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"helper-tab",transcript_path:"",cwd:$p,tool_input:{command:"git push origin main"}}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

@test "the shift session itself still answers to the site rules" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"the-shift",transcript_path:"",cwd:$p,tool_input:{command:"git push origin main"}}' \
    >"$BATS_TEST_TMPDIR/held-shell.json"
  run env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CURSOR_PROJECT_DIR="$p" \
    bash "$CURSOR_HOOKS/hardhat.sh" <"$BATS_TEST_TMPDIR/held-shell.json"
  is_cursor_deny
}

@test "origin tab is pointed at the live CLI worker" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"origin-ide",transcript_path:"",cwd:$p,tool_input:{command:"echo hi"}}' \
    >"$BATS_TEST_TMPDIR/origin-shell.json"
  run env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh" <"$BATS_TEST_TMPDIR/origin-shell.json"
  is_cursor_deny
  printf '%s' "$output" | grep -q 'agent --resume='
  printf '%s' "$output" | grep -q 'live-cli-worker'
  printf '%s' "$output" | grep -q -- "--workspace"
  printf '%s' "$output" | grep -q 'terminal'
  printf '%s' "$output" | grep -q 'ask Nightshift to stop'
}

@test "origin tab can still run the stop helper while a worker is live" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  plugin="$BATS_TEST_DIRNAME/../../plugins/nightshift"
  jq -nc --arg p "$p" --arg cmd "bash $plugin/runtime/stop-shift.sh --project $p" \
    '{tool_name:"Shell",conversation_id:"origin-ide",transcript_path:"",cwd:$p,tool_input:{command:$cmd}}' \
    >"$BATS_TEST_TMPDIR/origin-stop-helper.json"
  run env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh" <"$BATS_TEST_TMPDIR/origin-stop-helper.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "another conversation stays free while a CLI worker is recorded" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  out="$(jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"helper-tab",transcript_path:"",cwd:$p,tool_input:{command:"git push origin main"}}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

@test "cursor binding probe is recognized on Shell" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"bind-me",transcript_path:"",cwd:$p,tool_input:{command:": nightshift-binding-probe"}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "bind-me" ]
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "cursor" ]
}

# --- the policy files are control files, and elevation is the owner's switch ---

# cursor_shell <project> <command> — the Shell payload this host sends.
cursor_shell() {
  local p="$1" c="$2"
  jq -nc --arg p "$p" --arg c "$c" \
    '{tool_name:"Shell",conversation_id:"cursor-tab",transcript_path:"",cwd:$p,tool_input:{command:$c}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
}

@test "cursor denies rewriting the shift policy, its defaults, and the deadline" {
  p="$(new_project)"
  punch_open "$p"
  for f in shift-policy.json shift-defaults.json deadline; do
    run cursor_shell "$p" "printf 'forged' > .nightshift/$f"
    is_cursor_deny || { echo "path rewrite allowed: $f"; return 1; }
    printf '%s' "$output" | grep -qF "$f" || { echo "deny does not name $f"; return 1; }
    run cursor_shell "$p" "cd .nightshift && rm -f $f"
    is_cursor_deny || { echo "name delete allowed: $f"; return 1; }
  done
}

@test "cursor denies an elevation category by default and honours an allowance" {
  p="$(new_project)"
  punch_open "$p"
  run cursor_shell "$p" "docker compose up -d"
  is_cursor_deny
  printf '%s' "$output" | grep -qF "needs allowance: containers"
  printf '%s' "$output" | grep -qF "elevation.containers.policy"
  jq -nc '{schemaVersion:1,shiftId:"9f2c40ab77e51d63",createdAt:"2026-09-02T02:30:00Z",
    source:"composition",deadlineEpoch:null,verificationLevel:"final",
    toolingPolicy:"existing-tools",
    allowances:[{category:"containers",scope:"category",provenance:"one-shift"}]}' \
    >"$p/.nightshift/shift-policy.json"
  run cursor_shell "$p" "docker compose up -d"
  is_allow
}

@test "cursor leaves a command that only uses the dev stack alone" {
  p="$(new_project)"
  punch_open "$p"
  run cursor_shell "$p" "psql -c 'select 1'"
  is_allow
  run cursor_shell "$p" "git commit -m 'sudo apt-get install jq'"
  is_allow
}
