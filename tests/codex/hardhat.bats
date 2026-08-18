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

# codex_hardhat_ask <project> [tool-name] [ENV=VAL ...]
codex_hardhat_ask() {
  local p="$1"
  shift
  local tool="AskUserQuestion"
  if [ "${1:-}" = "AskUserQuestion" ] || [ "${1:-}" = "request_user_input" ]; then
    tool="$1"
    shift
  fi
  jq -nc --arg tool "$tool" '{tool_name:$tool,tool_input:{}}' |
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

@test "request_user_input is parked with its native template entry" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" request_user_input
  is_deny "$output"
  printf '%s' "$output" | grep -q "park"
}

@test "request_user_input remains available outside an armed shift" {
  p="$(new_project)"
  punch_open "$p"
  rm "$p/.nightshift/.shift-armed"
  run codex_hardhat_ask "$p" request_user_input
  is_allow
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

@test "the AskUserQuestion compatibility alias reads its exact key" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" \
    NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"alias park","request_user_input":"native park"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "alias park"
}

@test "request_user_input uses its own host-native message" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" request_user_input \
    NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"alias park","request_user_input":"native park"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "native park"
}

@test "an empty request_user_input message allows Codex to ask" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" request_user_input \
    NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"alias park","request_user_input":""}'
  is_allow
}

@test "a missing Codex question key is a configuration error, not an alias fallback" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_ask "$p" request_user_input \
    NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"must not leak across hosts"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "missing the required 'request_user_input' entry"
  printf '%s' "$output" | grep -qF '/nightshift:setup'
  printf '%s' "$output" | grep -qF 'ask Nightshift to set up on Codex'
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
  out="$(jq -nc '{tool_name:"mcp__web__fetch",tool_input:{query:"how to git push"}}' |
    env NIGHTSHIFT_TOOL_RULES='{"mcp__web__search":"no browsing tonight"}' \
      NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

@test "a nested question-tool name cannot bypass the canonical caller rule" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc '{tool_name:"mcp__router__invoke",tool_input:{tool_name:"request_user_input"}}' |
    env NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"","request_user_input":"","mcp__router__invoke":"router blocked"}' \
      CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "router blocked"
}

@test "toolDeny can block canonical Codex Bash calls" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "git status" \
    NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"","request_user_input":"","Bash":"no shell tonight"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "no shell tonight"
}

# Codex delivers file edits as apply_patch with the patch text in tool_input.command; the
# payload's cwd is the documented way a hook finds the project — no env override here.
@test "neverCommitPatterns inspects a pathspec commit on Codex" {
  p="$(new_project)"
  punch_open "$p"
  printf 'clean\n' >"$p/leak.txt"
  git -C "$p" add leak.txt
  git -C "$p" commit -q -m seed
  printf 'API_KEY=sk-secret\n' >"$p/leak.txt"
  run codex_hardhat_bash "$p" "git commit -m pathspec-bypass leak.txt" NIGHTSHIFT_NEVER_COMMIT_PATTERNS="sk-secret"
  is_deny "$output"
}

@test "protectedDirs inspects Git paths on Codex too" {
  p="$(new_project)"
  punch_open "$p"
  mkdir -p "$p/ai_docs"
  printf 'secret\n' >"$p/ai_docs/secret.txt"
  run codex_hardhat_bash "$p" "git add -A" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_deny "$output"
  git -C "$p" add ai_docs/secret.txt
  run codex_hardhat_bash "$p" "git commit -m protected-bypass" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_deny "$output"
  git -C "$p" add ai_docs/secret.txt
  git -C "$p" commit -q -m protected
  rm -f "$p/ai_docs/secret.txt"
  run codex_hardhat_bash "$p" "git add -A" NIGHTSHIFT_PROTECTED_DIRS="ai_docs"
  is_deny "$output"
}

@test "the bound worker cannot unlink the armed marker or delete the punch list" {
  p="$(new_project)"
  punch_open "$p"
  run codex_hardhat_bash "$p" "unlink .nightshift/.shift-armed"
  is_deny "$output"
  run codex_hardhat_bash "$p" "cd .nightshift && unlink .shift-armed"
  is_deny "$output"
  run codex_hardhat_bash "$p" "cd .nightshift && touch STOP"
  is_deny "$output"
  run codex_hardhat_bash "$p" "rm .nightshift/punch-list.md"
  is_deny "$output"
}

@test "an apply_patch aimed at the rules file is denied" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg p "$p" '{tool_name:"apply_patch",cwd:$p,tool_input:{command:"*** Begin Patch\n*** Update File: .nightshift/rules.json\n@@\n-old\n+new\n*** End Patch"}}' |
    bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
}

@test "an MCP writer aimed at the rules file is denied" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg p "$p" '{tool_name:"mcp__filesystem__write_file",cwd:$p,tool_input:{path:($p + "/.nightshift/rules.json"),content:"{}"}}' |
    bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
}

@test "a patch is not a command: forbidden text inside an edit trips no command guard" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg p "$p" '{tool_name:"apply_patch",cwd:$p,tool_input:{command:"*** Begin Patch\n*** Update File: docs/deploy.md\n+document .nightshift/rules.json and run git push only after review\n*** End Patch"}}' |
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

@test "a passive catch-all tool cannot claim the Codex shift session" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc '{tool_name:"mcp__filesystem__read_file",session_id:"helper-tab",tool_input:{path:"README.md"}}' |
    CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
  [ ! -f "$p/.nightshift/.shift-session" ]
  jq -nc '{tool_name:"Bash",session_id:"shift-tab",tool_input:{command:"pwd"}}' |
    CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "shift-tab" ]
}

@test "the no-push recipe holds when jq is absent and Python parses tool rules" {
  p="$(new_project)"
  punch_open "$p"
  bindir="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$bindir"
  for b in bash grep sed printf cat head tr git env python3; do
    src="$(command -v "$b")" && ln -sf "$src" "$bindir/$b"
  done
  input="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}')"
  out="$(printf '%s' "$input" | env PATH="$bindir" NIGHTSHIFT_FORBIDDEN_COMMANDS='git push' CODEX_PROJECT_DIR="$p" bash "$CODEX_HOOKS/hardhat.sh")"
  is_deny "$out"
}
