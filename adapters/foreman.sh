#!/usr/bin/env bash
# foreman.sh — the universal outer loop. Keeps sending ANY headless agent CLI back into the
# project until the punch list is clear, the deadline passes, the iteration cap is hit, or a
# stop-work order lands. Enforcement lives OUTSIDE the agent, so it works with any CLI
# (codex exec, cursor-agent, aider, opencode run, claude -p, ...).
#
#   foreman.sh --agent "codex exec --full-auto" \
#     [--project DIR] [--punch-list PATH] [--deadline "07:00"|EPOCH] \
#     [--max-iterations 50] [--stall N]
#
# The agent is invoked as:  <agent command> "<continuation prompt>"
# A no-progress run is HELD by default — every 3 stuck iterations a stall warning lands in
# the shift log and the loop keeps going; --stall N (or NIGHTSHIFT_STALL_MAX=N) opts into
# stopping after N stuck iterations instead. Deadline and cap are checked BETWEEN iterations
# only — a running agent is never killed (a whistle, not an axe).
# Exit: 0 done · 2 deadline · 3 cap · 4 stalled (opt-in) · 5 stop-work · 1 usage.
set -u

AGENT=""
PROJECT="$PWD"
PUNCH=""
DEADLINE_RAW=""
MAX_ITER=50
STALL_MAX="${NIGHTSHIFT_STALL_MAX:-0}" # 0 = hold a stalled run, never stop the loop
STALL_WARN=3

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit 1
}

# An option whose value is missing leaves nothing to shift past, and `shift 2` on a single
# remaining argument fails without moving — the loop would spin on it forever, silently.
need_value() { [ "$2" -ge 2 ] || { printf 'foreman: %s needs a value\n' "$1" >&2; usage; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) need_value "$1" $#; AGENT="$2"; shift 2 ;;
    --project) need_value "$1" $#; PROJECT="$2"; shift 2 ;;
    --punch-list) need_value "$1" $#; PUNCH="$2"; shift 2 ;;
    --deadline) need_value "$1" $#; DEADLINE_RAW="$2"; shift 2 ;;
    --max-iterations) need_value "$1" $#; MAX_ITER="$2"; shift 2 ;;
    --stall) need_value "$1" $#; STALL_MAX="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) printf 'foreman: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

[ -n "$AGENT" ] || { printf 'foreman: --agent is required\n' >&2; usage; }
cd "$PROJECT" || { printf 'foreman: cannot cd to %s\n' "$PROJECT" >&2; exit 1; }
PROJECT="$PWD"
NS="$PROJECT/.nightshift"
[ -n "$PUNCH" ] || PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"
LOG="$NS/shift-log.md"
[ -f "$PUNCH" ] || { printf 'foreman: no punch list at %s\n' "$PUNCH" >&2; exit 1; }

PROMPT="Resume the nightshift. Read .nightshift/punch-list.md and work its open items per the contract, one at a time; run the item gate before each commit; tick what you finish. Leave pushing to the owner unless the punch list says otherwise. Park owner decisions in parking-lot.md. Stop only when every box is ticked or a stop-work order exists."

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_line() { [ -d "$NS" ] && printf '%s · %s\n' "$(ts)" "$1" >>"$LOG"; }

open_boxes() {
  local n
  n="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}
ticked_boxes() {
  local n
  n="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[xX]\]' "$PUNCH" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}
project_head() { git -C "$PROJECT" rev-parse HEAD 2>/dev/null || printf 'nohead'; }

to_epoch() { # echoes an epoch, or nothing if unparseable / empty
  local d="$1" day e
  [ -n "$d" ] || return 0
  case "$d" in
    *[!0-9]*) : ;;                 # contains a non-digit
    *) printf '%s' "$d"; return 0 ;; # pure digits -> already epoch
  esac
  if printf '%s' "$d" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then
    day="$(date +%Y-%m-%d)"
    e="$(date -d "$day $d" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M' "$day $d" +%s 2>/dev/null || true)"
    if [ -n "$e" ] && [ "$e" -le "$(date +%s)" ]; then # already past today -> next day
      e="$(date -d "$day $d +1 day" +%s 2>/dev/null || date -j -v+1d -f '%Y-%m-%d %H:%M' "$day $d" +%s 2>/dev/null || true)"
    fi
    printf '%s' "$e"
    return 0
  fi
  date -d "$d" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S' "$d" +%s 2>/dev/null || true
}

whistle() {
  [ -n "${NIGHTSHIFT_NOTIFY_CMD:-}" ] || return 0
  NIGHTSHIFT_SUMMARY="$1" sh -c "$NIGHTSHIFT_NOTIFY_CMD" nightshift "$1" >/dev/null 2>&1 || true
}

DEADLINE_EPOCH="$(to_epoch "$DEADLINE_RAW")"

iter=0
stall_n=0
prev_fp=""
reason=""
code=0

while :; do
  # --- between-iteration checks (never interrupt a running agent) ---
  if [ -f "$STOP" ]; then reason="stop-work"; code=5; break; fi
  if [ "$(open_boxes)" -eq 0 ]; then reason="done"; code=0; break; fi
  if [ "$iter" -ge "$MAX_ITER" ]; then reason="cap"; code=3; break; fi
  if [ -n "$DEADLINE_EPOCH" ] && [ "$(date +%s)" -ge "$DEADLINE_EPOCH" ]; then reason="deadline"; code=2; break; fi

  # Stall guard — held by default: warn every STALL_WARN stuck iterations and keep looping.
  # Only the --stall/NIGHTSHIFT_STALL_MAX opt-in stops the loop; garbage fails safe to hold.
  fp="$(open_boxes):$(project_head)"
  if [ "$iter" -gt 0 ]; then
    if [ "$fp" = "$prev_fp" ]; then stall_n=$((stall_n + 1)); else stall_n=0; fi
    if [ "$STALL_MAX" -gt 0 ] 2>/dev/null; then
      if [ "$stall_n" -ge "$STALL_MAX" ]; then
        printf 'stalled\n' >"$STOP" 2>/dev/null || true
        reason="stalled"
        code=4
        break
      fi
    elif [ "$stall_n" -ge "$STALL_WARN" ]; then
      t="$(ticked_boxes)"
      log_line "stall warning — $stall_n attempts no progress, $t/$((t + $(open_boxes))) done; keeping shift open"
      stall_n=0
    fi
  fi
  prev_fp="$fp"

  iter=$((iter + 1))
  log_line "foreman iteration $iter · $(open_boxes) open"
  # shellcheck disable=SC2086  # $AGENT is a user-provided command line; word-splitting is intended
  $AGENT "$PROMPT" || true # a failing agent never kills the loop; the fingerprint judges liveness
done

log_line "foreman ended: $reason after $iter iteration(s), $(open_boxes) open"
whistle "foreman $reason: $(open_boxes) open after $iter iteration(s)"
exit "$code"
