#!/usr/bin/env bash
# validate.sh — contract SDK and deterministic release checks.
#
#   evals/validate.sh [--root DIR] [--report] [path]
#
# Prints the configured size budget and measured size for every contract.
# Exit: 0 ok · 1 usage · 2 contract/case failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
ROOT="$(cd "$_here/.." && pwd)"
exec python3 "$_here/lib/sdk.py" validate --root "$ROOT" "$@"
