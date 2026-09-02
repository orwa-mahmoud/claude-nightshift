#!/usr/bin/env bash
# migrate-state.sh — write .nightshift/state-version for a legacy workspace, and retire the
# capability-policy.json a pre-shift-policy workspace still carries.
#
# Explicit owner repair only. Hooks, start, status, archive, and recovery must never
# invoke this. The migration preserves every existing file and unknown owner field;
# it writes the schema marker and, at most, the remembered tooling policy.
#
#   migrate-state.sh [--project DIR]
#
# Exit: 0 migrated or already current · 1 armed · 2 unsupported · 3 write failed · 4 usage
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'migrate-state: --project needs a value\n' >&2; exit 4; }
      PROJECT="$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 4
      ;;
    *) printf 'migrate-state: unknown argument: %s\n' "$1" >&2; exit 4 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'migrate-state: cannot cd to %s\n' "$PROJECT" >&2
  exit 4
}

WORKSPACE="$HOST"
if [ -e "$HOST/.nightshift-link" ] || [ -L "$HOST/.nightshift-link" ]; then
  WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)" || {
    printf 'migrate-state: invalid .nightshift-link — Nightshift will not guess a workspace\n' >&2
    exit 2
  }
fi

# The tooling policy moved into shift-defaults.json, where it prefills the one question a
# composition step asks. A workspace scaffolded before that still holds capability-policy.json;
# carry its choice across, then retire the file. An unreadable one is left where it is: nothing
# that cannot be read may be deleted, and Doctor reports the leftover.
LEGACY_POLICY="$WORKSPACE/.nightshift/capability-policy.json"

# An unparsable file yields no policy, whatever status the parser chose to exit with.
legacy_tooling_policy() {
  if [ "$1" = jq ]; then
    jq -r 'if type == "object" and (.policy | type) == "string" then .policy else "" end' \
      "$LEGACY_POLICY" 2>/dev/null || printf ''
  else
    python3 -c 'import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
p = d.get("policy") if isinstance(d, dict) else None
sys.stdout.write(p if isinstance(p, str) else "")' "$LEGACY_POLICY" 2>/dev/null || printf ''
  fi
}

retire_legacy_policy() {
  local policy tool
  [ -f "$LEGACY_POLICY" ] && [ ! -L "$LEGACY_POLICY" ] || return 0
  if [ -f "$WORKSPACE/.nightshift/.shift-armed" ]; then
    printf 'migrate-state: refuse to retire capability-policy.json while the shift is armed\n' >&2
    exit 1
  fi
  tool="$(ns_policy_json_tool)" || {
    printf 'migrate-state: jq or python3 is required to read JSON\n' >&2
    exit 2
  }
  policy="$(legacy_tooling_policy "$tool")"
  case "$policy" in
    existing-tools | review-missing | auto-add) ;;
    *)
      printf 'capability-policy.json is unreadable; left in place for the owner\n'
      return 0
      ;;
  esac
  if [ -f "$WORKSPACE/.nightshift/shift-defaults.json" ]; then
    rm -f "$LEGACY_POLICY" || {
      printf 'migrate-state: cannot remove capability-policy.json\n' >&2
      exit 3
    }
    printf 'capability-policy.json removed; shift-defaults.json already carries the remembered choices\n'
    return 0
  fi
  bash "$_here/shift-policy.sh" --project "$WORKSPACE" defaults-set --toolingPolicy "$policy" \
    >/dev/null || {
    printf 'migrate-state: cannot write shift-defaults.json\n' >&2
    exit 3
  }
  rm -f "$LEGACY_POLICY" || {
    printf 'migrate-state: cannot remove capability-policy.json\n' >&2
    exit 3
  }
  printf 'capability-policy.json migrated to shift-defaults.json (toolingPolicy %s) and removed\n' \
    "$policy"
}

retire_legacy_policy

KIND="$(ns_state_kind "$WORKSPACE")"
case "$KIND" in
  current)
    printf 'Nightshift state-version is already %s\n' "$NS_STATE_VERSION"
    exit 0
    ;;
  legacy)
    ;;
  future)
    printf '%s\n' "$(ns_state_refuse_message future)" >&2
    exit 2
    ;;
  malformed)
    printf '%s\n' "$(ns_state_refuse_message malformed)" >&2
    exit 2
    ;;
  *)
    printf 'migrate-state: no .nightshift/ at %s — run setup first\n' "$WORKSPACE" >&2
    exit 2
    ;;
esac

ns_migrate_state "$WORKSPACE"
rc=$?
case "$rc" in
  0)
    printf 'Nightshift state-version is now %s\n' "$NS_STATE_VERSION"
    exit 0
    ;;
  1)
    printf 'migrate-state: refuse to migrate while the shift is armed\n' >&2
    exit 1
    ;;
  3)
    printf 'migrate-state: failed to write state-version\n' >&2
    exit 3
    ;;
  *)
    printf '%s\n' "$(ns_state_refuse_message "$KIND")" >&2
    exit 2
    ;;
esac
