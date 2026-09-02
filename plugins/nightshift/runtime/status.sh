#!/usr/bin/env bash
# status.sh — read-only shift status for the native Status skill.
#
#   status.sh --project DIR
#
# Prints a compact glanceable summary: punch-list progress, evidence counts, resolved policy,
# preflight gaps, and liveness vs checkpoint vs stall as separate lines. Never writes.
#
# Exit: 0 report printed · 1 usage
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'status: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'status: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'status: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}

WORKSPACE="$HOST"
if [ -e "$HOST/.nightshift-link" ] || [ -L "$HOST/.nightshift-link" ]; then
  WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)" || WORKSPACE="$HOST"
fi
NS="$WORKSPACE/.nightshift"

emit() { printf '%s\n' "$1"; }

if [ ! -d "$NS" ]; then
  emit "Nightshift Status"
  emit "Nightshift: missing at $WORKSPACE"
  exit 0
fi

PUNCH="$NS/punch-list.md"
OPEN=0
TICKED=0
[ -f "$PUNCH" ] && OPEN="$(ns_open_boxes "$PUNCH")" && TICKED="$(ns_ticked_boxes "$PUNCH")"
ARMED=0
[ -f "$NS/.shift-armed" ] && ARMED=1
WATCH="$(rule "$WORKSPACE" watchMinutes "${NIGHTSHIFT_WATCH:-}")"
case "$WATCH" in '' | *[!0-9]*) WATCH=0 ;; esac

emit "Nightshift Status"
emit "Workspace:   $WORKSPACE"
emit "Shift:       $([ "$ARMED" -eq 1 ] && printf armed || printf 'not armed')"
emit "Items:       open=$OPEN ticked=$TICKED"
emit "evidence:    $(ns_evidence_counts "$WORKSPACE")"
emit "liveness:    $(ns_status_liveness "$NS" "$WATCH")"
activity="$(ns_status_last_activity "$NS")"
emit "last activity: ${activity:-none}"
emit "last checkpoint: $(ns_status_last_checkpoint "$WORKSPACE")"
emit "stall attempts: $(ns_status_stall_attempts "$NS")"
emit ""
emit "resolved policy"
if POLICY_LINES="$(ns_policy_resolve_table "$WORKSPACE" 2>/dev/null)"; then
  printf '%s\n' "$POLICY_LINES"
else
  emit "none"
fi
emit ""
emit "preflight gaps"
if ns_policy_json_tool >/dev/null 2>&1; then
  PREFLIGHT="$("$_here/preflight-needs.sh" --project "$WORKSPACE" 2>/dev/null)" || PREFLIGHT=""
  if [ -n "$PREFLIGHT" ]; then
    printf '%s\n' "$PREFLIGHT"
  else
    emit "none"
  fi
else
  emit "unavailable (jq or python3 required)"
fi
exit 0
