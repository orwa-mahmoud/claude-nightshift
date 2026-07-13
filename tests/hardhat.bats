load helpers

@test "denies push while a box is open (punch-list-scoped)" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git push origin main"
  is_deny "$output"
}

@test "denies push when every box is ticked (punch-list-scoped)" {
  p="$(new_project)"
  punch_done "$p"
  run hardhat_bash "$p" "git push"
  is_deny "$output"
}

@test "denies push under a STOP marker (punch-list-scoped)" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run hardhat_bash "$p" "git push"
  is_deny "$output"
}

@test "allows push when there is no punch list" {
  p="$(new_project)"
  run hardhat_bash "$p" "git push"
  ! is_deny "$output"
}

@test "a commit message containing the word push is allowed" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit -m 'push it real good'"
  ! is_deny "$output"
}

@test "protected-dir git write is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git add ai_docs/secret" NIGHTSHIFT_PROTECTED_DIRS="ai_docs notes"
  is_deny "$output"
}

@test "protected-dir check is skipped when unset" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git add ai_docs/secret"
  ! is_deny "$output"
}

@test "commit under the wrong identity is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="owner@nope.io"
  is_deny "$output"
}

@test "commit under the expected identity is allowed" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="dev@example.com"
  ! is_deny "$output"
}

@test "a staged never-commit pattern is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  printf 'API_KEY=sk-secret\n' >"$p/leak.txt"
  git -C "$p" add leak.txt
  run hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret|API_KEY"
  is_deny "$output"
}

@test "never-commit pattern check is skipped when unset" {
  p="$(new_project)"
  punch_open "$p"
  printf 'API_KEY=sk-secret\n' >"$p/leak.txt"
  git -C "$p" add leak.txt
  run hardhat_bash "$p" "git commit -m x"
  ! is_deny "$output"
}

@test "AskUserQuestion is denied during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_ask "$p"
  is_deny "$output"
}

@test "AskUserQuestion is allowed with no active shift" {
  p="$(new_project)"
  punch_done "$p"
  run hardhat_ask "$p"
  ! is_deny "$output"
}

@test "denies push even when jq is absent (raw sed fallback)" {
  p="$(new_project)"
  punch_open "$p"
  bindir="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$bindir"
  for b in bash grep sed printf cat head git env; do
    src="$(command -v "$b")" && ln -sf "$src" "$bindir/$b"
  done
  input="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}')"
  out="$(printf '%s' "$input" | env PATH="$bindir" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
}

@test "shift-scoped rules are inert under a STOP marker but push stays denied" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run hardhat_bash "$p" "git add ai_docs/x" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  ! is_deny "$output"
  run hardhat_bash "$p" "git push"
  is_deny "$output"
}
