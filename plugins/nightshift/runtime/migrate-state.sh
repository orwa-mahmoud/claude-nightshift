#!/usr/bin/env bash
# migrate-state.sh — write .nightshift/state-version for a legacy workspace.
#
# Explicit owner repair only. Hooks, start, status, archive, and recovery must never
# invoke this. The migration preserves every existing file and unknown owner field;
# it writes only the schema marker.
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
