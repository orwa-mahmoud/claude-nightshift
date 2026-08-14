#!/usr/bin/env bash
# doctor.sh — read-only site diagnosis. Prints what Nightshift sees; never repairs.
#
#   doctor.sh [--project DIR]
#
# Exit: 0 report printed · 1 usage
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'doctor: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'doctor: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'doctor: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}

emit() { printf '%s\n' "$1"; }
fact() { FACTS="${FACTS}${FACTS:+
}$1"; }
warn() { WARNS="${WARNS}${WARNS:+
}$1"; }
act() { # safe|confirm|blocked  message
  ACTIONS="${ACTIONS}${ACTIONS:+
}[$1] $2"
}

FACTS=""
WARNS=""
ACTIONS=""

LINK="$HOST/.nightshift-link"
LINK_STATE="absent"
WORKSPACE="$HOST"
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  if WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)"; then
    LINK_STATE="valid"
    fact "task root $HOST links to workspace $WORKSPACE"
  else
    LINK_STATE="invalid"
    WORKSPACE="$HOST"
    warn "invalid .nightshift-link — Nightshift will not guess a workspace"
    act confirm "replace .nightshift-link with an absolute path to a directory that already contains .nightshift/, using runtime/link-workspace.sh"
  fi
else
  fact "task root is the workspace: $HOST"
fi

NS="$WORKSPACE/.nightshift"
STATE_KIND="absent"
STATE_VER=""
if [ -d "$NS" ]; then
  STATE_KIND="$(ns_state_kind "$WORKSPACE")"
  STATE_VER="$(ns_state_version "$WORKSPACE" || true)"
fi
if [ ! -d "$NS" ]; then
  warn "no .nightshift/ at $WORKSPACE"
  act confirm "run Nightshift setup in the real project (not a ChatGPT scratch workspace)"
  emit "Nightshift Doctor"
  emit "Host:        $HOST"
  emit "Workspace:   $WORKSPACE"
  emit "Link:        $LINK_STATE"
  emit "Nightshift:  missing"
  emit ""
  emit "Facts"
  printf '%s\n' "${FACTS:-none}"
  emit ""
  emit "Warnings"
  printf '%s\n' "${WARNS:-none}"
  emit ""
  emit "Actions (Doctor does not perform these)"
  printf '%s\n' "${ACTIONS:-none}"
  exit 0
fi

TARGET=""
if TARGET="$(ns_work_target "$WORKSPACE" 2>/dev/null)"; then
  fact "work target $TARGET"
else
  TARGET="$WORKSPACE"
  warn "work target could not be resolved; treating workspace as the code root"
fi

PUNCH="$NS/punch-list.md"
OPEN=0
TICKED=0
if [ -f "$PUNCH" ]; then
  OPEN="$(ns_open_boxes "$PUNCH")"
  TICKED="$(ns_ticked_boxes "$PUNCH")"
  fact "punch list open=$OPEN ticked=$TICKED"
else
  warn "punch-list.md is missing"
fi

ARMED=0
[ -f "$NS/.shift-armed" ] && ARMED=1
ENDED=0
[ -f "$NS/.ended" ] && ENDED=1
STOP=0
[ -f "$NS/STOP" ] && STOP=1
SESSION_END=0
[ -f "$NS/.session-end" ] && SESSION_END=1
STALL=""
[ -f "$NS/.stall" ] && STALL="$(tr -d '[:space:]' <"$NS/.stall" 2>/dev/null)"

if [ "$ARMED" -eq 1 ]; then fact "shift is armed"; else fact "shift is not armed"; fi
case "$STATE_KIND" in
  current)
    fact "state version ${STATE_VER:-$NS_STATE_VERSION} (current)"
    ;;
  legacy)
    fact "state version 0 (legacy — no state-version marker)"
    if [ "$ARMED" -eq 1 ]; then
      warn "legacy workspace cannot be migrated while a shift is armed"
      act blocked "wait until the shift is unarmed, then write version 1 with runtime/migrate-state.sh"
    else
      act confirm "write .nightshift/state-version as 1 with runtime/migrate-state.sh — only the marker is added"
    fi
    ;;
  future)
    warn "state version ${STATE_VER:-unknown} is newer than this plugin supports ($NS_STATE_VERSION)"
    act blocked "upgrade Nightshift; never rewrite or downgrade a newer state-version"
    ;;
  malformed)
    warn "state-version is malformed"
    act confirm "inspect .nightshift/state-version and replace it with a single integer while unarmed — never guess"
    ;;
esac
[ "$ENDED" -eq 1 ] && fact "gate has clocked the shift out (.ended)"
[ "$STOP" -eq 1 ] && fact "STOP is present"
[ "$SESSION_END" -eq 1 ] && fact "clean session-end marker is present"
[ -n "$STALL" ] && fact "stall count $STALL"

if [ "$ARMED" -eq 1 ] && [ "$OPEN" -eq 0 ] && [ "$ENDED" -eq 0 ]; then
  warn "armed with no open boxes and no .ended — clock-out may still be due"
  act confirm "ask Nightshift for status, or start so the watchman can spawn the clock-out"
