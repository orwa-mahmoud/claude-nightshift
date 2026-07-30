#!/usr/bin/env bash
# watchman.sh — the night watchman. Revives a session that DIES mid-shift; never one that ended.
#
# A Stop hook can only act inside a living session. A session killed by an API outage, a crash,
# or a closed terminal fires no hooks — the punch list survives on disk, but nothing re-invokes
# the agent, and the night is lost. The watchman is the outside half: armed at shift start, it
# wakes every interval and, only when the site is BOTH mid-shift and dead quiet, spawns a fresh
# headless session that resumes from the punch list. The file is the handover; no context is
# needed back.
#
#   watchman.sh [--project DIR] [--interval MIN] [--agent CMD] [--max-wakes N]
#
#   --interval  minutes between wakes (default $NIGHTSHIFT_WATCH, else 20; 0 exits immediately —
#               the "disabled" spelling)
#   --agent     the resume command. Default: the SHIFT'S OWN conversation, by id — the hooks
#               record the first working session into .nightshift/.shift-session, and the
#               revival is "claude --resume <that id> -p", one unbroken thread in the terminal
#               and the IDE extension alike. No record (or a vanished session) degrades to
#               "claude --continue -p". On the default agent only, the last retry of a wake
#               falls back to a fresh "claude -p": if the conversation itself is what broke,
#               resuming it would fail every wake forever, and the punch list on disk is enough
#               for a fresh session to carry on.
#   --max-wakes bound the number of wakes (0 = unbounded; tests use this)
#
# Stand-down order, checked at every wake — the watchman never overrides an honest ending:
#   1. stop-work order (.nightshift/STOP)            -> down (STOP is the pause while armed)
#   2. shift ended (.nightshift/.ended, or no punch) -> down
#   3. every box ticked                              -> one clock-out spawn if .ended is missing
#                                                       (crash at the finish line still gets
#                                                       receipts + whistle), then down
#   4. quitting time passed                          -> one clock-out spawn, then down
#   5. clean session end (.nightshift/.session-end)  -> down; the owner closed it on purpose
#
# Liveness: a working agent touches files constantly, so "alive" = anything in the project newer
# than the last wake's sentinel.
#
# Esc still means stop. Claude Code records a user interrupt in the session transcript
# ("Request interrupted by user"), and a 500 or a crash never writes one — that is the tell. At a
# quiet wake the watchman reads the tail of THE SHIFT'S OWN transcript (recorded in
# .shift-session by the hooks): interrupt there -> the owner paused it, stand by and keep
# watching; no interrupt -> it died or errored with nobody there, revive it. A second tab's Esc
# proves nothing and is ignored. With no record yet, the newest transcript in the project is the
# fallback tell. Unreadable defaults to reviving: waking a paused session costs an apology, a
# lost night costs the night. $NIGHTSHIFT_WATCH_TRANSCRIPTS overrides the transcript directory
# (tests use it).
#
# API outages: per wake, up to 3 spawn attempts spaced by $NIGHTSHIFT_WATCH_RETRY (default
# "30 120" seconds). Wakes that fail entirely back the interval off — double per consecutive
# failure, capped at 8x — so a dead API costs a handful of logged attempts, not one every tick.
# Exit: 0 stood down honestly · 1 usage/lock · 7 wake cap (tests).
set -u

PROJECT="$PWD"
INTERVAL_MIN="${NIGHTSHIFT_WATCH:-20}"
AGENT="${NIGHTSHIFT_WATCH_AGENT:-claude --continue -p}"
AGENT_IS_DEFAULT=1
[ -z "${NIGHTSHIFT_WATCH_AGENT:-}" ] || AGENT_IS_DEFAULT=0
MAX_WAKES=0
RETRY_SPACING="${NIGHTSHIFT_WATCH_RETRY:-30 120}"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit 1
}
need_value() { [ "$2" -ge 2 ] || { printf 'watchman: %s needs a value\n' "$1" >&2; usage; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project) need_value "$1" $#; PROJECT="$2"; shift 2 ;;
    --interval) need_value "$1" $#; INTERVAL_MIN="$2"; shift 2 ;;
    --agent) need_value "$1" $#; AGENT="$2"; AGENT_IS_DEFAULT=0; shift 2 ;;
    --max-wakes) need_value "$1" $#; MAX_WAKES="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) printf 'watchman: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

