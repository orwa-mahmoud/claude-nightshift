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

# Give <project>/.nightshift its own local receipts repo, as /nightshift:setup does.
receipts_init() {
  printf 'STOP\n.stall\n.notified\ndeadline\n' >"$1/.nightshift/.gitignore"
  git -C "$1/.nightshift" init -q
  git -C "$1/.nightshift" add -A
  git -C "$1/.nightshift" -c user.name=t -c user.email=t@example.com commit -q -m init
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

is_block() { printf '%s' "$1" | grep -q '"decision":"block"'; }
is_deny() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }
