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

@test "cursor binding probe is recognized on Shell" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc --arg p "$p" \
    '{tool_name:"Shell",conversation_id:"bind-me",transcript_path:"",cwd:$p,tool_input:{command:": nightshift-binding-probe"}}' |
    env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "bind-me" ]
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "cursor" ]
}
