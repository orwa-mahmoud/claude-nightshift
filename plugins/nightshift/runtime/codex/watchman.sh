#!/usr/bin/env bash
# watchman.sh — the night watchman for Codex shifts. Revives a session that DIED mid-shift;
# never one that ended, and never another host's.
#
# A hook can only act inside a living session; a session killed by an API outage, a crash, or a
# closed terminal fires nothing, and the punch list just sits there. This is the outside half for
# Codex: armed at shift start, it wakes every interval and, only when the site is mid-shift and
# provably dead quiet, resumes the shift's own conversation —
#
#   codex exec resume -c 'sandbox_mode="danger-full-access"' <session-id> "<revival order>"
#
# A persisted .nightshift/work-target keeps the resumed session aimed at the same child repository
# when run state lives in a parent workspace. The command appends to the same rollout the session
# was writing when it died (verified live: a
# SIGKILLed session's rollout ends mid-event with no terminal marker, and the resume continues
# that very file). The fallback is a fresh headless run; the punch list on disk is its handover.
#
# The sandbox grant is danger-full-access because the workspace-write sandbox protects .git —
# a revived session could edit but never commit (verified live: "Git cannot create
# .git/index.lock"), and one commit per item IS the contract. The fence around that access is
# nightshift's own guards: the hardhat denies what the owner forbade, in every mode — the same
# trade Claude Code makes with bypassPermissions.
#
#   watchman.sh [--project DIR] [--interval MIN] [--agent CMD] [--max-wakes N]
#
#   --interval  minutes between wakes (default: the rules file's watchMinutes, overridable by
#               $NIGHTSHIFT_WATCH; 0 exits immediately — the "disabled" spelling)
#   --agent     override the spawn command entirely (the test suite's lever). It is invoked as
#               $AGENT "<prompt>" with the project as cwd.
#   --max-wakes bound the number of wakes (0 = unbounded; tests use this)
#
# Evidence, conservative by construction — revive only on strong positive evidence of death:
#   ALIVE (stand by), any of:
#     · the recorded pid (line 3) exists and its start time matches line 4
#     · any process whose executable is exactly `codex` has this project as its cwd
#     · the recorded rollout (line 2) grew since the last wake
#   DEAD (revive): none of the above, boxes open, and the site armed.
# There is no owner-interrupt tell on Codex yet: an owner who closes an interactive session with
# open boxes is handing the night to the watchman — that is the product's stance, and the
# stop-work order (.nightshift/STOP) is the off switch. The 500-wedge signature (an API error as
# the rollout's last word) has not been observed on Codex and is deliberately not guessed at;
# a live-but-erroring session reads as alive and is left alone.
#
# Stand-down order, checked at every wake — never override an honest ending:
#   1. stop-work order (.nightshift/STOP)             -> down
#   2. shift ended (.nightshift/.ended, or no punch)  -> down
#   3. another host's shift (.shift-session line 5)   -> down (its own watchman minds it)
#   4. every box ticked                                -> one clock-out spawn if .ended missing,
#                                                        then down (a crash at the finish line
#                                                        still gets receipts and the whistle)
#   5. deadline passed                                 -> one clock-out spawn, then down
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../../lib/lib.sh" # pure-bash path — no dirname dependency

PROJECT="$PWD"
INTERVAL_MIN="${NIGHTSHIFT_WATCH:-}"
AGENT="${NIGHTSHIFT_WATCH_AGENT:-}"
MAX_WAKES=0

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
need_value() { [ "$2" -ge 2 ] || { printf 'watchman: %s needs a value\n' "$1" >&2; usage; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --project) need_value "$1" $#; PROJECT="$2"; shift 2 ;;
    --interval) need_value "$1" $#; INTERVAL_MIN="$2"; shift 2 ;;
    --agent) need_value "$1" $#; AGENT="$2"; shift 2 ;;
    --max-wakes) need_value "$1" $#; MAX_WAKES="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) printf 'watchman: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

cd "$PROJECT" 2>/dev/null || exit 1
PROJECT="$PWD"
NS="$PROJECT/.nightshift"
WORK_TARGET="$(ns_work_target "$PROJECT" 2>/dev/null || true)"
[ -n "$WORK_TARGET" ] || WORK_TARGET="$PROJECT"
PUNCH="$NS/punch-list.md"
LOG="$NS/shift-log.md"
TICK="$NS/.watchman-tick"
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
PROMPT_RESUME="$(rule "$PROJECT" revivalPrompt "${NIGHTSHIFT_REVIVAL_PROMPT:-}")"
PROMPT_FRESH="$(rule "$PROJECT" freshRevivalPrompt "${NIGHTSHIFT_FRESH_PROMPT:-}")"
for _req in "watchRetrySeconds:$RETRY_SPACING" "revivalPrompt:$PROMPT_RESUME" "freshRevivalPrompt:$PROMPT_FRESH"; do
  if [ -z "${_req#*:}" ]; then
    note unreadable-rules "${_req%%:*}"
    printf 'watchman: %s unreadable — .nightshift/rules.json absent or incomplete; re-run /nightshift:setup\n' "${_req%%:*}" >&2
    exit 1
  fi
done

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_line() { [ -d "$NS" ] && printf '%s · %s\n' "$(ts)" "$1" >>"$LOG"; }

# One watchman per site — either host's. A stale pidfile from a dead holder is taken over.
PIDFILE="$NS/.watchman"
if [ -f "$PIDFILE" ]; then
  oldpid="$(sed -n 1p "$PIDFILE" 2>/dev/null)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    printf 'watchman: already watching (pid %s)\n' "$oldpid" >&2
    exit 1
  fi
fi
printf '%s\n' "$$" >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

