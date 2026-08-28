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

@test "cursor binding probe is recognized on Shell" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"bind-me",transcript_path:"",cwd:$p,tool_input:{command:": nightshift-binding-probe"}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "bind-me" ]
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "cursor" ]
}
