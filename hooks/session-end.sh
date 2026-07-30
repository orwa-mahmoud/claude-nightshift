#!/usr/bin/env bash
# session-end.sh — SessionEnd hook. A clean exit mid-shift is the owner's hand on the door.
#
# The night watchman (adapters/watchman.sh) revives a session that dies mid-shift — but a session
# the owner ended on purpose (/exit, a clean quit) must stay ended. Crashes, kills and API deaths
# never reach this hook, which is exactly the tell: a marker present means a hand closed the
# session, no marker means it died. The watchman stands down on the marker; /nightshift:start and
# the hunt cut clear it, which is what re-arms the night.
#
# Inert outside an active shift: no punch list, no open box, or an already-ended shift writes
# nothing, so ordinary sessions leave no residue.
set -u

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"

if [ ! -f "$PUNCH" ] || [ -f "$NS/.ended" ] \
  || ! grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null; then
  exit 0
fi

# jq preferred, sed fallback — same policy as hardhat: a missing jq never disables the hook.
if command -v jq >/dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.reason // "unknown"' 2>/dev/null || printf 'unknown')"
else
  REASON="$(printf '%s' "$INPUT" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  REASON="${REASON:-unknown}"
fi

printf '%s · clean session end (%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$REASON" >"$NS/.session-end"
exit 0
