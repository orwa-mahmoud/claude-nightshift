#!/usr/bin/env bash
# clock-out-gate.sh — Stop hook.
#
# The punch list is the only truth. Release order on every stop attempt:
#   1. stop-work order — .nightshift/STOP exists              -> release (open boxes stay open)
#   2. done            — zero open "- [ ]" (or no punch list) -> release
#   3. quitting time   — now past .nightshift/deadline        -> write STOP, log, release
#   4. stall red-tag   — N stop attempts, no progress         -> write STOP, log, release
#   5. otherwise       — block, re-injecting the contract
#
# Quitting time and the stall guard are a whistle, not an axe: a Stop hook can only run at
# a stop attempt, so neither can ever interrupt work mid-item.
set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"
DEADLINE="$NS/deadline"
STALL="$NS/.stall"
LOG="$NS/shift-log.md"
STALL_MAX="${NIGHTSHIFT_STALL_MAX:-3}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_line() { [ -d "$NS" ] && printf '%s · %s\n' "$(ts)" "$1" >>"$LOG"; }

# grep -c prints the count AND exits 1 on zero matches; keep only the number.
count() {
  local n
  n="$(grep -cE "$1" "$PUNCH" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}
open_boxes()   { count '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]'; }
ticked_boxes() { count '^[[:space:]]*-[[:space:]]*\[[xX]\]'; }

project_head() { git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || printf 'nohead'; }

deadline_passed() {
  local now dl target
  now="$(date +%s)"
  dl="$(tr -d '[:space:]' <"$DEADLINE" 2>/dev/null || true)"
  [ -n "$dl" ] || return 1
  if printf '%s' "$dl" | grep -qE '^[0-9]+$'; then
    target="$dl"                                    # epoch seconds (what `start` writes)
  else                                              # best-effort ISO parse, GNU then BSD
    target="$(date -d "$dl" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S' "$dl" +%s 2>/dev/null || true)"
  fi
  [ -n "$target" ] || return 1
  [ "$now" -ge "$target" ]
}

# 1. Stop-work order — honor at once; open boxes are left open on purpose (an honest snapshot).
[ -f "$STOP" ] && exit 0

# 2. Done — no punch list, or every box ticked.
if [ ! -f "$PUNCH" ] || [ "$(open_boxes)" -eq 0 ]; then
  exit 0
fi

OPEN="$(open_boxes)"
TICKED="$(ticked_boxes)"
TOTAL=$((OPEN + TICKED))

# 3. Quitting time — mechanical deadline.
if [ -f "$DEADLINE" ] && deadline_passed; then
  log_line "quitting time — shift ended, $TICKED/$TOTAL done, items left open"
  printf 'deadline\n' >"$STOP"
  exit 0
fi

# 4. Stall red-tag — N consecutive stop attempts with no progress. Progress = a box ticked
#    OR a commit landed, captured in the fingerprint; either resets the counter.
FP="$TICKED:$(project_head)"
prev_fp=""
prev_n=0
if [ -f "$STALL" ]; then
  prev_fp="$(sed -n '1p' "$STALL")"
  prev_n="$(sed -n '2p' "$STALL")"
  prev_n="${prev_n:-0}"
fi
if [ "$prev_fp" = "$FP" ]; then
  attempts=$((prev_n + 1))
else
  attempts=1
fi
if [ "$attempts" -ge "$STALL_MAX" ]; then
  log_line "stalled — auto-ended, $attempts attempts no progress, $TICKED/$TOTAL done, items left open"
  printf 'stalled\n' >"$STOP"
  exit 0
fi
printf '%s\n%s\n' "$FP" "$attempts" >"$STALL"

# 5. Block, and re-inject the contract so the next turn resumes the shift.
cat <<'JSON'
{"decision":"block","reason":"DO NOT STOP — the punch list (.nightshift/punch-list.md) still has open items. Work them top to bottom, ONE at a time, each to its own Verify. Per item: implement fully — no stubs, no deferrals, no 'documented for later'; run the item gate right before its commit and require it GREEN; make ONE commit; then tick the box to '- [x]'. Never fake a tick. Deletion is not completion — never remove an item or edit the contract above '## Items'. Park any decision that is genuinely the owner's in .nightshift/parking-lot.md with a sensible default chosen, and KEEP WORKING — never ask, never wait. A walkthrough cycle that finds nothing new is SUCCESS, not idleness. You may stop only when zero '- [ ]' remain, or the owner issues a stop-work order (.nightshift/STOP)."}
JSON
exit 0
