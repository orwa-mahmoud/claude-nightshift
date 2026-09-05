#!/usr/bin/env bash
# run.sh — run the deterministic eval matrix and write a human-review report.
#
#   evals/run.sh [--root DIR]
#
# Informational host-agent baselines are recorded in the report and never gated.
# Exit: 0 ok · 1 usage · 2 eval failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
ROOT="$(cd "$_here/.." && pwd)"
exec python3 "$_here/lib/sdk.py" run --root "$ROOT" "$@"
