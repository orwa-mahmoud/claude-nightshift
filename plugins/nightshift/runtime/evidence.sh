#!/usr/bin/env bash
# evidence.sh — versioned findings ledger (JSON Lines).
#
#   evidence.sh --project DIR init|validate|append|disposition|render|export-tsv|migrate
#
# Validates records. Does not verify a Nightshift tick or interpret domain meaning.
# Exit: 0 ok · 1 usage · 2 contract failure
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
exec python3 "$_here/evidence.py" "$@"
