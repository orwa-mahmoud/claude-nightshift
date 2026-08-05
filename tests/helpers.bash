# Shared helpers for the nightshift hook tests.
HOOKS="$BATS_TEST_DIRNAME/../plugin/hooks"
RULES_TEMPLATE="$BATS_TEST_DIRNAME/../plugin/skills/nightshift/references/nightshift-rules-template.json"

# Create an isolated project with its own git repo and a .nightshift dir. Echoes the path.
# The suite must see only the env a test passes explicitly — a developer's own shell (or a
# host that feeds settings env into commands) must never leak NIGHTSHIFT_* into fixtures.
while IFS='=' read -r _v _; do
  case "$_v" in NIGHTSHIFT_*) unset "$_v" ;; esac
done < <(env)

new_project() {
  local p="$BATS_TEST_TMPDIR/${1:-proj}"
  mkdir -p "$p/.nightshift"
  cp "$RULES_TEMPLATE" "$p/.nightshift/rules.json" # as setup does — the one copy of every knob
  : >"$p/.nightshift/.shift-armed"                 # as /nightshift:start does — a shift is running
  git -C "$p" init -q
  git -C "$p" config user.email dev@example.com
  git -C "$p" config user.name tester
  git -C "$p" commit -q --allow-empty -m init
  printf '%s' "$p"
}

# Create the recommended layout: a plain workspace folder that is NOT a repo, holding the code
# repo one level down and .nightshift beside it. Echoes the workspace path.
new_workspace() {
  local w="$BATS_TEST_TMPDIR/${1:-ws}"
  mkdir -p "$w/.nightshift"
  cp "$RULES_TEMPLATE" "$w/.nightshift/rules.json"
  : >"$w/.nightshift/.shift-armed"
  add_repo "$w" repo
  printf '%s' "$w"
}

# add_repo <workspace> <name> — add another git repo one level down.
add_repo() {
  local r="$1/$2"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email dev@example.com
  git -C "$r" config user.name tester
  git -C "$r" commit -q --allow-empty -m init
}

# Give <project>/.nightshift its own local receipts repo, as /nightshift:setup does.
receipts_init() {
  printf 'STOP\n.stall\n.notified\ndeadline\n' >"$1/.nightshift/.gitignore"
  git -C "$1/.nightshift" init -q
  git -C "$1/.nightshift" add -A
  git -C "$1/.nightshift" -c user.name=t -c user.email=t@example.com commit -q -m init
}

# A punch list with one open and one ticked box (TICKED=1, TOTAL=2).
# A background writer races the watchman it is meant to feed: on a loaded runner every sample can
# land before the subshell is even scheduled, so a live session reads as dead and the test fails
# with nothing wrong in the code. Writers signal once they are running; this blocks until then, so
# a red suite always means a real defect.
wait_writer() {
  local flag="$1" i=0
  while [ ! -e "$flag" ]; do
    i=$((i + 1))
    [ "$i" -lt 400 ] || { echo "background writer never started: $flag" >&2; return 1; }
    sleep 0.05
  done
}

punch_open() { printf '## Items\n- [ ] **1. first.**\n- [x] **2. done.**\n' >"$1/.nightshift/punch-list.md"; }
punch_done() { printf '## Items\n- [x] **1. first.**\n- [x] **2. done.**\n' >"$1/.nightshift/punch-list.md"; }

# gate <project> [ENV=VAL ...] — pipes a minimal Stop payload; the gate reads stdin now.
gate() {
  local p="$1"
  shift
  jq -nc '{hook_event_name:"Stop",session_id:"test-shift-session",transcript_path:""}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/clock-out-gate.sh"
}

# hardhat_bash <project> <command> [ENV=VAL ...]
hardhat_bash() {
  local p="$1" c="$2"
  shift 2
  jq -nc --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
}

# hardhat_bash_cwd <project> <cwd> <command> [ENV=VAL ...]
hardhat_bash_cwd() {
  local p="$1" w="$2" c="$3"
  shift 3
  jq -nc --arg c "$c" --arg w "$w" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
}

# hardhat_ask <project> [ENV=VAL ...]
hardhat_ask() {
  local p="$1"
  shift
  jq -nc '{tool_name:"AskUserQuestion",tool_input:{}}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
}

is_block() { printf '%s' "$1" | grep -q '"decision":"block"' && printf '%s' "$1" | jq -e . >/dev/null; }
is_deny() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"' && printf '%s' "$1" | jq -e . >/dev/null; }

# Letting something through is a positive claim, not the absence of a string: the hook must have
# run to completion AND said nothing. `! is_deny "$output"` alone also passes when the hook
# crashed, was never invoked, or exited before reaching the rule under test — which is no
# assertion at all. These read bats' own $status/$output, so call them with no arguments.
is_allow() { [ "$status" -eq 0 ] && [ -z "$output" ]; }
is_release() { [ "$status" -eq 0 ] && [ -z "$output" ]; }