case "$INTERVAL_MIN" in *[!0-9]*) printf 'watchman: --interval must be whole minutes\n' >&2; exit 1 ;; esac
[ "$INTERVAL_MIN" -gt 0 ] || exit 0 # 0 = disabled, by design

cd "$PROJECT" || { printf 'watchman: cannot cd to %s\n' "$PROJECT" >&2; exit 1; }
PROJECT="$PWD"
NS="$PROJECT/.nightshift"
PUNCH="$NS/punch-list.md"
PIDFILE="$NS/.watchman"
SENTINEL="$NS/.watchman-tick"
[ -d "$NS" ] || { printf 'watchman: no .nightshift at %s\n' "$PROJECT" >&2; exit 1; }

# Claude Code keeps transcripts under ~/.claude/projects/<project path, non-alnum -> dashes>.
TRANSCRIPTS="${NIGHTSHIFT_WATCH_TRANSCRIPTS:-$HOME/.claude/projects/$(printf '%s' "$PROJECT" | tr -c 'A-Za-z0-9' '-')}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_line() { printf '%s · %s\n' "$(ts)" "$1" >>"$NS/shift-log.md"; }

# One watchman per site. A stale pidfile (dead pid) is taken over silently.
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
  printf 'watchman: already watching (pid %s)\n' "$(cat "$PIDFILE")" >&2
  exit 1
fi
printf '%s\n' "$$" >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

open_boxes() {
  local n
  n="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

deadline_passed() {
  local dl
  [ -f "$NS/deadline" ] || return 1
  dl="$(tr -d '[:space:]' <"$NS/deadline" 2>/dev/null || true)"
  [ -n "$dl" ] || return 1
  case "$dl" in *[!0-9]*) return 1 ;; esac # start/hunt write epochs; anything else is not ours to judge
  [ "$(date +%s)" -ge "$dl" ]
}

# The hooks write the shift's identity (session id, transcript path) at first work. Read fresh
# each use — the record appears after the watchman was armed.
shift_session_id() { sed -n 1p "$NS/.shift-session" 2>/dev/null; }
shift_transcript() { sed -n 2p "$NS/.shift-session" 2>/dev/null; }

# The default agent resumes the shift's own conversation by id; no record degrades to --continue.
# An owner-supplied agent is used verbatim.
resolve_agent() {
  local sid
  if [ "$AGENT_IS_DEFAULT" -eq 1 ]; then
    sid="$(shift_session_id)"
    if [ -n "$sid" ]; then printf 'claude --resume %s -p' "$sid"; else printf 'claude --continue -p'; fi
  else
    printf '%s' "$AGENT"
  fi
}

PROMPT="Resume the nightshift. Read .nightshift/punch-list.md and work its open items per the contract, one at a time; run the item gate before each commit; tick what you finish. Leave pushing to the owner unless the punch list says otherwise. Park owner decisions in parking-lot.md. Stop only when every box is ticked or a stop-work order exists."

# One spawn attempt; the resumed session may legitimately run for hours. shellcheck disable:
# $AGENT is an owner-provided command line; word-splitting is intended, as in foreman.
spawn() { # $1 optionally overrides the agent for this one attempt
  local a="${1:-$AGENT}"
  # shellcheck disable=SC2086
  $a "$PROMPT" >/dev/null 2>&1
}

