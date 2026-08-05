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
  : >"$w/.nightshift/.shift-armed"
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

# The no-push recipe in docs/knobs.md is `git .*push` so that config injection cannot slip between the
# words. This pins the recipe itself.
@test "the no-push recipe catches git -c k=v push" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_bash "$p" "git -c http.proxy=x push origin main" \
    NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push'
  is_deny "$output"
}

# The shift records its own identity: the first session to work under an active shift writes
# .shift-session, and a second tab never overwrites it — the watchman must know WHICH
# conversation to read and revive, not guess at the newest.
@test "the first working session records itself and is never overwritten" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc '{tool_name:"Bash",session_id:"first-tab",transcript_path:"/tmp/a.jsonl",tool_input:{command:"echo hi"}}' |
    CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "first-tab" ]
  jq -nc '{tool_name:"Bash",session_id:"second-tab",transcript_path:"/tmp/b.jsonl",tool_input:{command:"echo hi"}}' |
    CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "first-tab" ]
}

@test "no active shift means no session record" {
  p="$(new_project)"
  punch_done "$p"
  jq -nc '{tool_name:"Bash",session_id:"s1",transcript_path:"",tool_input:{command:"echo hi"}}' |
    CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
  [ ! -f "$p/.nightshift/.shift-session" ]
}

# v0.5.2: the record carries process identity — the claude ancestor's pid and start time, found
# by walking the hook's own ancestry. A stubbed ps makes the walk deterministic here.
@test "the record claims the claude ancestor's pid and start time" {
  p="$(new_project)"
  punch_open "$p"
  stub="$BATS_TEST_TMPDIR/pidbin"
  mkdir -p "$stub"
  cat >"$stub/ps" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *lstart*) echo "  Mon Jan  1 00:00:00 2026  " ;;
  *comm*) echo "claude" ;;
  *) echo 1 ;;
esac
STUB
  chmod +x "$stub/ps"
  jq -nc '{tool_name:"Bash",session_id:"pid-tab",transcript_path:"/tmp/t.jsonl",tool_input:{command:"echo hi"}}' |
    PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "pid-tab" ]
  sed -n 3p "$p/.nightshift/.shift-session" | grep -qE '^[0-9]+$'
  [ "$(sed -n 4p "$p/.nightshift/.shift-session")" = "Mon Jan  1 00:00:00 2026" ]
}

@test "no claude ancestor leaves the pid lines empty, never breaks the record" {
  p="$(new_project)"
  punch_open "$p"
  jq -nc '{tool_name:"Bash",session_id:"bare-tab",transcript_path:"",tool_input:{command:"echo hi"}}' |
    CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
  [ "$(sed -n 1p "$p/.nightshift/.shift-session")" = "bare-tab" ]
  [ "$(wc -l <"$p/.nightshift/.shift-session")" -eq 4 ]
  [ -z "$(sed -n 3p "$p/.nightshift/.shift-session")" ]
}

# The claim is an exclusive create: two racing first sessions cannot interleave — one record
# lands whole, id and transcript from the same writer.
@test "two racing identity claims land exactly one whole record" {
  for round in 1 2 3; do
    p="$(new_project "race$round")"
    punch_open "$p"
    jq -nc '{tool_name:"Bash",session_id:"race-a",transcript_path:"/tmp/a.jsonl",tool_input:{command:"echo hi"}}' |
      CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh" &
    one=$!
    jq -nc '{tool_name:"Bash",session_id:"race-b",transcript_path:"/tmp/b.jsonl",tool_input:{command:"echo hi"}}' |
      CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh" &
    two=$!
    wait "$one" "$two"
    [ "$(wc -l <"$p/.nightshift/.shift-session")" -eq 4 ]
    sid="$(sed -n 1p "$p/.nightshift/.shift-session")"
    tpath="$(sed -n 2p "$p/.nightshift/.shift-session")"
    case "$sid" in
      race-a) [ "$tpath" = "/tmp/a.jsonl" ] ;;
      race-b) [ "$tpath" = "/tmp/b.jsonl" ] ;;
      *) false ;;
    esac
  done
}

# ---- the site rules bind the shift's session; other conversations keep their tools ----

@test "another conversation is untouched by the site rules" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\n' >"$p/.nightshift/.shift-session"
  out="$(jq -nc '{tool_name:"AskUserQuestion",tool_input:{},session_id:"helper-tab"}' |
    env CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  [ -z "$out" ] # the question is the helper's to ask
  out="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push origin main"},session_id:"helper-tab"}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  [ -z "$out" ] # the owner's other tab pushes if the owner pleases
}

