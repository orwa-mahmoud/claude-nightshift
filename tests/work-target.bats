load helpers

LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"

resolve_target() {
  bash -c '. "$1"; ns_work_target "$2"' _ "$LIB" "$1"
}

@test "workspace repository resolves to itself" {
  p="$(new_project target-self)"
  expected="$(git -C "$p" rev-parse --show-toplevel)"
  run resolve_target "$p"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "parent workspace resolves and persists its single child repository" {
  w="$(new_workspace target-parent)"
  expected="$(git -C "$w/repo" rev-parse --show-toplevel)"
  run resolve_target "$w"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]

  bash -c '. "$1"; ns_record_work_target "$2" "$3"' _ "$LIB" "$w" "$w/repo"
  [ "$(cat "$w/.nightshift/work-target")" = "$expected" ]
}

@test "several child repositories require an explicit persisted target" {
  w="$(new_workspace target-many)"
  add_repo "$w" second
  run resolve_target "$w"
  [ "$status" -eq 2 ]

  bash -c '. "$1"; ns_record_work_target "$2" "$3"' _ "$LIB" "$w" "$w/second"
  expected="$(git -C "$w/second" rev-parse --show-toplevel)"
  run resolve_target "$w"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "gate progress follows the persisted target after resume" {
  w="$(new_workspace target-resume)"
  add_repo "$w" second
  punch_open "$w"
  bash -c '. "$1"; ns_record_work_target "$2" "$3"' _ "$LIB" "$w" "$w/second"

  run gate "$w" NIGHTSHIFT_STALL_MAX=2 NIGHTSHIFT_STALL_WARN=1
  is_block "$output"
  git -C "$w/second" commit -q --allow-empty -m progress
  run gate "$w" NIGHTSHIFT_STALL_MAX=2 NIGHTSHIFT_STALL_WARN=1
  is_block "$output"
  [ ! -e "$w/STOP" ]
}

@test "setup and start pin the same persisted work target contract" {
  setup_skill="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"
  start_skill="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/start/SKILL.md"
  grep -qF '.nightshift/work-target' "$setup_skill"
  grep -qF '.nightshift/work-target' "$start_skill"
  grep -qF 'several child repositories' "$setup_skill"
  grep -qF 'refuse to arm' "$start_skill"
}
