#!/usr/bin/env bash
# capability-policy.sh — persist the owner's tooling policy and inventory cache.
#
#   capability-policy.sh --project DIR get|set|inventory|migrate [options]
#
#   get [--work-mode repository|artifact]
#   set --policy existing-tools|auto-add|review-missing [--remember true|false]
#   inventory get
#   inventory set --record JSON
#   migrate
#
# Writes only .nightshift/capability-policy.json and .nightshift/capabilities.json.
# Never writes the punch list. Inventory is a cache, not proof of a tick.
# Exit: 0 ok (get fails closed to existing-tools) · 1 usage/missing state · 2 contract
set -u
_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
exec python3 "$_here/capability-policy.py" "$@"