# The Esc tell: an interrupt marker in the tail of the newest transcript means the owner paused
# the session on purpose. Only the tail — an interrupt mid-history with work after it is a
# session that already moved on.
owner_paused() {
  local f latest=""
  latest="$(shift_transcript)"
  if [ -z "$latest" ] || [ ! -f "$latest" ]; then
    latest=""
    for f in "$TRANSCRIPTS"/*.jsonl; do
      [ -f "$f" ] || continue
      if [ -z "$latest" ] || [ "$f" -nt "$latest" ]; then latest="$f"; fi
    done
  fi
  [ -n "$latest" ] || return 1
  tail -n 25 "$latest" 2>/dev/null | grep -q "Request interrupted by user"
}

alive_since_last_wake() {
  # -type f: a directory's mtime moves whenever anything inside it is created or removed — the
  # watchman's own bookkeeping would read as site life. Files are the signal, directories noise.
  find "$PROJECT" -path "$NS/.watchman*" -prune -o -type f -newer "$SENTINEL" -print 2>/dev/null |
    grep -q .
}

log_line "watchman armed · every ${INTERVAL_MIN}m"
: >"$SENTINEL"
wake=0
misses=0

# NIGHTSHIFT_WATCH_SLEEP overrides the base sleep in seconds — the test suite's speed lever.
BASE_SLEEP="${NIGHTSHIFT_WATCH_SLEEP:-$((INTERVAL_MIN * 60))}"

while :; do
  sleep $((BASE_SLEEP * (misses < 3 ? 1 << misses : 8)))
  wake=$((wake + 1))

  if [ -f "$NS/STOP" ]; then log_line "watchman: stop-work order — standing down"; exit 0; fi
  if [ -f "$NS/.ended" ] || [ ! -f "$PUNCH" ]; then exit 0; fi
  if [ "$(open_boxes)" -eq 0 ]; then
    log_line "watchman: every box ticked but the shift never clocked out — spawning the clock-out"
    spawn "$(resolve_agent)" || true
    exit 0
  fi
  if deadline_passed; then
    log_line "watchman: quitting time passed with the site dead — spawning the clock-out"
    spawn "$(resolve_agent)" || true
    exit 0
  fi
  if [ -f "$NS/.session-end" ]; then
    log_line "watchman: clean session end — the owner closed it; standing down (start re-arms)"
    exit 0
  fi

  if alive_since_last_wake; then
    misses=0
    esc_prev=0
  elif owner_paused; then
    # Esc means stop. Stand by rather than down: if the owner resumes and a 500 kills it later,
    # the next quiet wake will find an errored tail, not an interrupt, and revive as usual.
    if [ "${esc_prev:-0}" -eq 0 ]; then
      log_line "watchman: owner pressed Esc — standing by, not resuming (STOP ends the shift; resuming re-arms)"
    fi
    esc_prev=1
    misses=0
  else
    esc_prev=0
    attempt=0
    revived=1
    # shellcheck disable=SC2086  # RETRY_SPACING is a space-separated list; splitting is the point
    for spacing in $RETRY_SPACING ""; do
      attempt=$((attempt + 1))
      if [ -z "$spacing" ] && [ "$AGENT_IS_DEFAULT" -eq 1 ]; then
        # Last try of the wake: if the conversation itself is what broke, --continue can never
        # succeed — a fresh session reads the punch list and carries on regardless.
        log_line "watchman: resume attempt $attempt (fresh-session fallback)"
        if spawn "claude -p"; then revived=0; fi
        break
      fi
      log_line "watchman: site quiet ${INTERVAL_MIN}m+ with open boxes — resume attempt $attempt"
      if spawn "$(resolve_agent)"; then revived=0; break; fi
      [ -n "$spacing" ] || break
      sleep "$spacing"
    done
    if [ "$revived" -eq 0 ]; then
      misses=0
      log_line "watchman: resumed session returned — re-checking next wake"
    else
      misses=$((misses + 1))
      log_line "watchman: all $attempt attempts failed (api down?) — backing off"
    fi
  fi

  : >"$SENTINEL" # after all actions, so the watchman's own writes never read as site life
  if [ "$MAX_WAKES" -gt 0 ] && [ "$wake" -ge "$MAX_WAKES" ]; then exit 7; fi
done
