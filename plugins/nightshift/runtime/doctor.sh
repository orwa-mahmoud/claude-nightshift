#!/usr/bin/env bash
# doctor.sh — read-only site diagnosis. Prints what Nightshift sees; never repairs.
#
#   doctor.sh [--project DIR]
#
# Exit: 0 report printed · 1 usage
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
_here="$(cd -P "$_here" && pwd)" || exit 1
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
    act confirm "replace .nightshift-link with an absolute path to a directory that already contains .nightshift/, using $_here/link-workspace.sh"
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
  act confirm "run Nightshift setup from the project you want to change (not a ChatGPT scratch workspace)"
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
UNUSABLE_RECV=0
if MODE="$(ns_work_mode "$WORKSPACE" 2>/dev/null)"; then
  fact "work mode $MODE"
  if [ "$MODE" = artifact ]; then
    fact "artifact receipts $(ns_receipts_count "$WORKSPACE")"
    if latest="$(ns_latest_receipt "$WORKSPACE")"; then
      fact "latest artifact receipt ${latest##*/}"
    fi
    recv="$(ns_receipts_dir "$WORKSPACE")"
    if [ -e "$recv" ] || [ -L "$recv" ]; then
      if ! ns_receipts_usable_dir "$WORKSPACE" >/dev/null; then
        UNUSABLE_RECV=1
        warn "artifact receipts path is not a usable directory"
        act confirm "replace the unusable receipts path with a real directory so write-receipt can land; Doctor does not rewrite it"
      fi
    fi
  fi
else
  MODE=""
  warn "work mode is malformed; treating the site as unusable until Setup rewrites it"
fi
if TARGET="$(ns_work_target "$WORKSPACE" 2>/dev/null)"; then
  fact "work target $TARGET"
else
  rc=$?
  TARGET="$WORKSPACE"
  if [ "$rc" -eq 3 ]; then
    warn "work target is a disposable scratch workspace"
  else
    warn "work target could not be resolved; treating workspace as the code root"
  fi
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

if [ "$MODE" = artifact ]; then
  if [ "${TICKED:-0}" -gt 0 ] && [ "$(ns_receipts_count "$WORKSPACE")" -eq 0 ] && [ "$UNUSABLE_RECV" -eq 0 ]; then
    warn "artifact mode has ticked items but no receipts"
    act confirm "complete ticked items with $_here/write-receipt.sh (native Windows: runtime/windows/write-receipt.ps1) or untick them; Doctor does not rewrite the punch list"
  fi
fi

ORDERS="$(ns_open_boxes_file "$NS/work-orders.md")"
if [ "$ORDERS" -gt 0 ]; then
  fact "pending Hunt work orders=$ORDERS"
fi
DRAFTS="$(ns_open_drafts "$NS/drafting-table.md")"
if [ "$DRAFTS" -gt 0 ]; then
  fact "staged drafting-table items=$DRAFTS"
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
      act blocked "wait until the shift is unarmed, then write version 1 with $_here/migrate-state.sh"
    else
      act confirm "write $NS/state-version as 1 with $_here/migrate-state.sh — only the marker is added"
    fi
    ;;
  future)
    warn "state version ${STATE_VER:-unknown} is newer than this plugin supports ($NS_STATE_VERSION)"
    act blocked "upgrade Nightshift; never rewrite or downgrade a newer state-version"
    ;;
  malformed)
    warn "state-version is malformed"
    act confirm "inspect $NS/state-version and replace it with a single integer while unarmed — never guess"
    ;;
esac
[ "$ENDED" -eq 1 ] && fact "gate has clocked the shift out (.ended)"
[ "$STOP" -eq 1 ] && fact "STOP is present"
[ "$SESSION_END" -eq 1 ] && fact "clean session-end marker is present"
[ -n "$STALL" ] && fact "stall count $STALL"

DEADLINE="$NS/deadline"
if [ ! -f "$DEADLINE" ]; then
  fact "deadline=none"
else
  dl_raw="$(tr -d '[:space:]' <"$DEADLINE" 2>/dev/null)"
  if printf '%s' "$dl_raw" | grep -qE '^[0-9]+$'; then
    now="$(date +%s)"
    if [ "$now" -ge "$dl_raw" ]; then
      fact "deadline=$dl_raw remaining=0s (elapsed)"
    else
      fact "deadline=$dl_raw remaining=$((dl_raw - now))s"
    fi
  else
    warn "deadline is not a UNIX epoch — watchmen compare integer seconds"
  fi
fi

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
if [ -f "$PUNCH" ] && [ "$OPEN" -eq 0 ]; then
  fact "punch list has no open items — leftover Shift contract and Gates still bind the next Hunt or Start cut"
  if [ "$ARMED" -eq 0 ]; then
    warn "empty punch list will inherit the current contract"
    act confirm "review punch-list.md contract and Gates before composing a new campaign; Archive files ticked items but never resets them"
  fi
fi
if [ "$ORDERS" -gt 0 ] && [ "$ARMED" -eq 0 ]; then
  act confirm "start to promote a parked Hunt order, or hunt to compose a new one"
fi
if [ "$DRAFTS" -gt 0 ] && [ "$ARMED" -eq 0 ]; then
  act confirm "promote agreed drafting-table items into punch-list.md, or start to be offered them"
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

