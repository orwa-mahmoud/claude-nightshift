#!/usr/bin/env bash
# export-support.sh — write one redacted local support bundle.
#
# Explicit owner action after Doctor. Never upload, transmit, attach, or open
# the file. Doctor itself stays read-only and must not invoke this.
#
#   export-support.sh [--project DIR]
#
# Exit: 0 wrote the bundle · 1 usage · 2 refused
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'export-support: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'export-support: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'export-support: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}

WORKSPACE="$HOST"
LINK_STATE="absent"
if [ -e "$HOST/.nightshift-link" ] || [ -L "$HOST/.nightshift-link" ]; then
  if WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)"; then
    LINK_STATE="valid"
  else
    printf 'export-support: invalid .nightshift-link — Nightshift will not guess a workspace\n' >&2
    exit 2
  fi
fi

NS="$WORKSPACE/.nightshift"
[ -d "$NS" ] || {
  printf 'export-support: no .nightshift/ at %s\n' "$WORKSPACE" >&2
  exit 2
}

HOME_ROOT="${HOME:-}"
[ -n "$HOME_ROOT" ] && HOME_ROOT="$(cd -P "$HOME_ROOT" 2>/dev/null && pwd)" || HOME_ROOT=""
TARGET="$(ns_work_target "$WORKSPACE" 2>/dev/null || true)"
[ -n "$TARGET" ] && TARGET="$(cd -P "$TARGET" 2>/dev/null && pwd)" || TARGET=""

PLUGIN_JSON="$_here/../.claude-plugin/plugin.json"
PLUGIN_VER="unknown"
PLUGIN_NAME="nightshift"
if [ -f "$PLUGIN_JSON" ]; then
  if command -v jq >/dev/null 2>&1; then
    PLUGIN_VER="$(jq -r '.version // "unknown"' "$PLUGIN_JSON" 2>/dev/null || printf 'unknown')"
    PLUGIN_NAME="$(jq -r '.name // "nightshift"' "$PLUGIN_JSON" 2>/dev/null || printf 'nightshift')"
  else
    PLUGIN_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | sed -n 1p)"
    PLUGIN_VER="${PLUGIN_VER:-unknown}"
    PLUGIN_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | sed -n 1p)"
    PLUGIN_NAME="${PLUGIN_NAME:-nightshift}"
  fi
fi

STATE_KIND="$(ns_state_kind "$WORKSPACE")"
STATE_VER="$(ns_state_version "$WORKSPACE" || true)"
case "$STATE_KIND" in
  current | legacy) ;;
  *) STATE_VER="" ;;
esac

RULES="$NS/rules.json"
RULES_STATE="missing"
RULES_KEYS=""
if [ ! -f "$RULES" ]; then
  RULES_STATE="missing"
elif command -v jq >/dev/null 2>&1 && jq -e 'type == "object"' "$RULES" >/dev/null 2>&1; then
  RULES_STATE="valid"
  RULES_KEYS="$(jq -r 'keys[]' "$RULES" 2>/dev/null | tr '\n' ' ')"
else
  RULES_STATE="unreadable"
fi

REASON="$(ns_reason_code "$NS")"
REASON_LABEL=""
[ -z "$REASON" ] || REASON_LABEL="$(ns_reason_label "$REASON")"

LEASE_STATE="absent"
LEASE_HOST=""
LEASE_GENERATION=""
LEASE_MODE=""
if [ -e "$NS/.shift-lease" ] || [ -L "$NS/.shift-lease" ]; then
  if ns_lease_valid "$NS"; then
    LEASE_STATE="valid"
    LEASE_HOST="$NS_LEASE_HOST"
    LEASE_GENERATION="$NS_LEASE_GENERATION"
    if [ -n "$NS_LEASE_NONCE" ]; then
      LEASE_MODE="recovered"
    else
      LEASE_MODE="interactive"
    fi
  else
    LEASE_STATE="malformed"
  fi
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
outdir="$NS/support"
mkdir -p "$outdir" || {
  printf 'export-support: cannot create %s\n' "$outdir" >&2
  exit 2
}
tmp="$outdir/.$stamp.$$"
dest="$outdir/${stamp}.txt"

