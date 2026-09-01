#!/usr/bin/env bash
# provision.sh — transactional Auto-add engine.
#
#   provision.sh --project DIR plan|apply|recover|rollback \
#     [--recipe PATH] [--capability ID] [--budget-seconds N]
#
# Stages: authorize → capture-baseline → apply → smoke → record → commit-tooling
# Incomplete work is recorded only in .nightshift/provision-transaction.json.
# Never writes the punch list. Never pushes.
# Exit: 0 ok · 1 usage/runtime failure · 2 refused
set -u
_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
exec python3 "$_here/provision.py" "$@"
