load helpers

# A shift exists because the owner started one. Before v0.7.2 the hooks themselves claimed the
# first session that tripped them while a box was open, so writing a punch list while planning put
# that session on shift — it then could not end its turn and had to either fight the gate or start
# working. `/nightshift:start` writes .shift-armed; nothing else does.

@test "an unarmed site releases the session even with open boxes" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  punch_open "$p"
  run gate "$p"
  is_release
}

@test "an unarmed site never claims a session" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  punch_open "$p"
  run gate "$p"
  [ ! -f "$p/.nightshift/.shift-session" ]
}

@test "an armed site still holds a session with open boxes" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  is_block "$output"
}

@test "arming is what binds the session, so the record appears only once armed" {
  p="$(new_project)"
  punch_open "$p"
  run gate "$p"
  [ -f "$p/.nightshift/.shift-session" ]
}

# The guards are the shift's. Outside one, this is an ordinary session in an ordinary project.
@test "an unarmed site applies no hardhat guard" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  punch_open "$p"
  run hardhat_bash "$p" "git push" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_allow
}

@test "an armed site applies the hardhat guard" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git push" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_deny "$output"
}

# A finished shift stops being a shift, or the guards would follow the project into whatever
# ordinary session opens it next.
@test "ending the shift disarms the site" {
  p="$(new_project)"
  punch_done "$p"
  run gate "$p"
  is_release
  [ ! -f "$p/.nightshift/.shift-armed" ]
}

# Only the Items list is the shift. A checkbox in the contract prose above it is an example, and
# counting it would hold a session over work nobody queued.
@test "a checkbox above the Items heading is not the shift" {
  p="$(new_project)"
  printf '# Punch List\n\n- [ ] this is prose, not work\n\n## Items\n- [x] **1. done.**\n' \
    >"$p/.nightshift/punch-list.md"
  run gate "$p"
  is_release
}

@test "a checkbox below the Items heading is the shift" {
  p="$(new_project)"
  printf '# Punch List\n\n- [ ] this is prose, not work\n\n## Items\n- [ ] **1. real.**\n' \
    >"$p/.nightshift/punch-list.md"
  run gate "$p"
  is_block "$output"
}

# The contract references the Items list in prose. If those references were the literal heading,
# scoping the count would start at the first sentence and the whole contract would read as work.
@test "the shipped template carries the Items heading exactly once" {
  n="$(grep -c '^## Items[[:space:]]*$' "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/punch-list-template.md")"
  [ "$n" -eq 1 ]
  m="$(grep -c '## Items' "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/punch-list-template.md")"
  [ "$m" -eq 1 ]
}

@test "start is the command that arms the gate" {
  s="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/start/SKILL.md"
  grep -qF '$NS/.shift-armed' "$s"
  grep -qF 'Arm the gate' "$s"
}

# hunt and quality both start shifts without the owner typing another command. A start path that
# skips the marker writes the items and holds nothing — the failure is silent and looks like work.
@test "every skill that starts a shift arms the gate" {
  for s in start hunt quality; do
    grep -qF '$NS/.shift-armed' "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/$s/SKILL.md" \
      || { echo "starts a shift without arming: $s"; return 1; }
  done
}

@test "a stop-work order disarms the site even with no punch list" {
  p="$(new_project)"
  : >"$p/.nightshift/STOP"
  run gate "$p"
  is_release
  [ ! -f "$p/.nightshift/.shift-armed" ]
}

@test "status reports whether a shift is running" {
  grep -qF '$NS/.shift-armed' "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/status/SKILL.md"
}
