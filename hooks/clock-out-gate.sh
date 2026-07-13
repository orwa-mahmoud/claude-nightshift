#!/usr/bin/env bash
# clock-out-gate.sh — Stop hook.
#
# The punch list is the only truth. While .nightshift/punch-list.md holds an open
# "- [ ]" item, the shift cannot clock out: the gate blocks the stop and re-injects
# the contract. Zero open boxes (or no punch list at all) releases it.
set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PUNCH="$PROJECT_DIR/.nightshift/punch-list.md"

# grep -c prints the count AND exits 1 on zero matches; keep only the number.
open_boxes() {
  local n
  n="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

# No punch list, or every box ticked -> nothing to hold. Release.
if [ ! -f "$PUNCH" ] || [ "$(open_boxes)" -eq 0 ]; then
  exit 0
fi

# Open items remain. Block, and re-inject the contract so the next turn resumes the shift.
cat <<'JSON'
{"decision":"block","reason":"DO NOT STOP — the punch list (.nightshift/punch-list.md) still has open items. Work them top to bottom, ONE at a time, each to its own Verify. Per item: implement fully — no stubs, no deferrals, no 'documented for later'; run the item gate right before its commit and require it GREEN; make ONE commit; then tick the box to '- [x]'. Never fake a tick. Deletion is not completion — never remove an item or edit the contract above '## Items'. Park any decision that is genuinely the owner's in .nightshift/parking-lot.md with a sensible default chosen, and KEEP WORKING — never ask, never wait. A walkthrough cycle that finds nothing new is SUCCESS, not idleness. You may stop only when zero '- [ ]' remain, or the owner issues a stop-work order (.nightshift/STOP)."}
JSON
exit 0