fi
if [ "$STOP" -eq 1 ] && [ "$ARMED" -eq 1 ]; then
  warn "stop-work order is pending until the next stop attempt"
  act confirm "leave STOP in place until the working session ends; do not delete it mid-run"
fi
if [ "$STOP" -eq 1 ] && [ "$ARMED" -eq 0 ]; then
  warn "STOP leftover while no shift is armed — start will clear it"
  act confirm "run start when you want a new shift, which clears stale STOP"
fi

json_is_object() {
  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "object"' "$1" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d, dict) else 1)' "$1" 2>/dev/null
  else
    return 1
  fi
}

RULES="$NS/rules.json"
if [ ! -f "$RULES" ]; then
  warn "rules.json is missing — watchman will refuse to arm"
  act confirm "re-run setup and accept the shipped rules template"
elif json_is_object "$RULES"; then
  fact "rules.json is a JSON object"
  wm="$(rule "$WORKSPACE" watchMinutes "")"
  case "$wm" in
    '' | *[!0-9]*) warn "watchMinutes missing or not a whole number"; act confirm "restore watchMinutes from the shipped template (10, or 0 to disarm)" ;;
    *) fact "watchMinutes $wm" ;;
  esac
else
  warn "rules.json is unreadable or not a JSON object"
  act confirm "fix .nightshift/rules.json or re-run setup — never half-apply a broken file"
fi

HOST_REC="none"
SID="$(sed -n 1p "$NS/.shift-session" 2>/dev/null || true)"
TPATH="$(sed -n 2p "$NS/.shift-session" 2>/dev/null || true)"
SPID="$(sed -n 3p "$NS/.shift-session" 2>/dev/null | tr -d '[:space:]')"
if [ -f "$NS/.shift-session" ]; then
  HOST_REC="$(ns_session_host "$NS")"
  fact "recorded host $HOST_REC"
  if [ -n "$SID" ]; then
    fact "session id is present (not printed)"
    if [ "$HOST_REC" = "codex" ]; then
      kind="$(ns_codex_identity_kind "$SID")"
      fact "Codex identity kind $kind"
      if [ "$kind" != "resumable" ]; then
        warn "recorded Codex identity is $kind — watchman must not claim it resumed that thread"
        act blocked "capture a resumable Codex session id before relying on overnight revival"
      fi
    fi
  else
    warn "session id line is empty"
    act confirm "let the next tool call record identity, or accept a fresh-session fallback"
  fi
  if [ -n "$SPID" ] && printf '%s' "$SPID" | grep -qE '^[0-9]+$'; then
    if kill -0 "$SPID" 2>/dev/null; then
      fact "recorded pid $SPID is alive"
    else
      fact "recorded pid $SPID is dead"
    fi
  fi
else
  fact "no .shift-session yet"
  if [ "$ARMED" -eq 1 ] && [ "$OPEN" -gt 0 ]; then
    warn "armed shift has no session record — a 500 can land before first work"
  fi
fi

WPID=""
[ -f "$NS/.watchman" ] && WPID="$(sed -n 1p "$NS/.watchman" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$WPID" ] && printf '%s' "$WPID" | grep -qE '^[0-9]+$'; then
  if kill -0 "$WPID" 2>/dev/null; then
    fact "watchman pid $WPID is alive"
  else
    fact "watchman pid $WPID is stale"
    if [ "$ARMED" -eq 0 ]; then
      act safe "remove leftover .watchman — the recorded process is gone and no shift is armed"
    else
      act confirm "re-run start so the host watchman is armed; do not launch a second copy by hand beside a living one"
    fi
  fi
else
  fact "no live watchman pid file"
fi

RCODE="$(ns_reason_code "$NS")"
if [ -n "$RCODE" ]; then
  fact "watchman reason $RCODE ($(ns_reason_label "$RCODE"))"
fi

if [ "$ARMED" -eq 1 ] && [ "$OPEN" -gt 0 ] && [ -z "$WPID" ]; then
  warn "shift is armed with open boxes and no watchman"
  act confirm "re-run start so the host watchman is armed, or work the list in the live session"
fi

[ -n "$TPATH" ] && [ ! -f "$TPATH" ] && warn "recorded transcript/rollout path is not a readable file"

act blocked "Doctor never repairs, arms, stops, revives, or deletes"

emit "Nightshift Doctor"
emit "Host:        $HOST"
emit "Workspace:   $WORKSPACE"
emit "Link:        $LINK_STATE"
emit "Work target: $TARGET"
emit "Recorded:    ${HOST_REC:-none}"
emit "State:       ${STATE_VER:--} ($STATE_KIND)"
emit "Armed:       $ARMED  Open: $OPEN  Ticked: $TICKED  STOP: $STOP  Ended: $ENDED"
emit ""
emit "Facts"
printf '%s\n' "${FACTS:-none}"
emit ""
emit "Warnings"
printf '%s\n' "${WARNS:-none}"
emit ""
emit "Actions (Doctor does not perform these)"
printf '%s\n' "${ACTIONS:-none}"
exit 0
