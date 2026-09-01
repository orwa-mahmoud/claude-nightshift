#!/usr/bin/env bash
# provision-preflight.sh — read-only permission and revival check.
#
#   provision-preflight.sh --project DIR check
#
# Prints JSON {ok, skipReasons, recoverNeeded}. Never writes the punch list.
# Never installs. A permission-prompt risk is a skip, not a freeze.
# Exit: 0 report printed · 1 usage
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
CMD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'provision-preflight: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    check)
      CMD="check"
      shift
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'provision-preflight: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[ "$CMD" = check ] || {
  printf 'provision-preflight: usage: provision-preflight.sh --project DIR check\n' >&2
  exit 1
}

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'provision-preflight: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}

WORKSPACE="$HOST"
if [ -e "$HOST/.nightshift-link" ] || [ -L "$HOST/.nightshift-link" ]; then
  WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)" || {
    printf 'provision-preflight: invalid .nightshift-link\n' >&2
    exit 1
  }
fi

NS="$WORKSPACE/.nightshift"
RECOVER=0
if [ -f "$NS/provision-transaction.json" ] && [ ! -L "$NS/provision-transaction.json" ]; then
  RECOVER=1
fi

# Frictionless grant: Claude bypassPermissions / allowlist, or a Codex unattended sandbox.
grant=0
for f in "$HOST/.claude/settings.local.json" "$HOST/.claude/settings.json" \
         "$WORKSPACE/.claude/settings.local.json" "$WORKSPACE/.claude/settings.json"; do
  [ -f "$f" ] || continue
  if grep -q 'bypassPermissions\|"allow"' "$f" 2>/dev/null; then
    grant=1
    break
  fi
done

codex_grant="${CODEX_SANDBOX:-}${CODEX_SANDBOX_MODE:-}${NIGHTSHIFT_WATCH_AGENT:-}"
case "$codex_grant" in
  *danger-full-access*|*bypassPermissions*|*'-a never'*) grant=1 ;;
esac

# Attended: a human can click Allow. Revival is never attended.
attended=0
if [ "${NIGHTSHIFT_REVIVAL:-}" != 1 ] && [ -t 0 ]; then
  attended=1
fi

SKIP=""
if [ "$grant" -eq 0 ] && [ "$attended" -eq 0 ]; then
  SKIP="permission-prompt-required"
fi

OK=true
[ -z "$SKIP" ] || OK=false
RECOVER_JSON=false
[ "$RECOVER" -eq 0 ] || RECOVER_JSON=true

if [ -z "$SKIP" ]; then
  printf '{"ok":%s,"skipReasons":[],"recoverNeeded":%s}\n' "$OK" "$RECOVER_JSON"
else
  printf '{"ok":%s,"skipReasons":["%s"],"recoverNeeded":%s}\n' "$OK" "$SKIP" "$RECOVER_JSON"
fi
exit 0
