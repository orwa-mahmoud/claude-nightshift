#!/usr/bin/env bash
# detect-capabilities.sh — read-only applicability detector.
#
#   detect-capabilities.sh --project DIR [--host claude|codex|cursor] [--normalize]
#
# Prints JSON on stdout. Never writes inside the project. Exit 0 on success, 1 on usage.
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
exec python3 "$_here/detect-capabilities.py" "$@"
