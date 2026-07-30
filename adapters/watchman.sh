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
#               and the IDE extension alike. On the default agent the attempts of a wake walk a
#               chain, each rung logged: the recorded conversation first, "claude --continue -p"
#               next (no record starts here), and a fresh "claude -p" last — if the conversation
#               itself is what broke, resuming it would fail every wake forever, and the punch
#               list on disk is enough for a fresh session to carry on.
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
# Liveness is a ladder, not a guess — revival needs strong positive evidence of death, because
# the one truly harmful failure is spawning a second agent beside a living one (a resumed id
# APPENDS to the same session; two writers interleave):
#   1. the shift's transcript moved since last wake  -> alive (a session streams every turn)
#   2. any project file moved                        -> alive (work that writes files)
#   3. interrupt marker in the transcript tail       -> owner pressed Esc; stand by
#   4. recorded pid alive (start time verified)      -> tail shows "API Error"? the 500 wedge:
#                                                       alive but errored, nobody home — revive.
#                                                       No error -> long silent work; stand by
#   5. no pid recorded, a claude process in project  -> uncertain; stand by (conservative)
#   6. none of the above                             -> dead; revive
# Every retry attempt re-runs the whole ladder first — a site that comes back to life mid-wake
# is left alone — and each failed attempt re-baselines the sentinel so its own transcript writes
# never read as site life.
#
# Esc still means stop. Claude Code records a user interrupt in the session transcript
# ("Request interrupted by user"), and a 500 or a crash never writes one — that is the tell, read
# from the tail of THE SHIFT'S OWN transcript (recorded in .shift-session by the hooks). A second
# tab's Esc proves nothing and is ignored. With no record yet, the newest transcript in the
# project is the fallback tell. Unreadable defaults to reviving: waking a paused session costs an
# apology, a lost night costs the night. $NIGHTSHIFT_WATCH_TRANSCRIPTS overrides the transcript
# directory (tests use it).
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

# The hooks write the shift's identity at first work: session id, transcript path, and the
# claude ancestor's pid + start time. Read fresh each use — the record appears after the
# watchman was armed.
shift_session_id() { sed -n 1p "$NS/.shift-session" 2>/dev/null; }
shift_transcript() { sed -n 2p "$NS/.shift-session" 2>/dev/null; }
shift_pid() { sed -n 3p "$NS/.shift-session" 2>/dev/null; }
shift_pid_start() { sed -n 4p "$NS/.shift-session" 2>/dev/null; }

# Attempts of a wake walk a chain of rungs on the default agent: the recorded conversation
# first, --continue next (and first when nothing was recorded), a fresh session last — each a
# weaker but sturdier claim on the night. An owner-supplied agent is used verbatim on every rung.
rung_agent() { # $1 attempt, $2 total attempts this wake
  local sid
  if [ "$AGENT_IS_DEFAULT" -ne 1 ]; then printf '%s' "$AGENT"; return; fi
  if [ "$1" -ge "$2" ] && [ "$2" -gt 1 ]; then printf 'claude -p'; return; fi
  sid="$(shift_session_id)"
  if [ "$1" -eq 1 ] && [ -n "$sid" ]; then printf 'claude --resume %s -p' "$sid"; else printf 'claude --continue -p'; fi
}
rung_label() { # morning-readable name for the rung, mirrors rung_agent
  if [ "$AGENT_IS_DEFAULT" -ne 1 ]; then printf 'owner agent'; return; fi
  if [ "$1" -ge "$2" ] && [ "$2" -gt 1 ]; then printf 'fresh-session fallback'; return; fi
  if [ "$1" -eq 1 ] && [ -n "$(shift_session_id)" ]; then printf 'resuming the recorded conversation'; else printf -- '--continue fallback'; fi
}
# Clock-out spawns take the strongest single rung: the recorded conversation, else --continue.
resolve_agent() { rung_agent 1 2; }

