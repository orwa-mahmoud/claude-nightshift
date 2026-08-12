#!/usr/bin/env bash
# Explicitly connect this task root to an existing authoritative Nightshift workspace.
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

HOST="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
WORKSPACE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host-root) [ "$#" -ge 2 ] || exit 2; HOST="$2"; shift 2 ;;
    --workspace) [ "$#" -ge 2 ] || exit 2; WORKSPACE="$2"; shift 2 ;;
    *) printf 'link-workspace: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$WORKSPACE" ] || { printf 'link-workspace: --workspace is required\n' >&2; exit 2; }
ns_record_workspace_link "$HOST" "$WORKSPACE" || {
  printf 'link-workspace: target must be an absolute existing workspace containing .nightshift/\n' >&2
  exit 1
}
printf 'Nightshift task root: %s\nNightshift workspace: %s\n' \
  "$(cd -P "$HOST" && pwd)" "$(ns_workspace_root "$HOST")"