json_tool_rule_state() { # $1 = rules file, $2 = exact tool name
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg tool "$2" '
      if (.toolDeny | type) != "object" then "invalid"
      elif (.toolDeny | has($tool) | not) then "missing"
      elif (.toolDeny[$tool] | type) != "string" then "invalid"
      elif .toolDeny[$tool] == "" then "allow"
      else "deny"
      end
    ' "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); rules=d.get("toolDeny"); tool=sys.argv[2]
print("invalid" if not isinstance(rules,dict) else "missing" if tool not in rules else "invalid" if not isinstance(rules[tool],str) else "allow" if rules[tool]=="" else "deny")' "$1" "$2" 2>/dev/null
  fi
}

RULES="$NS/rules.json"
if [ ! -f "$RULES" ]; then
  warn "rules.json is missing — watchman will refuse to arm"
  act confirm "re-run setup and accept the shipped rules template"
elif ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  warn "rules.json cannot be validated — neither jq nor python3 is available"
  act blocked "install jq or python3 before arming; toolDeny never falls back to text matching"
elif json_is_object "$RULES"; then
  fact "rules.json is a JSON object"
  wm="$(rule "$WORKSPACE" watchMinutes "")"
  case "$wm" in
    '' | *[!0-9]*) warn "watchMinutes missing or not a whole number"; act confirm "restore watchMinutes from the shipped template (10, or 0 to disarm)" ;;
    *) fact "watchMinutes $wm" ;;
  esac
  retry="$(rule "$WORKSPACE" watchRetrySeconds "${NIGHTSHIFT_WATCH_RETRY:-}")"
  resume="$(ns_expand_injected_paths "$WORKSPACE" "$(rule "$WORKSPACE" revivalPrompt "${NIGHTSHIFT_REVIVAL_PROMPT:-}")")"
  fresh="$(ns_expand_injected_paths "$WORKSPACE" "$(rule "$WORKSPACE" freshRevivalPrompt "${NIGHTSHIFT_FRESH_PROMPT:-}")")"
  if [ -z "$retry" ]; then
    warn "watchRetrySeconds is empty — watchman will refuse to arm"
    act confirm "restore watchRetrySeconds from the shipped template"
  fi
  if [ -z "$resume" ]; then
    warn "revivalPrompt is empty — watchman will refuse to arm"
    act confirm "restore revivalPrompt from the shipped template"
  fi
  if [ -z "$fresh" ]; then
    warn "freshRevivalPrompt is empty — watchman will refuse to arm"
    act confirm "restore freshRevivalPrompt from the shipped template"
  fi
  for tool in AskUserQuestion request_user_input; do
    tool_state="$(json_tool_rule_state "$RULES" "$tool")"
    case "$tool_state" in
      allow) fact "toolDeny.$tool explicitly allows the question tool" ;;
      deny) fact "toolDeny.$tool explicitly denies the question tool" ;;
      missing | invalid)
        warn "toolDeny.$tool is $tool_state — question behavior has no explicit policy"
        act confirm "re-run setup and review the shipped $tool entry (non-empty denies; empty allows)"
        ;;
    esac
  done
else
  warn "rules.json is unreadable or not a JSON object"
  act confirm "fix $NS/rules.json or re-run setup — never half-apply a broken file"
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

LEASE_STATE="absent"
LEASE_GENERATION=""
if [ -e "$NS/.shift-lease" ] || [ -L "$NS/.shift-lease" ]; then
  if ns_lease_valid "$NS"; then
    LEASE_STATE="valid"
    LEASE_HOST="$NS_LEASE_HOST"
    LEASE_GENERATION="$NS_LEASE_GENERATION"
    LEASE_NONCE="$NS_LEASE_NONCE"
    LEASE_PID="$NS_LEASE_PID"
    fact "process lease host $LEASE_HOST generation $LEASE_GENERATION"
    if [ -n "$LEASE_NONCE" ]; then
      fact "process lease belongs to a watchman recovery (capability not printed)"
    else
      fact "process lease belongs to the interactive shift process"
    fi
    if [ "$HOST_REC" != "none" ] && [ "$LEASE_HOST" != "$HOST_REC" ]; then
      warn "process lease host $LEASE_HOST disagrees with recorded session host $HOST_REC"
      act blocked "issue STOP from a separate session, then run Start again; do not rewrite the lease by hand"
    fi
    if [ -n "$LEASE_PID" ]; then
      if ns_recorded_process "$LEASE_PID" "$NS_LEASE_START"; then
        fact "lease holder pid $LEASE_PID is alive"
      else
        fact "lease holder pid $LEASE_PID is not confirmed alive"
      fi
    fi
  else
    LEASE_STATE="malformed"
    warn "process lease is malformed — ownership cannot be proven"
    act blocked "issue STOP from a separate session, then run Start again; never guess or edit .shift-lease"
  fi
elif [ "$ARMED" -eq 1 ] && [ -n "$SID" ]; then
  warn "armed shift has no process lease — the bound session's next tool call must bootstrap it"
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

act confirm "export a redacted local support bundle with $_here/export-support.sh — written under $NS/support/, never uploaded"
act blocked "Doctor never repairs, arms, stops, revives, or deletes"

emit "Nightshift Doctor"
emit "Host:        $HOST"
emit "Workspace:   $WORKSPACE"
emit "Link:        $LINK_STATE"
emit "Work target: $TARGET"
emit "Recorded:    ${HOST_REC:-none}"
emit "Lease:       $LEASE_STATE${LEASE_GENERATION:+ (generation $LEASE_GENERATION)}"
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
