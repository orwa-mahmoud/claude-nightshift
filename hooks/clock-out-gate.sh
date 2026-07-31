#!/usr/bin/env bash
# clock-out-gate.sh — Stop hook.
#
# The punch list is the only truth. Release order on every stop attempt:
#   1. stop-work order — .nightshift/STOP exists              -> release (open boxes stay open)
#   2. done            — zero open "- [ ]" (or no punch list) -> release
#   3. quitting time   — now past .nightshift/deadline        -> write STOP, log, release
#   4. otherwise       — block, re-injecting the contract
#
# Stall guard: consecutive stop attempts with no progress are counted (progress = a tick or a
# commit). By default a stalled shift is HELD — every 3 stuck attempts a stall warning lands
# in the shift log and the gate keeps blocking; only STOP, done, or the deadline release.
# Owner opt-in: NIGHTSHIFT_STALL_MAX=N auto-ends the shift (write STOP, log, release) after N
# stuck attempts. Env is fixed at session start, so only a human can choose that.
#
# Quitting time and the stall opt-in are a whistle, not an axe: a Stop hook can only run at
# a stop attempt, so neither can ever interrupt work mid-item.
#
# Morning whistle: if NIGHTSHIFT_NOTIFY_CMD is set, any shift-ending release fires it exactly
# once with a one-line summary (both $NIGHTSHIFT_SUMMARY and $1). Unset -> silent no-op.
#
# Receipts: any shift-ending release also snapshots .nightshift/ into its local receipts repo
# (the one /nightshift:setup created). No receipts repo -> no-op; a failed commit never blocks
# the release.
set -u

# shellcheck source=hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The Stop payload carries the session's identity; a tty guard keeps manual runs from hanging.
if [ -t 0 ]; then INPUT=""; else INPUT="$(cat)"; fi
if command -v jq >/dev/null 2>&1; then
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  TPATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
else
  SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  TPATH="$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"
DEADLINE="$NS/deadline"
STALL="$NS/.stall"
NOTIFIED="$NS/.notified"
ENDED="$NS/.ended" # written when the shift actually ends; hardhat keeps the site rules armed until then
LOG="$NS/shift-log.md"
STALL_MAX="${NIGHTSHIFT_STALL_MAX:-0}" # 0 = hold a stalled shift, never auto-end
STALL_WARN="${NIGHTSHIFT_STALL_WARN:-3}" # rules file: stallWarnEvery
case "$STALL_WARN" in '' | *[!0-9]*) STALL_WARN=3 ;; esac
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

# The code repo is what makes a commit visible as progress, and the recommended layout puts it
# one level below the project dir rather than at it. Where several repos sit there, no single
# HEAD describes the shift — so fingerprint all of them, and a commit in any one still counts.
project_head() {
  local r child base heads=""
  if r="$(repo_root "$PROJECT_DIR")"; then
    git -C "$r" rev-parse HEAD 2>/dev/null || printf 'nohead'
    return 0
  fi
  for child in "$PROJECT_DIR"/*/; do
    base="${child%/}"
    base="${base##*/}"
    case "$base" in .*) continue ;; esac
    r="$(git -C "$child" rev-parse HEAD 2>/dev/null)" || continue
    heads="$heads$r"
  done
  printf '%s' "${heads:-nohead}"
}

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
  # Exclusive create: of two sessions releasing at once, exactly one owns the whistle.
  (set -C; : >"$NOTIFIED") 2>/dev/null || return 0
  NIGHTSHIFT_SUMMARY="$1" sh -c "$NOTIFY" nightshift "$1" >/dev/null 2>&1 || true
}

# Receipts snapshot — $1 is the commit subject. Transient markers stay out via the receipts
# repo's own .gitignore; the pinned identity keeps this working headless. Signing is turned off
# explicitly: an owner with commit.gpgsign=true globally would otherwise lose every receipt to a
# key prompt that nothing is there to answer at 3am.
receipts_commit() {
  local err
  [ -d "$NS/.git" ] || return 0
  git -C "$NS" add -A >/dev/null 2>&1 || true
  err="$(git -C "$NS" -c user.name=nightshift -c user.email=nightshift@localhost \
    -c commit.gpgsign=false commit -q -m "$1" 2>&1)" && return 0
  case "$err" in
    *"nothing to commit"* | *"nothing added"*) : ;;
    *) log_line "receipts commit failed: $(printf '%s' "$err" | head -n1)" ;;
  esac
}

# Every shift-ending release runs through here. ENDED is what stands the site rules down —
# hardhat keeps them armed while a stop-work order is merely pending, because the agent goes on
# working until its next stop attempt.
end_shift() {
  [ -d "$NS" ] && : >"$ENDED"
  receipts_commit "$1"
  whistle "$1"
}

if [ -f "$PUNCH" ]; then OPEN="$(open_boxes)"; TICKED="$(ticked_boxes)"; else OPEN=0; TICKED=0; fi
TOTAL=$((OPEN + TICKED))

