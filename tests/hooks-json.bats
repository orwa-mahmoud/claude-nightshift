load helpers

# The plugin root can live at a path containing spaces (e.g. a local marketplace checkout);
# an unquoted ${CLAUDE_PLUGIN_ROOT} makes the shell split the path and every hook fails.

@test "hooks.json declares all three hook commands" {
  n="$(jq -r '[.. | .command? // empty] | length' "$BATS_TEST_DIRNAME/../hooks/hooks.json")"
  [ "$n" -eq 3 ]
}

@test "every hooks.json command quotes the plugin root (spaced-path safe)" {
  while IFS= read -r cmd; do
    case "$cmd" in
      '"${CLAUDE_PLUGIN_ROOT}'*'"') : ;;
      *) echo "unquoted command: $cmd"; return 1 ;;
    esac
  done < <(jq -r '.. | .command? // empty' "$BATS_TEST_DIRNAME/../hooks/hooks.json")
}

@test "hook commands run from a directory whose path contains a space" {
  dir="$BATS_TEST_TMPDIR/plugin root with spaces"
  mkdir -p "$dir/hooks"
  cp "$BATS_TEST_DIRNAME/../hooks/clock-out-gate.sh" "$dir/hooks/"
  p="$(new_project)"
  cmd="$(jq -r '.hooks.Stop[0].hooks[0].command' "$BATS_TEST_DIRNAME/../hooks/hooks.json")"
  CLAUDE_PLUGIN_ROOT="$dir" CLAUDE_PROJECT_DIR="$p" run sh -c "$cmd"
  [ "$status" -eq 0 ]
}
