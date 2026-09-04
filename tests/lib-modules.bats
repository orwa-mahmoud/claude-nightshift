#!/usr/bin/env bats
# Library layout: lib.sh is the public entry; modules load relative to it.

LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
LIB_DIR="$BATS_TEST_DIRNAME/../plugins/nightshift/lib"

@test "lib.sh loads from a different working directory" {
  other="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$other"
  run bash -c 'cd "$1" && . "$2" && type ns_have_cmd >/dev/null && type ns_workspace_root >/dev/null && type repo_root >/dev/null && type ns_state_kind >/dev/null && type ns_policy_resolve >/dev/null && type ns_pid_alive >/dev/null && type ns_lock >/dev/null && printf loaded' _ "$other" "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" = loaded ]
}

@test "lib.sh may be sourced twice" {
  run bash -c '. "$1" && . "$1" && ns_have_cmd bash && [ "$NS_STATE_VERSION" = 1 ] && printf ok' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "lib.sh loads under set -u" {
  run bash -c 'set -u; . "$1"; type ns_lock >/dev/null; printf ok' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "callers keep sourcing lib.sh rather than individual modules" {
  root="$BATS_TEST_DIRNAME/../plugins/nightshift"
  for mod in common paths git state policy process ownership; do
    if grep -R --include='*.sh' -F "lib/${mod}.sh" "$root/hooks" "$root/runtime"; then
      echo "hook or runtime sourced lib/${mod}.sh directly"
      return 1
    fi
  done
  grep -R --include='*.sh' -lF 'lib/lib.sh' "$root/hooks" "$root/runtime" | grep -q .
}

@test "lib.sh is a loader; each public function has one implementation" {
  if grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$LIB"; then
    return 1
  fi
  for fn in ns_workspace_root repo_root ns_lock ns_state_kind ns_policy_resolve ns_pid_alive valid_ere; do
    n="$(grep -hE "^${fn}\(\) \{" "$LIB_DIR"/*.sh | wc -l | tr -d ' ')"
    [ "$n" -eq 1 ] || { echo "expected one $fn, got $n"; return 1; }
  done
}
