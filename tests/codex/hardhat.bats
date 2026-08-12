load ../helpers

# helpers.bash anchors its paths one directory up; from tests/codex/ the repo root is two.
HOOKS="$BATS_TEST_DIRNAME/../../plugins/nightshift/hooks"
RULES_TEMPLATE="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json"
CODEX_HOOKS="$HOOKS/codex"

# codex_hardhat_bash <project> <command> [ENV=VAL ...] — the placeholder PreToolUse payload.
codex_hardhat_bash() {
  local p="$1" c="$2"
  shift 2
  jq -nc --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' |
    env "$@" CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
}

# codex_hardhat_ask <project> [ENV=VAL ...]
codex_hardhat_ask() {
  local p="$1"
  shift
  jq -nc '{tool_name:"AskUserQuestion",tool_input:{}}' |
    env "$@" CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
}

@test "the no-push recipe denies push during an active shift" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git push origin main" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push'
  is_deny "$output"
}

@test "a scary-looking command passes when the forbidden list is unset" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "docker compose down"
  is_allow
}

@test "forbidden-commands rule is shift-scoped: inert once every box is ticked" {
  p="$(new_project)"
  punch_done "$p"
  run codex_hardhat_bash "$p" "docker ps" NIGHTSHIFT_FORBIDDEN_COMMANDS='docker'
  is_allow
}

@test "a protected-dir commit is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git commit -m x ai_docs/notes.md" NIGHTSHIFT_PROTECTED_DIRS="ai_docs notes"
  is_deny "$output"
}

@test "a protected-dir git add is denied; unset leaves it free" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git add ai_docs/secret" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_deny "$output"
  run codex_hardhat_bash "$p" "git add ai_docs/secret"
  is_allow
}

@test "commit under the wrong identity is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="owner@nope.io"
  is_deny "$output"
}

@test "commit under the expected identity is allowed" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_EXPECTED_EMAIL="dev@example.com"
  is_allow
}

@test "a staged never-commit pattern is denied when configured" {
  p="$(new_project)"
  punch_open "$p"
  printf 'API_KEY=sk-secret\n' >"$p/leak.txt"
  git -C "$p" add leak.txt
  run codex_hardhat_bash "$p" "git commit -m x" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret|API_KEY"
  is_deny "$output"
}

@test "AskUserQuestion is parked with the template's own message" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p"
  is_deny "$output"
  printf '%s' "$output" | grep -q "park" # the template's toolDeny entry, read from the file
}

@test "an open checkbox outside Items does not activate the codex hardhat" {
  p="$(new_project)"
  printf '%s\n' '- [ ] planning example' '## Items' '- [x] **1. done.**' >"$p/.nightshift/punch-list.md"
  run codex_hardhat_ask "$p"
  is_allow
}

@test "an open checkbox under Items activates the codex hardhat" {
  p="$(new_project)"
  printf '%s\n' '- [x] planning example' '## Items' '- [ ] **1. open.**' >"$p/.nightshift/punch-list.md"
  run codex_hardhat_ask "$p"
  is_deny "$output"
}

@test "open Items remain inert until the codex shift is armed" {
  p="$(new_project)"
  punch_open "$p"
  rm "$p/.nightshift/.shift-armed"
  run codex_hardhat_ask "$p"
  is_allow
}

@test "the toolDeny map words the park denial per tool" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"park it and keep welding"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "park it and keep welding"
}

# Hosted tools never reach the Codex hook path; the arbitrary names an owner can list are MCP
# tools, so the fixture speaks that vocabulary.
@test "a listed tool is denied with its own message; an unlisted one passes" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc '{tool_name:"mcp__web__search",tool_input:{}}' |
    env NIGHTSHIFT_TOOL_RULES='{"mcp__web__search":"no browsing tonight"}' CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "no browsing tonight"
  out="$(jq -nc '{tool_name:"mcp__web__fetch",tool_input:{}}' |
    env NIGHTSHIFT_TOOL_RULES='{"mcp__web__search":"no browsing tonight"}' CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

# Codex delivers file edits as apply_patch with the patch text in tool_input.command; the
# payload's cwd is the documented way a hook finds the project — no env override here.
@test "an apply_patch aimed at the rules file is denied" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg p "$p" '{tool_name:"apply_patch",cwd:$p,tool_input:{command:"*** Begin Patch\n*** Update File: .nightshift/rules.json\n@@\n-old\n+new\n*** End Patch"}}' |
    bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
}

@test "a patch is not a command: forbidden text inside an edit trips no command guard" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg p "$p" '{tool_name:"apply_patch",cwd:$p,tool_input:{command:"*** Begin Patch\n*** Update File: docs/deploy.md\n+run git push only after review\n*** End Patch"}}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' bash "$CODEX_HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

@test "the codex hardhat records its host, and a second tab never overwrites it" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc '{tool_name:"Bash",session_id:"first-tab",transcript_path:"/tmp/a.jsonl",tool_input:{command:"echo hi"}}' |
    CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "first-tab" ]
  [ "$(sed -n 2p "$p/.nightshift/.shift-session")" = "/tmp/a.jsonl" ]
  [ "$(wc -l <"$p/.nightshift/.shift-session")" -eq 5 ] # id, transcript, pid, start time, host
  [ -z "$(sed -n 3p "$p/.nightshift/.shift-session")" ] # no invented process identity
  [ "$(sed -n 5p "$p/.nightshift/.shift-session")" = "codex" ]
  jq -nc '{tool_name:"Bash",session_id:"second-tab",transcript_path:"/tmp/b.jsonl",tool_input:{command:"echo hi"}}' |
    CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "first-tab" ]
}

@test "the no-push recipe holds even when jq is absent (raw sed fallback)" {
  p="$(new_project)"
  punch_open "$p"
  bindir="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$bindir"
  for b in bash grep sed printf cat head tr git env; do
    src="$(command -v "$b")" && ln -sf "$src" "$bindir/$b"
  done
  input="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}')"
  out="$(printf '%s' "$input" | env PATH="$bindir" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
}
