#!/usr/bin/env bash
# watchman.sh — the night watchman. Revives a session that DIES mid-shift; never one that ended.
#
# A Stop hook can only act inside a living session. A session killed by an API outage, a crash,
# or a closed terminal fires no hooks — the punch list survives on disk, but nothing re-invokes
# the agent, and the night is lost. The watchman is the outside half: armed at shift start, it
# wakes every interval and, only when the site is BOTH mid-shift and dead quiet, resumes the
# shift's OWN conversation by id — the hours of context it already had, not a briefing. Only if
# that conversation is itself unusable does it fall back, and the punch list on disk is what
# carries a fresh session when it must. A persisted .nightshift/work-target tells that session
# which child repository contains the code when run state lives in a parent workspace.
#
#   watchman.sh [--project DIR] [--interval MIN] [--agent CMD] [--max-wakes N]
#
#   --interval  minutes between wakes (default: the rules file's watchMinutes, overridable by
#               $NIGHTSHIFT_WATCH; 0 exits immediately — the "disabled" spelling)
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
# Liveness is a ladder, session-first — revival needs strong positive evidence of death,
# because the one truly harmful failure is spawning a second agent beside a living one (a
# resumed id APPENDS to the same session; two writers interleave). Only the session's own
# signals testify; project files never vote — a detached loop, a build, or a sync writing
# files can neither mute the owner's Esc nor mask a dead session as alive:
#   1. interrupt marker in the transcript tail       -> owner pressed Esc; stand by
#   2. the shift's transcript moved since last wake  -> alive (a session streams every turn)
#   3. recorded pid alive (start time verified)      -> transcript's last word is the host's own
#                                                       API-error event? the 500 wedge: alive but
#                                                       errored, nobody home — revive.
#                                                       Otherwise -> long silent work; stand by
#   4. `claude agents --json` (the host's roster)    -> id present: alive, wedge rule as above —
#                                                       it even rescues a stale recorded pid;
#                                                       a clean roster without it: dead; revive
#   5. pid provably dead, or roster without the id   -> dead; revive
#   6. neither oracle answered                       -> a claude process working in the project
#                                                       stands it by; else dead; revive
#   7. no identity recorded at all                   -> transcript ends in the error -> the
#                                                       wedge again (a 500 can land before the
#                                                       first tool call records identity;
#                                                       --continue resumes that conversation);
#                                                       a claude process in the project stands
#                                                       it by; else dead; revive
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
# API outages: per wake, up to 3 spawn attempts spaced by the rules file's watchRetrySeconds
# (shipped "30 120"; $NIGHTSHIFT_WATCH_RETRY overrides). A wake that fails entirely just waits
# for the next one — the watchman knocks every interval, all night, until the API answers.
# Exit: 0 stood down honestly · 1 usage/lock · 7 wake cap (tests).
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../../lib/lib.sh" # pure-bash path — no dirname dependency

PROJECT="$PWD"
INTERVAL_MIN="${NIGHTSHIFT_WATCH:-}" # resolved from the rules file once the project is known
AGENT="${NIGHTSHIFT_WATCH_AGENT:-claude --continue -p}"
AGENT_IS_DEFAULT=1
[ -z "${NIGHTSHIFT_WATCH_AGENT:-}" ] || AGENT_IS_DEFAULT=0
MAX_WAKES=0

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

cd "$PROJECT" 2>/dev/null || exit 1
PROJECT="$PWD"
WORK_TARGET="$(ns_work_target "$PROJECT" 2>/dev/null || true)"
[ -n "$WORK_TARGET" ] || WORK_TARGET="$PROJECT"

cd "$PROJECT" || { printf 'watchman: cannot cd to %s\n' "$PROJECT" >&2; exit 1; }
PROJECT="$PWD"

# One copy: the rules file is the config; a flag or env var is a session-start override. The
# shipped values live visibly in the file setup copies — there are no fallbacks hiding here,
# and a missing knob refuses to arm, loudly, naming the repair.
NS="$PROJECT/.nightshift"
[ -d "$NS" ] || { printf 'watchman: no .nightshift at %s\n' "$PROJECT" >&2; exit 1; }
note() { ns_record_reason "$NS" "$1" "${2:-}"; }
[ -n "$INTERVAL_MIN" ] || INTERVAL_MIN="$(rule "$PROJECT" watchMinutes "")"
case "$INTERVAL_MIN" in
  '' | *[!0-9]*)
    note unreadable-rules watchMinutes
    printf 'watchman: watchMinutes missing or not whole minutes — .nightshift/rules.json absent or incomplete; re-run /nightshift:setup\n' >&2
    exit 1
    ;;
esac
[ "$INTERVAL_MIN" -gt 0 ] || exit 0 # 0 = disabled, by design
RETRY_SPACING="$(rule "$PROJECT" watchRetrySeconds "${NIGHTSHIFT_WATCH_RETRY:-}")"
NOTIFY="$(rule "$PROJECT" notifyCommand "${NIGHTSHIFT_NOTIFY_CMD:-}")" # empty = silent, a real value
PUNCH="$NS/punch-list.md"
PIDFILE="$NS/.watchman"
SENTINEL="$NS/.watchman-tick"

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

# Counted below the `## Items` heading only, exactly as the gate counts them — a watchman that
# read a checkbox out of the contract prose would keep reviving a shift the gate considers done.
open_boxes() { ns_open_boxes "$PUNCH"; }

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

# A resumed conversation carries its own context — the thread IS the instruction, and the gate
# does the enforcing. Its order is one line: you were cut off, keep going. Only the
# fresh-session fallback, which starts empty, gets the full pointer at the punch list. Both are
# the owner's to word (rules file keys: revivalPrompt, freshRevivalPrompt).
PROMPT_RESUME="$(rule "$PROJECT" revivalPrompt "${NIGHTSHIFT_REVIVAL_PROMPT:-}")"
PROMPT_FRESH="$(rule "$PROJECT" freshRevivalPrompt "${NIGHTSHIFT_FRESH_PROMPT:-}")"
for _req in "watchRetrySeconds:$RETRY_SPACING" "revivalPrompt:$PROMPT_RESUME" "freshRevivalPrompt:$PROMPT_FRESH"; do
  if [ -z "${_req#*:}" ]; then
    note unreadable-rules "${_req%%:*}"
    printf 'watchman: %s missing — .nightshift/rules.json absent or incomplete; re-run /nightshift:setup\n' "${_req%%:*}" >&2
    log_line "watchman: rules.json is missing ${_req%%:*} — cannot arm; re-run /nightshift:setup"
    exit 1
  fi
done

# Resumed rungs get the short order; the fresh rung gets the map. Attempts mirror rung_agent.
rung_prompt() { # $1 attempt, $2 total attempts this wake
  if [ "$1" -ge "$2" ] && [ "$2" -gt 1 ]; then printf '%s' "$PROMPT_FRESH"; else printf '%s' "$PROMPT_RESUME"; fi
}

# One spawn attempt; the resumed session may legitimately run for hours. shellcheck disable:
# $AGENT is an owner-provided command line; word-splitting is intended.
spawn() { # $1 optionally overrides the agent for this one attempt; $2 the order for its rung
  local a="${1:-$AGENT}" p="${2:-$PROMPT_RESUME}"
  # NIGHTSHIFT_REVIVAL marks the child for the hooks: a revival session ending is never the
  # owner's hand on the door — without the mark, the worker's own exit would write .session-end
  # under the recorded id and stand the watchman down mid-outage.
  # shellcheck disable=SC2086
  ( cd "$WORK_TARGET" && CLAUDE_PROJECT_DIR="$PROJECT" NIGHTSHIFT_REVIVAL=1 $a "$p" >/dev/null 2>&1 )
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

# The Esc tell: the owner's interrupt matters only as the transcript's LAST WORD — the same
# rule as the wedge. An interrupt the owner already resumed past has newer conversation events
# after it and is history, not a pause; a real death right after such a resume must read as
# death. Trailing bookkeeping lines are not conversation and cannot mask the marker.
owner_paused() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] || return 1
  tail -n 25 "$t" 2>/dev/null | awk '
    /[^\\]"type"[[:space:]]*:[[:space:]]*"(user|assistant)"/ {
      esc = /Request interrupted by user/
    }
    END { exit esc ? 0 : 1 }'
}

# The wedge tell: Claude Code records an API failure as its own synthetic assistant event,
# flagged "isApiErrorMessage":true at the top level — an owner pasting "API Error: 500" into a
# prompt carries no such field, and prose quoting the field arrives with its quotes escaped,
# which the [^\\] guard skips. The wedge is the session sitting at that errored prompt NOW, so
# the flag must be on the LAST conversation event (user or assistant): anything after it —
# a retry, an answer, the owner's next prompt — means somebody already acted, and a session
# whose owner is awake at the keyboard is not the watchman's to touch. Trailing bookkeeping
# lines (summaries, snapshots) are not conversation and cannot mask the wedge.
errored_tail() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] || return 1
  tail -n 25 "$t" 2>/dev/null | awk '
    /[^\\]"type"[[:space:]]*:[[:space:]]*"(user|assistant)"/ {
      wedge = /[^\\]"isApiErrorMessage"[[:space:]]*:[[:space:]]*true/
    }
    END { exit wedge ? 0 : 1 }'
}

# Primary pulse: a live session streams every turn into its transcript, even when the work
# writes no project files — long reasoning, research, a wall of tool output.
transcript_pulse() {
  local t
  t="$(resolve_transcript)"
  [ -n "$t" ] && [ "$t" -nt "$SENTINEL" ]
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

# The registry witness: `claude agents --json` is the host's own roster of every live session,
# interactive and background. The recorded id present is the host saying the shift is alive; a
# clean roster without it is the host saying it is gone. 0 present · 1 absent · 2 no record, or
# a CLI without the command — which proves nothing.
registry_state() {
  local sid out
  sid="$(shift_session_id)"
  [ -n "$sid" ] || return 2
  out="$(claude agents --json 2>/dev/null)" || return 2
  case "$out" in \[*) ;; *) return 2 ;; esac
  printf '%s' "$out" | grep -qF "\"$sid\"" && return 0
  return 1
}

# The verdict, session-first. The session's own signals decide — the owner's Esc above all,
# then the shift's transcript, then its process, then the host's registry. Project files never
# vote: folder noise (a detached loop, a build, a sync) must never mute the owner's Esc, and
# must never mask a dead session as alive.
site_verdict() { # prints: esc | alive | silent | wedge | tabs | dead
  local sid ps rg
  if owner_paused; then printf 'esc'; return; fi
  if transcript_pulse; then printf 'alive'; return; fi
  sid="$(shift_session_id)"
  if [ -n "$sid" ]; then
    shift_process_alive
    ps=$?
    if [ "$ps" -eq 0 ]; then
      if errored_tail; then printf 'wedge'; else printf 'silent'; fi
      return
    fi
    registry_state
    rg=$?
    if [ "$rg" -eq 0 ]; then
      # The pid may be stale or unrecorded, but the host lists the session — alive.
      if errored_tail; then printf 'wedge'; else printf 'silent'; fi
      return
    fi
    if [ "$ps" -eq 1 ] || [ "$rg" -eq 1 ]; then printf 'dead'; return; fi
    # Identity recorded but no oracle answered: the conservative reading.
    if project_has_claude; then printf 'tabs'; return; fi
    printf 'dead'
    return
  fi
  # No identity recorded — a 500 can land before the first tool call writes one. The newest
  # conversation ending in the host's error event is the wedge; --continue resumes it.
  if errored_tail; then printf 'wedge'; return; fi
  if project_has_claude; then printf 'tabs'; return; fi
  printf 'dead'
}

# Re-evaluated before every retry attempt: an honest ending arriving, the session coming back
# to life, or the owner acting mid-wake cancels the remaining attempts. Empty means revival is
# still warranted.
hold_reason() {
  if [ -f "$NS/STOP" ]; then printf 'stop-work order'; return; fi
  if [ -f "$NS/.ended" ] || [ ! -f "$PUNCH" ]; then printf 'shift ended'; return; fi
  if [ "$(open_boxes)" -eq 0 ]; then printf 'all boxes ticked'; return; fi
  if deadline_passed; then printf 'deadline passed'; return; fi
  if [ -f "$NS/.session-end" ]; then printf 'clean session end'; return; fi
  case "$(site_verdict)" in
    alive) printf 'session activity' ;;
    esc) printf 'owner Esc' ;;
    silent) printf 'live shift session' ;;
    tabs) printf 'a live claude session in the project' ;;
  esac
}

log_line "watchman armed · every ${INTERVAL_MIN}m"
: >"$SENTINEL"
wake=0
standby_prev=""
down_notified=0

# NIGHTSHIFT_WATCH_SLEEP overrides the base sleep in seconds — the test suite's speed lever.
BASE_SLEEP="${NIGHTSHIFT_WATCH_SLEEP:-$((INTERVAL_MIN * 60))}"

while :; do
  sleep "$BASE_SLEEP"
  wake=$((wake + 1))

  if [ -f "$NS/STOP" ]; then note owner-stop; log_line "watchman: stop-work order — standing down"; exit 0; fi
  if [ -f "$NS/.ended" ]; then note completed; exit 0; fi
  if [ ! -f "$PUNCH" ]; then note stand-down "punch list missing"; exit 0; fi
  # This watchman revives Claude sessions. A record naming another host belongs to that host's
  # watchman: resuming it here would spawn claude against a shift another agent is working.
  host="$(ns_session_host "$NS")"
  if [ "$host" != claude ]; then
    note wrong-host "$host"
    log_line "watchman: shift is owned by $host — standing down"
    exit 0
  fi
  if [ "$(open_boxes)" -eq 0 ]; then
    log_line "watchman: every box ticked but the shift never clocked out — spawning the clock-out"
    spawn "$(resolve_agent)" "$(rung_prompt 1 2)" || true
    note completed
    exit 0
  fi
  if deadline_passed; then
    log_line "watchman: quitting time passed with the site dead — spawning the clock-out"
    spawn "$(resolve_agent)" "$(rung_prompt 1 2)" || true
    note deadline
    exit 0
  fi
  if [ -f "$NS/.session-end" ]; then
    note clean-session-end
    log_line "watchman: clean session end — the owner closed it; standing down (start re-arms)"
    exit 0
  fi

  # The liveness ladder, session-first (site_verdict). Revival needs strong positive evidence
  # of death — the one truly harmful failure is a second agent beside a living one, so every
  # uncertain reading stands by. Esc is read before everything else: if the owner resumes and a
  # 500 kills it later, the next wake finds an errored tail, not an interrupt, and revives.
  verdict="$(site_verdict)"
  case "$verdict" in
      alive)
        standby_prev=""
        down_notified=0
        ;;
      esc)
        note esc-standby
        [ "$standby_prev" = "esc" ] || log_line "watchman: owner pressed Esc — standing by, not resuming (STOP ends the shift; resuming re-arms)"
        standby_prev="esc"
        down_notified=0
        ;;
      silent)
        note silent-standby
        [ "$standby_prev" = "silent" ] || log_line "watchman: the shift session is alive with a quiet transcript — long silent work; standing by"
        standby_prev="silent"
        down_notified=0
        ;;
      tabs)
        note silent-standby "live claude in project"
        [ "$standby_prev" = "tabs" ] || log_line "watchman: a claude session is live in this project — standing by"
        standby_prev="tabs"
        down_notified=0
        ;;
      wedge | dead)
        standby_prev=""
        sid="$(shift_session_id)"
        [ "$verdict" != "wedge" ] || log_line "watchman: probable wedge — a session sits at an errored prompt with nobody there; reviving its conversation"
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
          if spawn "$(rung_agent "$attempt" "$total")" "$(rung_prompt "$attempt" "$total")"; then
            revived=0
            break
          fi
          # Re-baseline: the failed attempt may have appended its own error to the transcript.
          # Only what moves AFTER this line is site life.
          : >"$SENTINEL"
          [ -n "$spacing" ] || break
          sleep "$spacing"
        done
        # A successful revival is morning news, not a page: it lands in the parking lot — the
        # file the owner reads — with the thread's handles. The page is reserved for the one
        # night event that needs the owner: a dead session no attempt could bring back, rung
        # once per outage, not once per wake.
        if [ "$revived" -eq 0 ]; then
          down_notified=0
          if [ "$AGENT_IS_DEFAULT" -eq 1 ] && [ "$attempt" -ge "$total" ] && [ "$total" -gt 1 ]; then
            note fresh-fallback
          elif [ -z "$sid" ]; then
            note fresh-fallback
          else
            note revived
          fi
          if [ -n "$sid" ]; then
            log_line "watchman: resumed session returned — the night is one thread: claude --resume $sid · vscode://anthropic.claude-code/open?session=$sid"
            printf -- '- [notice] %s — the shift session died and the watchman revived it. One thread: claude --resume %s · cursor://anthropic.claude-code/open?session=%s · vscode://anthropic.claude-code/open?session=%s\n' \
              "$(ts)" "$sid" "$sid" "$sid" >>"$NS/parking-lot.md"
          else
            log_line "watchman: resumed session returned — re-checking next wake"
            printf -- '- [notice] %s — the shift session died and the watchman revived it (details in shift-log.md).\n' "$(ts)" >>"$NS/parking-lot.md"
          fi
        elif [ -z "$aborted" ]; then
          note exhausted-retry
          log_line "watchman: all $attempt attempts failed (api down?) — knocking again in ${INTERVAL_MIN}m"
          if [ -n "$NOTIFY" ] && [ "$down_notified" -eq 0 ]; then
            down_notified=1
            summary="nightshift: the shift session is down and revival failed — it needs you${sid:+: claude --resume $sid}"
            NIGHTSHIFT_SUMMARY="$summary" sh -c "$NOTIFY" nightshift "$summary" >/dev/null 2>&1 || true
          fi
        fi
        ;;
  esac

  : >"$SENTINEL" # after all actions, so the watchman's own writes never read as site life
  if [ "$MAX_WAKES" -gt 0 ] && [ "$wake" -ge "$MAX_WAKES" ]; then exit 7; fi
done