{
  printf 'Nightshift support bundle\n'
  printf 'Generated: %s\n' "$stamp"
  printf '\n== plugin ==\n'
  printf 'name: %s\n' "$PLUGIN_NAME"
  printf 'version: %s\n' "$PLUGIN_VER"
  printf '\n== host ==\n'
  printf 'uname: %s\n' "$(uname -s)"
  printf 'link: %s\n' "$LINK_STATE"
  printf '\n== state ==\n'
  printf 'kind: %s\n' "$STATE_KIND"
  [ -z "$STATE_VER" ] || printf 'version: %s\n' "$STATE_VER"
  printf '\n== identities ==\n'
  if id_host="$(ns_tokenize_text "$HOST" "$HOME_ROOT" "$WORKSPACE" "$TARGET")"; then
    printf 'task: %s\n' "$id_host"
  else
    printf 'task: omitted\n'
  fi
  if id_ws="$(ns_tokenize_text "$WORKSPACE" "$HOME_ROOT" "$WORKSPACE" "$TARGET")"; then
    printf 'workspace: %s\n' "$id_ws"
  else
    printf 'workspace: omitted\n'
  fi
  if [ -n "$TARGET" ]; then
    if id_tg="$(ns_tokenize_text "$TARGET" "$HOME_ROOT" "$WORKSPACE" "$TARGET")"; then
      printf 'work_target: %s\n' "$id_tg"
    else
      printf 'work_target: omitted\n'
    fi
  else
    printf 'work_target: unresolved\n'
  fi
  printf '\n== markers ==\n'
  if [ -L "$NS/.shift-armed" ]; then
    printf 'armed: unusable\n'
  else
    printf 'armed: %s\n' "$( [ -f "$NS/.shift-armed" ] && printf yes || printf no )"
  fi
  if [ -L "$NS/.ended" ]; then
    printf 'ended: unusable\n'
  else
    printf 'ended: %s\n' "$( [ -f "$NS/.ended" ] && printf yes || printf no )"
  fi
  printf 'stop: %s\n' "$( [ -f "$NS/STOP" ] && printf yes || printf no )"
  if [ -L "$NS/.session-end" ]; then
    printf 'session_end: unusable\n'
  else
    printf 'session_end: %s\n' "$( [ -f "$NS/.session-end" ] && printf yes || printf no )"
  fi
  if [ -L "$NS/.shift-session" ]; then
    printf 'session_record: unusable\n'
  else
    printf 'session_record: %s\n' "$( [ -f "$NS/.shift-session" ] && printf present || printf absent )"
  fi
  printf 'process_lease: %s\n' "$LEASE_STATE"
  [ -z "$LEASE_HOST" ] || printf 'lease_host: %s\n' "$LEASE_HOST"
  [ -z "$LEASE_GENERATION" ] || printf 'lease_generation: %s\n' "$LEASE_GENERATION"
  [ -z "$LEASE_MODE" ] || printf 'lease_mode: %s\n' "$LEASE_MODE"
  if [ -L "$NS/.watchman" ]; then
    printf 'watchman_pidfile: unusable\n'
  else
    printf 'watchman_pidfile: %s\n' "$( [ -f "$NS/.watchman" ] && printf present || printf absent )"
  fi
  printf '\n== rules ==\n'
  printf 'validity: %s\n' "$RULES_STATE"
  printf 'keys: %s\n' "${RULES_KEYS:-}"
  printf '\n== watchman reason ==\n'
  if [ -n "$REASON" ]; then
    printf 'code: %s\n' "$REASON"
    printf 'label: %s\n' "$REASON_LABEL"
  else
    printf 'code: none\n'
  fi
  printf '\n== runtime log tail ==\n'
  if [ -f "$NS/scheduled.log" ] && [ ! -L "$NS/scheduled.log" ]; then
    tail_ok=0
    tail_skip=0
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$PROJECT" != "$WORKSPACE" ]; then
        line="$(printf '%s' "$line" | sed "s#$(ns_sed_escape "$PROJECT")#$(ns_sed_escape "$WORKSPACE")#g")"
      fi
      if sanitized="$(ns_sanitize_line "$line" "$HOME_ROOT" "$WORKSPACE" "$TARGET")"; then
        printf '%s\n' "$sanitized"
        tail_ok=$((tail_ok + 1))
      else
        tail_skip=$((tail_skip + 1))
      fi
    done <<EOF
$(tail -n 40 "$NS/scheduled.log" 2>/dev/null)
EOF
    if [ "$tail_ok" -eq 0 ] && [ "$tail_skip" -gt 0 ]; then
      printf 'omitted: every line failed sanitization\n'
    fi
  else
    printf 'absent\n'
  fi
} >"$tmp" || {
  rm -f "$tmp"
  printf 'export-support: failed to write bundle\n' >&2
  exit 2
}

chmod 600 "$tmp" || {
  rm -f "$tmp"
  printf 'export-support: failed to restrict bundle mode\n' >&2
  exit 2
}
mv "$tmp" "$dest" || {
  rm -f "$tmp"
  printf 'export-support: failed to publish bundle\n' >&2
  exit 2
}

printf 'Support bundle: %s\n' "$dest"
printf 'Included: plugin metadata, host, state version, tokenized identities, marker and lease state, rules validity and key names, reason codes, sanitized runtime-log tail\n'
printf 'Omitted: environment, secrets, rule values, repository contents, diffs, transcripts, prompts, owner files, credentials, network, session identities, lease capabilities\n'
printf 'Inspect the file before sharing. Never uploaded, attached, or opened automatically.\n'
exit 0
