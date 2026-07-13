# Shared helpers for the nightshift hook tests.
HOOKS="$BATS_TEST_DIRNAME/../hooks"

# Create an isolated project with its own git repo and a .nightshift dir. Echoes the path.
new_project() {
  local p="$BATS_TEST_TMPDIR/${1:-proj}"
  mkdir -p "$p/.nightshift"
  git -C "$p" init -q
  git -C "$p" config user.email dev@example.com
  git -C "$p" config user.name tester
  git -C "$p" commit -q --allow-empty -m init
  printf '%s' "$p"
}

# A punch list with one open and one ticked box (TICKED=1, TOTAL=2).
punch_open() { printf '## Items\n- [ ] **1. first.**\n- [x] **2. done.**\n' >"$1/.nightshift/punch-list.md"; }
punch_done() { printf '## Items\n- [x] **1. first.**\n- [x] **2. done.**\n' >"$1/.nightshift/punch-list.md"; }

# gate <project> [ENV=VAL ...]
gate() {
  local p="$1"
  shift
  env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/clock-out-gate.sh"
}

# hardhat_bash <project> <command> [ENV=VAL ...]
hardhat_bash() {
  local p="$1" c="$2"
  shift 2
  jq -nc --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
}

# hardhat_ask <project> [ENV=VAL ...]
hardhat_ask() {
  local p="$1"
  shift
  jq -nc '{tool_name:"AskUserQuestion",tool_input:{}}' |
    env "$@" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh"
}

# spotcheck <file>
spotcheck() {
  jq -nc --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}' |
    bash "$HOOKS/spot-check.sh"
}

is_block() { printf '%s' "$1" | grep -q '"decision":"block"'; }
is_deny() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }
