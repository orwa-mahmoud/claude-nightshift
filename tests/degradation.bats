load helpers

@test "gate is inert in a project with no punch list" {
  p="$(new_project)"
  run gate "$p"
  [ -z "$output" ]
}

@test "hardhat is inert in a project with no punch list" {
  p="$(new_project)"
  run hardhat_bash "$p" "git push"
  ! is_deny "$output"
  run hardhat_ask "$p"
  ! is_deny "$output"
}

@test "two projects gate independently" {
  a="$(new_project a)"
  punch_open "$a"
  b="$(new_project b)"
  punch_done "$b"
  run gate "$a"
  is_block "$output"
  run gate "$b"
  [ -z "$output" ]
}
