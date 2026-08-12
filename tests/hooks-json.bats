load helpers

# The plugin root can live at a path containing spaces (e.g. a local marketplace checkout);
# an unquoted ${CLAUDE_PLUGIN_ROOT} makes the shell split the path and every hook fails.

@test "hooks.json declares every hook command" {
  n="$(jq -r '[.. | .command? // empty] | length' "$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/hooks.json")"
  [ "$n" -eq 5 ]
}

@test "every hooks.json command quotes the plugin root (spaced-path safe)" {
  while IFS= read -r cmd; do
    case "$cmd" in
      '"${CLAUDE_PLUGIN_ROOT}'*'"') : ;;
      *) echo "unquoted command: $cmd"; return 1 ;;
    esac
  done < <(jq -r '.. | .command? // empty' "$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/hooks.json")
}

@test "hook commands run from a directory whose path contains a space" {
  dir="$BATS_TEST_TMPDIR/plugin root with spaces"
  mkdir -p "$dir/hooks"
  cp "$BATS_TEST_DIRNAME"/../plugins/nightshift/hooks/*.sh "$dir/hooks/"
  p="$(new_project)"
  cmd="$(jq -r '.hooks.Stop[0].hooks[0].command' "$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/hooks.json")"
  CLAUDE_PLUGIN_ROOT="$dir" CLAUDE_PROJECT_DIR="$p" run sh -c "printf '{}' | $cmd"
  [ "$status" -eq 0 ]
}

# A path or matcher that no longer resolves disables a guard in total silence: the hook simply
# never runs, and every other test — which invokes the scripts directly — stays green. These
# assert the wiring itself, which is the only thing standing between the config and no guard.

@test "every hooks.json command points at a file that exists" {
  root="$BATS_TEST_DIRNAME/../plugins/nightshift"
  while IFS= read -r cmd; do
    path="${cmd%\"}"
    path="${path#\"}"
    path="${path/\$\{CLAUDE_PLUGIN_ROOT\}/$root}"
    [ -f "$path" ] || { echo "hooks.json names a file that does not exist: $path"; return 1; }
  done < <(jq -r '.. | .command? // empty' "$root/hooks/hooks.json")
}

@test "hooks.json registers the events and matchers the guards rely on" {
  f="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/hooks.json"
  [ "$(jq -r '[.hooks.PreToolUse[].matcher] | sort | join(",")' "$f")" = "AskUserQuestion,Bash,Edit|Write|MultiEdit|NotebookEdit" ]
  [ "$(jq -r '.hooks.Stop | length' "$f")" -eq 1 ]
  [ "$(jq -r '.hooks.SessionEnd | length' "$f")" -eq 1 ]
  jq -e '.hooks.SessionEnd[0].hooks[0].command | test("session-end")' "$f" >/dev/null
  jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash")   | .hooks[0].command | test("hardhat")'       "$f" >/dev/null
  jq -e '.hooks.PreToolUse[] | select(.matcher=="AskUserQuestion") | .hooks[0].command | test("hardhat")' "$f" >/dev/null
  jq -e '.hooks.PreToolUse[] | select(.matcher=="Edit|Write|MultiEdit|NotebookEdit") | .hooks[0].command | test("hardhat")' "$f" >/dev/null
  jq -e '.hooks.Stop[0].hooks[0].command | test("clock-out-gate")' "$f" >/dev/null
}

@test "the hooks wired in hooks.json actually decide when driven through their own config" {
  root="$BATS_TEST_DIRNAME/../plugins/nightshift"
  p="$(new_project)"
  punch_open "$p"
  cmd="$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[0].command' "$root/hooks/hooks.json")"
  out="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}' |
    CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$p" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' sh -c "$cmd")"
  is_deny "$out"

  cmd="$(jq -r '.hooks.Stop[0].hooks[0].command' "$root/hooks/hooks.json")"
  out="$(printf '{}' | CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$p" sh -c "$cmd")"
  is_block "$out"
}
