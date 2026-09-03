#!/usr/bin/env bats
# Strict-subset reader for rules.json — no jq or python3 on the arm/deny path.

bats_require_minimum_version 1.5.0

load helpers

ROOT="$BATS_TEST_DIRNAME/.."
LIB="$ROOT/plugins/nightshift/lib/lib.sh"
TEMPLATE="$ROOT/plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
DOCTOR="$ROOT/plugins/nightshift/runtime/doctor.sh"
STATUS="$ROOT/plugins/nightshift/runtime/status.sh"
HOOKS="$ROOT/plugins/nightshift/hooks"

no_json_bin() {
  build_toolset_bin "$1" bash sh sed tr sort grep cut awk cat mktemp uname date \
    rm mv cp ln printf head tail wc find test dirname basename cksum env true false
}

@test "the shipped template is the accepted shape" {
  run bash -c '. "$1"; ns_rules_load "$2" && rule "$3" watchMinutes "" && printf x' \
    _ "$LIB" "$TEMPLATE" "$(dirname "$TEMPLATE")/../.."
  # rule() wants workspace/.nightshift/rules.json — load the template path directly.
  run bash -c '. "$1"; ns_rules_load "$2" && ns_rules_get "$2" watchMinutes' _ "$LIB" "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" = 10 ]
  run bash -c '. "$1"; ns_rules_load "$2" && ns_rules_get "$2" receiptsAutoCommit' _ "$LIB" "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" = false ]
  run bash -c '. "$1"; ns_rules_tool_state "$2" AskUserQuestion' _ "$LIB" "$TEMPLATE"
  [ "$status" -eq 0 ]
  [ "$output" = deny ]
}

@test "comments, trailing commas, unknown types, and unexpected nesting fail closed" {
  dir="$BATS_TEST_TMPDIR/bad"
  mkdir -p "$dir"
  printf '{ "watchMinutes": 10, }\n' >"$dir/trailing.json"
  printf '{ "watchMinutes": 10 }\n// comment\n' >"$dir/comment.json"
  printf '{ "watchMinutes": null }\n' >"$dir/null.json"
  printf '{ "watchMinutes": 1.5 }\n' >"$dir/float.json"
  printf '{ "elevation": { "sudo": "deny" } }\n' >"$dir/nest.json"
  printf '{not json\n' >"$dir/broken.json"

  reject() {
    run bash -c '. "$1"; ns_rules_load "$2" && exit 0; printf "%s\n" "$NS_RULES_ERR"; exit 1' \
      _ "$LIB" "$1"
  }
  reject "$dir/trailing.json"
  [ "$status" -eq 1 ]
  [ "$output" = "trailing comma" ]

  reject "$dir/comment.json"
  [ "$status" -eq 1 ]
  [ "$output" = comment ]

  reject "$dir/null.json"
  [ "$status" -eq 1 ]
  [ "$output" = "unknown type" ]

  reject "$dir/float.json"
  [ "$status" -eq 1 ]
  [ "$output" = "unknown type" ]

  reject "$dir/nest.json"
  [ "$status" -eq 1 ]
  [ "$output" = "unexpected nesting" ]

  reject "$dir/broken.json"
  [ "$status" -eq 1 ]
  [ "$output" = "not a JSON object" ]
}

@test "Start can resolve rules and hardhat can deny sudo without jq or python3" {
  p="$(new_project rules-nojq)"
  punch_open "$p"
  bin="$(no_json_bin rules-nojq-bin)"
  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash -c '. "$1"; ns_policy_resolve_table "$2"' _ "$LIB" "$p"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'watchMinutes=10 (rules, permanent)'
  printf '%s\n' "$output" | grep -qxF 'elevation.sudo=deny (rules, permanent)'
  printf '%s\n' "$output" | grep -qxF 'verificationLevel=none (built-in, -)'
  ! printf '%s\n' "$output" | grep -qF 'jq or python3'

  out="$(jq -nc --arg c 'sudo id' '{tool_name:"Bash",tool_input:{command:$c}}' |
    env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/hardhat.sh")"
  is_deny "$out"
  printf '%s' "$out" | grep -qF "needs allowance: sudo"
  ! printf '%s' "$out" | grep -qF 'jq or python3'
}

@test "malformed rules refuse to arm with a named reason" {
  p="$(new_project rules-malformed)"
  printf '{ "watchMinutes": 10, }\n' >"$p/.nightshift/rules.json"
  bin="$(no_json_bin rules-malformed-bin)"
  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash -c '. "$1"; ns_rules_check "$2"' _ "$LIB" "$p"
  [ "$status" -eq 1 ]
  [ "$output" = "trailing comma" ]

  grep -qF 'ns_rules_check' "$START"
  grep -qF 'refuse to arm' "$START"
  grep -qF 'named reason' "$START"
  ! grep -qF 'install jq or python3' "$START"
  ! grep -qiE '\bawk\b' "$START"
}

@test "Doctor and Status never ask to install jq or python3" {
  ! grep -qF 'install jq or python3' "$DOCTOR"
  ! grep -qF 'jq or python3 required' "$STATUS"
  p="$(new_project rules-doctor)"
  punch_open "$p"
  bin="$(no_json_bin rules-doctor-bin)"
  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash "$DOCTOR" --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'rules.json is a JSON object'
  printf '%s' "$output" | grep -qF 'watchMinutes=10 (rules, permanent)'
  ! printf '%s' "$output" | grep -qF 'jq or python3'
}

@test "the reader agrees on the default awk and on gawk when present" {
  p="$(new_project rules-awk)"
  cp "$TEMPLATE" "$p/.nightshift/rules.json"
  def="$(bash -c '. "$1"; ns_rules_facts "$2/.nightshift/rules.json"' _ "$LIB" "$p")"
  [ -n "$def" ]
  printf '%s\n' "$def" | grep -q $'^r\twatchMinutes\t1\t10$'
  if command -v gawk >/dev/null 2>&1; then
    gawk_out="$(env NS_RULES_AWK=gawk bash -c '. "$1"; ns_rules_facts "$2/.nightshift/rules.json"' _ "$LIB" "$p")"
    [ "$def" = "$gawk_out" ]
    env NS_RULES_AWK=gawk bash -c '
      . "$1"
      printf "{ \"watchMinutes\": 10, }\n" >"$2/bad.json"
      ns_rules_load "$2/bad.json"
      printf "%s\n" "$NS_RULES_ERR"
    ' _ "$LIB" "$BATS_TEST_TMPDIR" | grep -qxF 'trailing comma'
  fi
}

@test "owner-facing docs never name the reader implementation" {
  ! grep -qiE '\bawk\b' "$ROOT/docs/how-it-works.md"
  ! grep -qiE '\bawk\b' "$ROOT/docs/knobs.md"
  ! grep -qiE '\bawk\b' "$START"
  ! grep -qiE '\bawk\b' "$ROOT/plugins/nightshift/skills/doctor/SKILL.md"
  ! grep -qiE '\bawk\b' "$ROOT/plugins/nightshift/skills/status/SKILL.md"
}