sid()        { sed -n 1p "$NS/.shift-session" 2>/dev/null; }
rollout()    { sed -n 2p "$NS/.shift-session" 2>/dev/null; }
rec_pid()    { sed -n 3p "$NS/.shift-session" 2>/dev/null | tr -d '[:space:]'; }
rec_start()  { sed -n 4p "$NS/.shift-session" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
open_boxes() { ns_open_boxes "$PUNCH"; }

# The recorded pid counts only as the exact recorded process: pid + start time, a pair that pid
# reuse cannot counterfeit.
recorded_process_alive() {
  local p s now
  p="$(rec_pid)"; s="$(rec_start)"
  [ -n "$p" ] && [ -n "$s" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  now="$(ps -o lstart= -p "$p" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$now" ] && [ "$now" = "$s" ]
}

# Any codex working in this project stands the watchman by — matched on the exact executable
# name, never a substring: unrelated processes carry "codex" deep in their environment.
codex_in_project() {
  local p cwd
  for p in $(pgrep -x codex 2>/dev/null); do
    cwd="$(lsof -a -d cwd -p "$p" -Fn 2>/dev/null | sed -n 's/^n//p' | sed -n 1p)"
    [ "$cwd" = "$PROJECT" ] && return 0
  done
  return 1
}

# The rollout is the session's own pulse: a live session streams events into it. Growth since
# the last wake is life; the sentinel is re-baselined every wake and after every failed spawn so
# the watchman's own attempts never read as site activity.
ROLLOUT_SEEN=""
baseline_rollout() {
  local r
  r="$(rollout)"
  [ -n "$r" ] && [ -f "$r" ] && ROLLOUT_SEEN="$(wc -c <"$r" 2>/dev/null | tr -d ' ')" || ROLLOUT_SEEN=""
}
rollout_grew() {
  local r now
  r="$(rollout)"
  [ -n "$r" ] && [ -f "$r" ] || return 1
  now="$(wc -c <"$r" 2>/dev/null | tr -d ' ')"
  [ -n "$ROLLOUT_SEEN" ] && [ "$now" != "$ROLLOUT_SEEN" ]
}

# Spawn one revival attempt. Rung 1 resumes the recorded conversation; rung 2 is a fresh
# headless run with the punch list as its handover. NIGHTSHIFT_REVIVAL marks the child for the
# hooks, so it inherits the shift's binding whatever id the fallback gave it.
# A non-resumable recorded id is never passed to `codex exec resume` and never treated as a
# successful resume of that thread.
spawn() { # $1 = rung (1|2)
  local prompt kind
  if [ -n "$AGENT" ]; then
    if [ "$1" -eq 1 ]; then prompt="$PROMPT_RESUME"; else prompt="$PROMPT_FRESH"; fi
    ( cd "$WORK_TARGET" && CODEX_PROJECT_DIR="$PROJECT" NIGHTSHIFT_REVIVAL=1 $AGENT "$prompt" >/dev/null 2>&1 )
    return $?
  fi
  if [ "$1" -eq 1 ]; then
    kind="$(ns_codex_identity_kind "$(sid)")"
    if [ "$kind" = "resumable" ]; then
      ( cd "$WORK_TARGET" && CODEX_PROJECT_DIR="$PROJECT" NIGHTSHIFT_REVIVAL=1 codex exec resume -c 'sandbox_mode="danger-full-access"' "$(sid)" "$PROMPT_RESUME" >/dev/null 2>&1 )
      return $?
    fi
  fi
  ( cd "$WORK_TARGET" && CODEX_PROJECT_DIR="$PROJECT" NIGHTSHIFT_REVIVAL=1 codex exec -s danger-full-access "$PROMPT_FRESH" >/dev/null 2>&1 )
}

rung_name() { if [ "$1" -eq 1 ] && [ -n "$(sid)" ]; then printf 'resuming the recorded conversation'; else printf 'fresh session'; fi; }

log_line "watchman (codex) armed · every ${INTERVAL_MIN}m"
BASE_SLEEP="${NIGHTSHIFT_WATCH_SLEEP:-$((INTERVAL_MIN * 60))}"
wake=0
baseline_rollout
: >"$TICK" 2>/dev/null || true

while :; do
  sleep "$BASE_SLEEP"
  wake=$((wake + 1))

  if [ -f "$NS/STOP" ]; then note owner-stop; log_line "watchman: stop-work order — standing down"; exit 0; fi
  if [ -f "$NS/.ended" ]; then note completed; exit 0; fi
  if [ ! -f "$PUNCH" ]; then note stand-down "punch list missing"; exit 0; fi

  # Another host's shift is another watchman's business: resuming it from here would spawn
  # codex against a conversation a different agent owns.
  host="$(ns_session_host "$NS")"
  if [ "$host" != codex ]; then
    note wrong-host "$host"
    log_line "watchman: shift is owned by $host — standing down"
    exit 0
  fi

  if [ "$(open_boxes)" -eq 0 ]; then
    log_line "watchman: every box ticked but the shift never clocked out — spawning the clock-out"
    spawn 1 || true
    note completed
    exit 0
  fi
  if [ -f "$NS/deadline" ]; then
    dl="$(tr -d '[:space:]' <"$NS/deadline" 2>/dev/null)"
    if printf '%s' "$dl" | grep -qE '^[0-9]+$' && [ "$(date +%s)" -ge "$dl" ]; then
      log_line "watchman: past the deadline with the session gone — spawning the clock-out"
      spawn 1 || true
      note deadline
      exit 0
    fi
  fi

  # Life, in evidence order: the recorded process, any codex in the project, the rollout pulse.
  if recorded_process_alive || codex_in_project || rollout_grew; then
    note silent-standby
    baseline_rollout
    : >"$TICK" 2>/dev/null || true
    if [ "$MAX_WAKES" -gt 0 ] && [ "$wake" -ge "$MAX_WAKES" ]; then exit 0; fi
    continue
  fi

  # A recorded identity that cannot be resumed is not a missing first-record (that still gets
  # the fresh fallback). Guessing, or starting an unrelated conversation, would claim a thread
  # this watchman did not resume.
  if [ -z "$AGENT" ]; then
    kind="$(ns_codex_identity_kind "$(sid)")"
    if [ "$kind" != "resumable" ] && [ "$kind" != "missing" ]; then
      note non-resumable-session "$kind"
      log_line "watchman: recorded Codex identity is $kind — standing down; not resuming and not starting a fresh thread"
      exit 0
    fi
  fi

  # Dead quiet, mid-shift: revive. Up to 3 attempts this wake, re-checking life between them —
  # a site that comes back mid-wake cancels the rest.
  attempt=0
  revived=1
  for gap in 0 $RETRY_SPACING; do
    [ "$gap" -gt 0 ] && sleep "$gap"
    if recorded_process_alive || codex_in_project || rollout_grew; then
      note silent-standby
      log_line "watchman: session activity during retries — holding the remaining attempts"
      break
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le 3 ] || break
    log_line "watchman: site dead quiet mid-shift — resume attempt $attempt ($(rung_name $attempt))"
    if spawn "$attempt"; then
      revived=0
      if [ "$attempt" -ge 2 ] || [ -z "$(sid)" ]; then
        note fresh-fallback
      else
        note revived
      fi
      log_line "watchman: revival returned — the night continues: codex exec resume $(sid)"
      break
    fi
    baseline_rollout
  done
  if [ "$revived" -eq 1 ] && [ "$attempt" -gt 0 ]; then
    note exhausted-retry
  fi
  baseline_rollout
  : >"$TICK" 2>/dev/null || true

  if [ "$MAX_WAKES" -gt 0 ] && [ "$wake" -ge "$MAX_WAKES" ]; then exit 0; fi
done
