load ../helpers

HOOKS="$BATS_TEST_DIRNAME/../../plugins/nightshift/hooks"
CURSOR_HOOKS="$HOOKS/cursor"

@test "beforeSubmitPrompt blocks the origin tab and names the resume command" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  run env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/before-submit.sh" \
    "$(jq -nc --arg p "$p" '{conversation_id:"origin-ide",cwd:$p,prompt:"continue"}')"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false' >/dev/null
  printf '%s' "$output" | grep -q 'agent --resume='
  printf '%s' "$output" | grep -q 'live-cli-worker'
  printf '%s' "$output" | grep -q 'terminal'
  printf '%s' "$output" | grep -q 'ask Nightshift to stop'
}

@test "beforeSubmitPrompt lets the origin tab ask Nightshift to stop" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  run env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/before-submit.sh" \
    "$(jq -nc --arg p "$p" '{conversation_id:"origin-ide",cwd:$p,prompt:"ask Nightshift to stop"}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "beforeSubmitPrompt lets another conversation send" {
  p="$(new_project)"
  punch_open "$p"
  printf 'origin-ide\n\n\n\ncursor\n' >"$p/.nightshift/.shift-session"
  printf 'live-cli-worker\n' >"$p/.nightshift/.shift-worker"
  run env CURSOR_PROJECT_DIR="$p" bash "$CURSOR_HOOKS/before-submit.sh" \
    "$(jq -nc --arg p "$p" '{conversation_id:"helper-tab",cwd:$p,prompt:"hi"}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
