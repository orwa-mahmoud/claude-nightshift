#!/usr/bin/env bash
# Run one shard of the bats suite. Shards partition tests/**/*.bats round-robin.
# Usage: tests/run-shard.sh SHARD TOTAL [--list]
#   SHARD  — 1-indexed shard number
#   TOTAL  — number of shards (CI matrix size or local parallel job count)
#   --list — print assigned files and exit (no bats run)
set -euo pipefail

shard="${1:?shard number required (1-indexed)}"
total="${2:?total shards required}"
list_only=0
if [ "${3:-}" = --list ]; then
  list_only=1
fi

case "$shard$total" in
  *[!0-9]*)
    echo "usage: tests/run-shard.sh SHARD TOTAL [--list]" >&2
    exit 2
    ;;
esac

if [ "$shard" -lt 1 ] || [ "$shard" -gt "$total" ]; then
  echo "shard must be 1..$total" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find tests -name '*.bats' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "no bats tests yet" >&2
  exit 0
fi

selected=()
idx=0
for f in "${files[@]}"; do
  if [ $(( idx % total )) -eq $(( shard - 1 )) ]; then
    selected+=("$f")
  fi
  idx=$(( idx + 1 ))
done

if [ "$list_only" -eq 1 ]; then
  printf '%s\n' "${selected[@]}"
  exit 0
fi

echo "shard $shard/$total: ${#selected[@]} file(s)" >&2
bats -r "${selected[@]}"
