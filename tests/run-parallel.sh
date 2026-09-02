#!/usr/bin/env bash
# Run the full bats suite in parallel shards (default 6). Same coverage as bats -r tests/.
# Usage: tests/run-parallel.sh [JOBS]
set -euo pipefail

jobs="${1:-6}"
case "$jobs" in
  *[!0-9]* | '')
    echo "usage: tests/run-parallel.sh [JOBS]" >&2
    exit 2
    ;;
esac
if [ "$jobs" -lt 1 ]; then
  echo "JOBS must be >= 1" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

tmpdir="${TMPDIR:-/tmp}/nightshift-bats-parallel-$$"
mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

failed=0
for s in $(seq 1 "$jobs"); do
  (
    export BATS_TMPDIR="$tmpdir/bats-shard-${s}"
    mkdir -p "$BATS_TMPDIR"
    if ! tests/run-shard.sh "$s" "$jobs" >"$tmpdir/shard-${s}.log" 2>&1; then
      echo 1 >"$tmpdir/shard-${s}.failed"
    fi
  ) &
done

for job in $(jobs -p); do
  wait "$job" || true
done

for s in $(seq 1 "$jobs"); do
  if [ -f "$tmpdir/shard-${s}.failed" ]; then
    failed=1
    echo "=== shard $s/$jobs FAILED ===" >&2
    cat "$tmpdir/shard-${s}.log" >&2
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "all $jobs shards passed" >&2