PROMPT="Resume the nightshift. Read .nightshift/punch-list.md and work its open items per the contract, one at a time; run the item gate before each commit; tick what you finish. Leave pushing to the owner unless the punch list says otherwise. Park owner decisions in parking-lot.md. Stop only when every box is ticked or a stop-work order exists."

# One spawn attempt; the resumed session may legitimately run for hours. shellcheck disable:
# $AGENT is an owner-provided command line; word-splitting is intended, as in foreman.
spawn() { # $1 optionally overrides the agent for this one attempt
  local a="${1:-$AGENT}"
  # shellcheck disable=SC2086
  $a "$PROMPT" >/dev/null 2>&1
}

# The transcript the tells read: the shift's own, recorded by the hooks; the newest in the
# project's transcript directory is the fallback before the record exists.
resolve_transcript() {
  local f latest=""
  latest="$(shift_transcript)"
  if [ -n "$latest" ] && [ -f "$latest" ]; then printf '%s' "$latest"; return; fi
  latest=""
  for f in "$TRANSCRIPTS"/*.jsonl; do
    [ -f "$f" ] || continue
    if [ -z "$latest" ] || [ "$f" -nt "$latest" ]; then latest="$f"; fi
  done
  printf '%s' "$latest"
}

# The Esc tell: an interrupt marker in the transcript tail means the owner paused the session on
# purpose. Only the tail — an interrupt mid-history with work after it is a session that already
# moved on.
owner_paused() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] || return 1
  tail -n 25 "$t" 2>/dev/null | grep -q "Request interrupted by user"
}

# The wedge tell: Claude Code writes API failures verbatim into the transcript ("API Error: 500
# Internal server error", "529 Overloaded", "Connection closed mid-response"). An error at the
# tail of a quiet transcript whose process still lives is a session sitting at an errored prompt
# with nobody there to press retry. The [^\\] guard skips the escaped quote of a session merely
# TALKING about API errors — only the host's own event starts the JSON string with the phrase.
errored_tail() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] || return 1
  tail -n 25 "$t" 2>/dev/null | grep -q '[^\\]"API Error:'
}

# Primary pulse: a live session streams every turn into its transcript, even when the work
# writes no project files — long reasoning, research, a wall of tool output.
transcript_pulse() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] && [ "$t" -nt "$SENTINEL" ]
}

site_moved() {
  # -type f: a directory's mtime moves whenever anything inside it is created or removed — the
  # watchman's own bookkeeping would read as site life. Files are the signal, directories noise.
  find "$PROJECT" -path "$NS/.watchman*" -prune -o -type f -newer "$SENTINEL" -print 2>/dev/null |
    grep -q .
}

# The process witness. 0: the recorded process is alive — pid checked with kill -0 and the start
# time re-read, because a reused pid wears the number but not the birthday. 1: provably dead.
# 2: nothing recorded to check.
shift_process_alive() {
  local pid start now
  pid="$(shift_pid)"
  case "$pid" in '' | *[!0-9]*) return 2 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  start="$(shift_pid_start)"
  if [ -n "$start" ]; then
    now="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ "$now" = "$start" ] || return 1
  fi
  return 0
}

# Fallback witness when no pid was recorded: any claude process whose working directory is this
# project. Not the shift's identity — just reason enough not to spawn beside it.
project_has_claude() {
  local p comm cwd
  for p in $(pgrep -f claude 2>/dev/null); do
    comm="$(ps -o comm= -p "$p" 2>/dev/null)"
    case "${comm##*/}" in claude) ;; *) continue ;; esac
    if [ -r "/proc/$p/cwd" ]; then
      cwd="$(readlink "/proc/$p/cwd" 2>/dev/null)"
    else
      cwd="$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
    fi
    case "$cwd" in "$PROJECT" | "$PROJECT"/*) return 0 ;; esac
  done
  return 1
}

# Re-evaluated before every retry attempt: an honest ending arriving, the site coming back to
# life, or the owner acting mid-wake cancels the remaining attempts. Empty means revival is
# still warranted.
hold_reason() {
  if [ -f "$NS/STOP" ]; then printf 'stop-work order'; return; fi
  if [ -f "$NS/.ended" ] || [ ! -f "$PUNCH" ]; then printf 'shift ended'; return; fi
  if [ "$(open_boxes)" -eq 0 ]; then printf 'all boxes ticked'; return; fi
  if deadline_passed; then printf 'deadline passed'; return; fi
  if [ -f "$NS/.session-end" ]; then printf 'clean session end'; return; fi
  if transcript_pulse || site_moved; then printf 'site activity'; return; fi
  if owner_paused; then printf 'owner Esc'; return; fi
  shift_process_alive
  case $? in
    0) errored_tail || printf 'live shift process' ;;
    2) if project_has_claude; then printf 'a live claude session in the project'; fi ;;
  esac
}

log_line "watchman armed · every ${INTERVAL_MIN}m"
: >"$SENTINEL"
wake=0
misses=0
standby_prev=""

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

  # The liveness ladder. Revival needs strong positive evidence of death — the one truly harmful
  # failure is a second agent beside a living one, so every uncertain reading stands by.
  if transcript_pulse || site_moved; then
    misses=0
    standby_prev=""
  else
    verdict=""
    if owner_paused; then
      # Esc means stop. Stand by rather than down: if the owner resumes and a 500 kills it
      # later, the next quiet wake will find an errored tail, not an interrupt, and revive.
      verdict="esc"
    else
      shift_process_alive
      case $? in
        0) if errored_tail; then verdict="wedge"; else verdict="silent"; fi ;;
        2) if project_has_claude; then verdict="tabs"; fi ;;
      esac
    fi
    case "$verdict" in
      esc)
        [ "$standby_prev" = "esc" ] || log_line "watchman: owner pressed Esc — standing by, not resuming (STOP ends the shift; resuming re-arms)"
        standby_prev="esc"
        misses=0
        ;;
      silent)
        [ "$standby_prev" = "silent" ] || log_line "watchman: shift process alive with a quiet transcript — long silent work; standing by"
        standby_prev="silent"
        misses=0
        ;;
      tabs)
        [ "$standby_prev" = "tabs" ] || log_line "watchman: a claude session is live in this project — standing by"
        standby_prev="tabs"
        misses=0
        ;;
      *)
        standby_prev=""
        [ "$verdict" != "wedge" ] || log_line "watchman: probable wedge — shift process alive at an errored prompt; reviving its conversation"
        attempt=0
        revived=1
        aborted=""
        # shellcheck disable=SC2086  # RETRY_SPACING is a space-separated list; splitting is the point
        set -- $RETRY_SPACING ""
        total=$#
        for spacing in "$@"; do
          attempt=$((attempt + 1))
          if [ "$attempt" -gt 1 ]; then
            # Re-check the whole ladder: a site that came back to life mid-wake — or an owner
            # who acted — cancels the remaining attempts.
            aborted="$(hold_reason)"
            if [ -n "$aborted" ]; then
              log_line "watchman: $aborted during retries — holding the remaining attempts"
              break
            fi
          fi
          log_line "watchman: site quiet ${INTERVAL_MIN}m+ with open boxes — resume attempt $attempt ($(rung_label "$attempt" "$total"))"
          if spawn "$(rung_agent "$attempt" "$total")"; then
            revived=0
            break
          fi
          # Re-baseline: the failed attempt may have appended its own error to the transcript.
          # Only what moves AFTER this line is site life.
          : >"$SENTINEL"
          [ -n "$spacing" ] || break
          sleep "$spacing"
        done
        if [ "$revived" -eq 0 ]; then
          misses=0
          log_line "watchman: resumed session returned — re-checking next wake"
        elif [ -n "$aborted" ]; then
          misses=0
        else
          misses=$((misses + 1))
          log_line "watchman: all $attempt attempts failed (api down?) — backing off"
        fi
        ;;
    esac
  fi

  : >"$SENTINEL" # after all actions, so the watchman's own writes never read as site life
  if [ "$MAX_WAKES" -gt 0 ] && [ "$wake" -ge "$MAX_WAKES" ]; then exit 7; fi
done
