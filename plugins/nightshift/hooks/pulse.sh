#!/usr/bin/env bash
# pulse.sh — shared overwrite-only writer for .nightshift/.shift-pulse.
#
# Host wrappers parse stdin, then call ns_pulse_emit with the bound session id.
# One line: epoch<space>session-id. Identity check, not the lease: helpers never
# write; Cursor origin IDE stops writing once .shift-worker exists.
# Inert outside an active shift (same as session-end). Silent stdout.
#
# When executed (Claude PostToolUse), parse session_id from stdin and CLAUDE_PROJECT_DIR.

ns_pulse_owner_ok() { # <ns> <sid>
  local rec worker
  [ -n "${2:-}" ] || return 1
  worker="$(ns_cursor_worker_id "$1")"
  if [ -n "$worker" ]; then
    [ "$2" = "$worker" ]
    return
  fi
  rec="$(ns_session_line "$1" 1)"
  [ -n "$rec" ] && [ "$2" = "$rec" ]
}

ns_pulse_emit() { # <ns> <sid>
  local ns="$1" sid="$2" punch epoch
  [ -n "$ns" ] && [ -n "$sid" ] || return 0
  punch="$ns/punch-list.md"
  if [ ! -f "$ns/.shift-armed" ] || [ ! -f "$punch" ] \
    || { [ -f "$ns/.ended" ] && [ ! -L "$ns/.ended" ]; } \
    || [ "$(ns_open_boxes "$punch")" -eq 0 ]; then
    return 0
  fi
  ns_pulse_owner_ok "$ns" "$sid" || return 0
  epoch="$(date +%s)"
  [ -L "$ns/.shift-pulse" ] && rm -f "$ns/.shift-pulse"
  printf '%s %s\n' "$epoch" "$sid" >"$ns/.shift-pulse"
  return 0
}

# Executed as the Claude wrapper: parse stdin, emit, stay silent.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -u
  _here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
  # shellcheck source=plugins/nightshift/lib/lib.sh
  . "$_here/../lib/lib.sh"
  INPUT="$(cat)"
  HOST_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
  PROJECT_DIR="$(ns_workspace_root "$HOST_DIR" 2>/dev/null)" || exit 0
  STATE_KIND="$(ns_state_kind "$PROJECT_DIR")"
  case "$STATE_KIND" in
    malformed | future) exit 0 ;;
  esac
  NS="$PROJECT_DIR/.nightshift"
  if command -v jq >/dev/null 2>&1; then
    SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  else
    SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fi
  ns_pulse_emit "$NS" "$SID"
  exit 0
fi