# Record the shift's own session, once — same contract as hardhat's record: id, transcript, and
# the claude ancestor's pid + start time, claimed with an exclusive create so two racing first
# sessions cannot interleave. Losing the race is the design.
record_shift_session() {
  local p="$$" _ comm pid="" start=""
  for _ in 1 2 3 4 5 6; do
    case "$p" in '' | *[!0-9]*) break ;; esac
    [ "$p" -gt 1 ] || break
    comm="$(ps -o comm= -p "$p" 2>/dev/null)" || break
    case "${comm##*/}" in claude) pid="$p"; break ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')"
  done
  [ -z "$pid" ] || start="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  (set -C; printf '%s\n%s\n%s\n%s\n' "$SID" "${TPATH:-}" "$pid" "$start" >"$NS/.shift-session") 2>/dev/null || true
}
if [ -f "$PUNCH" ] && [ "$OPEN" -gt 0 ] && [ ! -f "$ENDED" ] \
  && [ ! -f "$NS/.shift-session" ] && [ -n "${SID:-}" ]; then
  record_shift_session
fi

# The shift binds ONE session — the recorded one. Any other conversation in this project stops
# freely: the night is not its business unless the owner brings it. A watchman revival carries
# NIGHTSHIFT_REVIVAL=1 and inherits the binding even when the fresh-session fallback gave it a
# new id — it re-claims the record so the watchman and the clean-end tell follow the living
# thread. No parseable id keeps the conservative reading: held.
REC="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
if [ -n "$REC" ] && [ -n "${SID:-}" ] && [ "$SID" != "$REC" ]; then
  if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
    rm -f "$NS/.shift-session"
    record_shift_session
  else
    exit 0
  fi
fi

# One writer per site from here down: the stall fingerprint, the stop/ended markers, and the
# receipts commit are read-modify-write against shared files, and two sessions can attempt to
# stop at once. An unlockable site is decided unlocked — the gate must answer, never queue.
if [ -d "$NS" ] && ns_lock "$NS"; then
  trap 'ns_unlock "$NS"' EXIT
fi

# 1. Stop-work order — honor at once; open boxes are left open on purpose (an honest snapshot).
if [ -f "$STOP" ]; then
  if [ -f "$PUNCH" ]; then
    reason="$(head -n1 "$STOP" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    summary="shift ended${reason:+ ($reason)}: $TICKED/$TOTAL done"
    end_shift "$summary"
  fi
  exit 0
fi

# 2. Done — no punch list at all, or every box ticked.
[ -f "$PUNCH" ] || exit 0
if [ "$OPEN" -eq 0 ]; then
  end_shift "shift done: $TICKED/$TOTAL"
  exit 0
fi

# 3. Quitting time — mechanical deadline.
if [ -f "$DEADLINE" ] && deadline_passed; then
  log_line "quitting time — shift ended, $TICKED/$TOTAL done, items left open"
  printf 'deadline\n' >"$STOP"
  end_shift "quitting time: $TICKED/$TOTAL done, items left open"
  exit 0
fi

# Stall guard — consecutive stop attempts with no progress. Progress = a box ticked OR a
# commit landed, captured in the fingerprint; either resets the counter. Held by default:
# warn in the shift log every STALL_WARN stuck attempts and keep blocking. Auto-end only on
# the owner's NIGHTSHIFT_STALL_MAX=N opt-in.
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
if [ "$STALL_MAX" -gt 0 ] 2>/dev/null; then
  if [ "$attempts" -ge "$STALL_MAX" ]; then
    log_line "stalled — auto-ended, $attempts attempts no progress, $TICKED/$TOTAL done, items left open"
    printf 'stalled\n' >"$STOP"
    end_shift "stalled: $TICKED/$TOTAL done, $attempts attempts no progress"
    exit 0
  fi
elif [ "$attempts" -ge "$STALL_WARN" ]; then
  log_line "stall warning — $attempts attempts no progress, $TICKED/$TOTAL done; keeping shift open"
  attempts=0
fi
printf '%s\n%s\n' "$FP" "$attempts" >"$STALL"

# 4. Block, and re-inject the contract so the next turn resumes the shift. The owner may word
# the reinjection (rules file key: clockOutMessage) — jq builds the JSON so their text cannot
# break it; without jq the custom text is skipped, never a malformed decision.
if [ -n "${NIGHTSHIFT_GATE_MESSAGE:-}" ] && command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$NIGHTSHIFT_GATE_MESSAGE" '{decision:"block",reason:$r}'
  exit 0
fi
cat <<'JSON'
{"decision":"block","reason":"DO NOT STOP — the punch list (.nightshift/punch-list.md) still has open items. Work them top to bottom, ONE at a time, each to its own Verify. Per item: implement fully — no stubs, no deferrals, no 'documented for later'; effort is never a reason to defer, and this IS the focused session; run the item gate right before its commit and require it GREEN; make ONE commit; then tick the box to '- [x]'. Never fake a tick. Deletion is not completion — never remove an item or edit the contract above '## Items'. Park any decision that is genuinely the owner's in .nightshift/parking-lot.md with a sensible default chosen, and KEEP WORKING — never ask, never wait. A walkthrough cycle that finds nothing new is SUCCESS, not idleness. You may stop only when zero '- [ ]' remain, or the owner issues a stop-work order (.nightshift/STOP)."}
JSON
exit 0