@test "the shift session itself still answers to the site rules" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\n' >"$p/.nightshift/.shift-session"
  out="$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push origin main"},session_id:"the-shift"}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
}

@test "a tool call without a session id keeps the conservative reading — rules apply" {
  p="$(new_project)"
  punch_open "$p"
  printf 'the-shift\n\n\n\n' >"$p/.nightshift/.shift-session"
  run hardhat_bash "$p" "git push origin main" NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push'
  is_deny "$output"
}

# ---- the tool rules map: one knob, per-tool messages, owner-only (env, fixed at start) ----

@test "the map words the park denial per tool" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_ask "$p" NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"park it and keep welding"}'
  is_deny "$output"
  printf '%s' "$output" | grep -q "park it and keep welding"
}

@test "an empty message in the map lifts the question rule" {
  p="$(new_project)"
  punch_open "$p"
  run hardhat_ask "$p" NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":""}'
  is_allow
}

@test "a listed tool is denied with its own message; an unlisted one passes" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc '{tool_name:"WebSearch",tool_input:{}}' |
    env NIGHTSHIFT_TOOL_RULES='{"WebSearch":"no browsing tonight"}' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "no browsing tonight"
  out="$(jq -nc '{tool_name:"WebFetch",tool_input:{}}' |
    env NIGHTSHIFT_TOOL_RULES='{"WebSearch":"no browsing tonight"}' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  [ -z "$out" ]
}

@test "a map that is not a JSON object denies loudly instead of waving through" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc '{tool_name:"WebSearch",tool_input:{}}' |
    env NIGHTSHIFT_TOOL_RULES='not json' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "toolDeny"
}

@test "the map's default Ask rule holds even without jq" {
  p="$(new_project)"
  punch_open "$p"
  nojq="$BATS_TEST_TMPDIR/nojq-rules"
  mkdir -p "$nojq"
  for t in bash grep sed cat printf env sh ps dirname head tail tr awk date mkdir rm cut wc sleep kill git; do
    command -v "$t" >/dev/null && ln -sf "$(command -v "$t")" "$nojq/$t"
  done
  out="$(jq -nc '{tool_name:"AskUserQuestion",tool_input:{}}' |
    env PATH="$nojq" NIGHTSHIFT_TOOL_RULES='{"AskUserQuestion":"welded shut"}' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "welded shut"
}

# ---- one copy: the rules file IS the config; env is only a session-start override ----

@test "the guards read the rules file directly — no env needed" {
  p="$(new_project)"
  punch_open "$p"
  printf '{"forbiddenCommands":"git .*push","toolDeny":{"AskUserQuestion":"file-map says park"}}\n' >"$p/.nightshift/rules.json"
  run hardhat_bash "$p" "git push origin main"
  is_deny "$output"
  run hardhat_ask "$p"
  is_deny "$output"
  printf '%s' "$output" | grep -q "file-map says park"
}

@test "an env var overrides the file for the session" {
  p="$(new_project)"
  punch_open "$p"
  printf '{"forbiddenCommands":"git .*push"}\n' >"$p/.nightshift/rules.json"
  run hardhat_bash "$p" "git push origin main" NIGHTSHIFT_FORBIDDEN_COMMANDS="never-matches-anything"
  is_allow
}

@test "the night never rewrites its own rules — file tools and commands alike" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc --arg fp "$p/.nightshift/rules.json" '{tool_name:"Write",tool_input:{file_path:$fp,content:"{}"}}' |
    env CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -q "never rewrites its own rules"
  run hardhat_bash "$p" "echo '{}' > .nightshift/rules.json"
  is_deny "$output"
}

@test "file tools are free of the command guards — and free entirely outside a shift" {
  p="$(new_project)"
  punch_open "$p"
  out="$(jq -nc '{tool_name:"Write",tool_input:{file_path:"/tmp/notes.md",content:"how to git push"}}' |
    env NIGHTSHIFT_FORBIDDEN_COMMANDS='git .*push' CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  [ -z "$out" ] # a file's content is not a command
  q="$(new_project other)"
  out="$(jq -nc --arg fp "$q/.nightshift/rules.json" '{tool_name:"Write",tool_input:{file_path:$fp,content:"{}"}}' |
    env CLAUDE_PROJECT_DIR="$q" bash "$HOOKS/hardhat.sh")"
  [ -z "$out" ] # no shift, no rules — the owner edits freely
}

# No readable rules is a fault, never an opening: the question still parks, loudly.
@test "a missing rules file still parks questions and names the repair" {
  p="$(new_project)"
  punch_open "$p"
  rm "$p/.nightshift/rules.json"
  run hardhat_ask "$p"
  is_deny "$output"
  printf '%s' "$output" | grep -q "re-run /nightshift:setup"
}
