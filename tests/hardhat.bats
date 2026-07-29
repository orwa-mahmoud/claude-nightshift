load helpers

@test "push is allowed by default during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git push origin main"
  is_allow
}

@test "push is allowed by default when every box is ticked" {
  p="$(new_project)"
  punch_done "$p"
  run hardhat_bash "$p" "git push"
  is_allow
}

@test "allows push when there is no punch list" {
  p="$(new_project)"
  run hardhat_bash "$p" "git push"
  is_allow
}

@test "the no-push recipe denies push during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git push origin main" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_deny "$output"
}

@test "a commit message containing a forbidden word is not a match" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit -m 'push it real good'" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_allow
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
  is_allow
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
  is_allow
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
  is_allow
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
  is_allow
}

@test "the no-push recipe holds even when jq is absent (raw sed fallback)" {
  p="$(new_project)"
  punch_open "$p"
  bindir="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$bindir"
  for b in bash grep sed printf cat head git env; do
    src="$(command -v "$b")" && ln -sf "$src" "$bindir/$b"
  done
  input="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}')"
  out="$(printf '%s' "$input" | env PATH="$bindir" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
}

# A stop-work order is a request, not the ending: the agent keeps working until its next stop
# attempt, so the site rules must stay armed across that window. The gate writes .ended when it
# actually releases, and only that stands them down.

@test "a pending stop-work order keeps the site rules armed" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run hardhat_bash "$p" "git add ai_docs/x" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_deny "$output"
  run hardhat_bash "$p" "git push" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_deny "$output"
  run hardhat_ask "$p"
  is_deny "$output"
}

@test "the site rules stand down once the gate has ended the shift" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/STOP"
  run gate "$p"                       # the release that actually ends it
  [ -f "$p/.nightshift/.ended" ]
  run hardhat_bash "$p" "git add ai_docs/x" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_allow
  run hardhat_bash "$p" "git push" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_allow
}

@test "forbidden-commands pattern denies during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "docker system prune -af" NIGHTSHIFT_FORBIDDEN_COMMANDS='rm -rf|docker|kubectl'
  is_deny "$output"
}

@test "forbidden-commands rule is shift-scoped: inert once every box is ticked" {
  p="$(new_project)"
  punch_done "$p"
  run hardhat_bash "$p" "docker ps" NIGHTSHIFT_FORBIDDEN_COMMANDS='docker'
  is_allow
}

@test "a scary-looking command passes when the forbidden list is unset" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "docker compose down"
  is_allow
}

@test "deny stays valid JSON when the committer email contains a quote" {
  p="$(new_project)"
  punch_open "$p"
  git -C "$p" config user.email 'we"ird@example.com'
  run hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="owner@nope.io"
  is_deny "$output"
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "deny stays valid JSON when a protected dir name contains a quote" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" 'git add we"ird/x' NIGHTSHIFT_PROTECTED_DIRS='we"ird'
  is_deny "$output"
  printf '%s' "$output" | jq -e . >/dev/null
}

# --- the recommended layout: project dir is a plain folder, the repo sits one level down ---

@test "workspace layout: a wrong committer identity is denied" {
  w="$(new_workspace)"
  punch_open "$w"
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="owner@nope.io"
  is_deny "$output"
  # the repo's identity, not whatever the machine's global config happens to hold
  printf '%s' "$output" | grep -q "dev@example.com"
}

@test "workspace layout: the expected committer identity is allowed" {
  w="$(new_workspace)"
  punch_open "$w"
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="dev@example.com"
  is_allow
}

@test "workspace layout: a staged never-commit pattern is denied" {
  w="$(new_workspace)"
  punch_open "$w"
  printf 'API_KEY=sk-secret\n' >"$w/repo/leak.txt"
  git -C "$w/repo" add leak.txt
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret|API_KEY"
  is_deny "$output"
}

@test "workspace layout: a clean staged diff commits" {
  w="$(new_workspace)"
  punch_open "$w"
  printf 'ok\n' >"$w/repo/fine.txt"
  git -C "$w/repo" add fine.txt
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret|API_KEY"
  is_allow
}

@test "the receipts repo is never mistaken for the code repo" {
  w="$(new_workspace)"
  receipts_init "$w"
  punch_open "$w"
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="dev@example.com"
  is_allow
}

@test "the tool's cwd picks the repo when several sit in the workspace" {
  w="$(new_workspace)"
  add_repo "$w" other
  punch_open "$w"
  printf 'API_KEY=sk-secret\n' >"$w/repo/leak.txt"
  git -C "$w/repo" add leak.txt
  run hardhat_bash_cwd "$w" "$w/repo" "git commit -m x" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret"
  is_deny "$output"
}

@test "an undecidable repo fails closed rather than waving the commit through" {
  w="$(new_workspace)"
  add_repo "$w" other
  punch_open "$w"
  run hardhat_bash "$w" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="dev@example.com"
  is_deny "$output"
  printf '%s' "$output" | grep -q "cannot tell which git repository"
}

@test "an unresolvable repo leaves the string-matching guards untouched" {
  w="$BATS_TEST_TMPDIR/bare"
  mkdir -p "$w/.nightshift"
  punch_open "$w"
  run hardhat_bash "$w" "git push" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_deny "$output"
}

# The commit guards resolve `git -C` and `cd X &&`, but --git-dir/--work-tree relocate a commit
# past that resolution — the guard would inspect one repository while the commit lands in
# another. Unverifiable must mean denied, not misread.
@test "a --git-dir commit is denied when a commit guard is configured" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git --git-dir=/somewhere/else/.git commit -m x" \
    NIGHTSHIFT_EXPECTED_EMAIL=dev@example.com
  is_deny "$output"
}

@test "a --work-tree commit is denied when a commit guard is configured" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git --work-tree=/somewhere/else commit -am x" \
    NIGHTSHIFT_NEVER_COMMIT_PATTERNS='SECRET'
  is_deny "$output"
}

@test "--git-dir passes when no commit guard is configured" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git --git-dir=/somewhere/else/.git commit -m x"
  is_allow
}

@test "a commit message mentioning --git-dir is not a match" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit -m 'document the --git-dir flag'" \
    NIGHTSHIFT_EXPECTED_EMAIL=dev@example.com
  is_allow
}

# The identity guard reads the repo's config, and a command line can override identity past that
# read. Every visible override form is denied when an expected identity is configured.
@test "an inline -c user.email override is denied when an identity is expected" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git -c user.email=evil@example.com commit -m x" \
    NIGHTSHIFT_EXPECTED_EMAIL=dev@example.com
  is_deny "$output"
}

@test "an --author override is denied when an identity is expected" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git commit --author='Evil <evil@example.com>' -m x" \
    NIGHTSHIFT_EXPECTED_EMAIL=dev@example.com
  is_deny "$output"
}

@test "a GIT_AUTHOR_EMAIL prefix is denied when an identity is expected" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "GIT_AUTHOR_EMAIL=evil@example.com git commit -m x" \
    NIGHTSHIFT_EXPECTED_EMAIL=dev@example.com
  is_deny "$output"
}

# The README's no-push recipe is `git .*push` so that config injection cannot slip between the
# words. This pins the recipe itself.
@test "the no-push recipe catches git -c k=v push" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git -c http.proxy=x push origin main" \
    NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push'
  is_deny "$output"
}
