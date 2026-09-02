#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "run-shard partitions every bats file exactly once across six shards" {
  total=6
  all="$(
    cd "$REPO_ROOT" && find tests -name '*.bats' | sort
  )"
  [ -n "$all" ]

  merged=""
  for s in $(seq 1 "$total"); do
    shard_files="$(
      cd "$REPO_ROOT" && tests/run-shard.sh "$s" "$total" --list
    )"
    [ -n "$shard_files" ]
    merged="${merged}${shard_files}"$'\n'
  done

  [ "$(printf '%s\n' "$all" | wc -l | tr -d ' ')" -eq "$(printf '%s\n' "$merged" | sed '/^$/d' | wc -l | tr -d ' ')" ]
  [ "$(printf '%s\n' "$merged" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')" -eq "$(printf '%s\n' "$all" | wc -l | tr -d ' ')" ]
  diff -u <(printf '%s\n' "$all") <(printf '%s\n' "$merged" | sed '/^$/d' | sort)
}

@test "run-shard rejects out-of-range shard numbers" {
  run bash "$REPO_ROOT/tests/run-shard.sh" 0 6 --list
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/tests/run-shard.sh" 7 6 --list
  [ "$status" -eq 2 ]
}
