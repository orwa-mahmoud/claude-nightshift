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
#
# Morning whistle: if NIGHTSHIFT_NOTIFY_CMD is set, any shift-ending release fires it exactly
# once with a one-line summary (both $NIGHTSHIFT_SUMMARY and $1). Unset -> silent no-op.
set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"
DEADLINE="$NS/deadline"
STALL="$NS/.stall"
NOTIFIED="$NS/.notified"
LOG="$NS/shift-log.md"
STALL_MAX="${NIGHTSHIFT_STALL_MAX:-3}"
NOTIFY="${NIGHTSHIFT_NOTIFY_CMD:-}"

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

# Morning whistle — fires at most once per shift; $1 is the summary line.
whistle() {
  [ -n "$NOTIFY" ] || return 0
  [ -f "$NOTIFIED" ] && return 0
  : >"$NOTIFIED"
  NIGHTSHIFT_SUMMARY="$1" sh -c "$NOTIFY" nightshift "$1" >/dev/null 2>&1 || true
}

if [ -f "$PUNCH" ]; then OPEN="$(open_boxes)"; TICKED="$(ticked_boxes)"; else OPEN=0; TICKED=0; fi
TOTAL=$((OPEN + TICKED))

# 1. Stop-work order — honor at once; open boxes are left open on purpose (an honest snapshot).
if [ -f "$STOP" ]; then
  if [ -f "$PUNCH" ]; then
    reason="$(head -n1 "$STOP" 2>/dev/null | tr -d '[:space:]')"
    whistle "shift ended${reason:+ ($reason)}: $TICKED/$TOTAL done"
  fi
  exit 0
fi

# 2. Done — no punch list at all, or every box ticked.
[ -f "$PUNCH" ] || exit 0
if [ "$OPEN" -eq 0 ]; then
  whistle "shift done: $TICKED/$TOTAL"
  exit 0
fi

# 3. Quitting time — mechanical deadline.
if [ -f "$DEADLINE" ] && deadline_passed; then
  log_line "quitting time — shift ended, $TICKED/$TOTAL done, items left open"
  printf 'deadline\n' >"$STOP"
  whistle "quitting time: $TICKED/$TOTAL done, items left open"
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
  whistle "stalled: $TICKED/$TOTAL done, $attempts attempts no progress"
  exit 0
fi
printf '%s\n%s\n' "$FP" "$attempts" >"$STALL"

# 5. Block, and re-inject the contract so the next turn resumes the shift.
cat <<'JSON'
{"decision":"block","reason":"DO NOT STOP — the punch list (.nightshift/punch-list.md) still has open items. Work them top to bottom, ONE at a time, each to its own Verify. Per item: implement fully — no stubs, no deferrals, no 'documented for later'; run the item gate right before its commit and require it GREEN; make ONE commit; then tick the box to '- [x]'. Never fake a tick. Deletion is not completion — never remove an item or edit the contract above '## Items'. Park any decision that is genuinely the owner's in .nightshift/parking-lot.md with a sensible default chosen, and KEEP WORKING — never ask, never wait. A walkthrough cycle that finds nothing new is SUCCESS, not idleness. You may stop only when zero '- [ ]' remain, or the owner issues a stop-work order (.nightshift/STOP)."}
JSON
exit 0
