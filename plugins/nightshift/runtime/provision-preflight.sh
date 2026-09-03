#!/usr/bin/env bash
# provision-preflight.sh — read-only permission and revival check.
#
#   provision-preflight.sh --project DIR [--recipe PATH] check
#
# Prints JSON {ok, skipReasons, recoverNeeded}. Never writes the punch list.
# Never installs. A permission-prompt risk is a skip, not a freeze.
# Exit: 0 report printed · 1 usage
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
RECIPE=""
CMD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'provision-preflight: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    --recipe)
      [ $# -ge 2 ] || { printf 'provision-preflight: --recipe needs a value\n' >&2; exit 1; }
      RECIPE="$2"
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
  printf 'provision-preflight: usage: provision-preflight.sh --project DIR [--recipe PATH] check\n' >&2
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

# Reasons accumulate as JSON, once each, in the order they are checked.
SKIP_JSON=""
add_skip() {
  case "$SKIP_JSON" in
    *"\"$1\""*) return 0 ;;
  esac
  SKIP_JSON="${SKIP_JSON}${SKIP_JSON:+,}\"$1\""
}

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

if [ "$grant" -eq 0 ] && [ "$attended" -eq 0 ]; then
  add_skip permission-prompt-required
fi

# One resolve answers both remaining questions: what tonight allows, and which tooling policy
# is in force. An unresolvable view claims neither.
TABLE="$(ns_policy_resolve_table "$WORKSPACE" 2>/dev/null)" || TABLE=""
TOOLING="$(printf '%s\n' "$TABLE" | sed -n 's/^toolingPolicy=\([^ ]*\).*$/\1/p')"
SUDO_POLICY="$(printf '%s\n' "$TABLE" | sed -n 's/^elevation\.sudo=\([^ ]*\).*$/\1/p')"

# Elevation the owner already lifted still has to run unattended. A recipe that may reach for
# sudo needs passwordless sudo proven now, or the capability is skipped rather than hung on a
# password prompt. The probe is deliberately coarse — JSON punctuation becomes whitespace so the
# owner's own pattern sees the command text — because over-reporting a skip is safe and
# under-reporting is not. The engine, not the preflight, decides what may run.
if [ -n "$RECIPE" ] && [ -f "$RECIPE" ]; then
  case "$SUDO_POLICY" in
    allow | exact-plan)
      SUDO_PATTERN="$(ns_policy_elevation_pattern "$WORKSPACE" sudo)" || SUDO_PATTERN=""
      if [ -n "$SUDO_PATTERN" ] && valid_ere "$SUDO_PATTERN"; then
        if tr '"[]{},:' '       ' <"$RECIPE" | grep -qE "$SUDO_PATTERN"; then
          sudo -n true >/dev/null 2>&1 || add_skip permission-prompt-required
        fi
      fi
      ;;
  esac
fi

# Auto-add no longer requires a Python runtime. The model installs; the seatbelt is bash.

OK=true
[ -z "$SKIP_JSON" ] || OK=false
RECOVER_JSON=false
[ "$RECOVER" -eq 0 ] || RECOVER_JSON=true

printf '{"ok":%s,"skipReasons":[%s],"recoverNeeded":%s}\n' "$OK" "$SKIP_JSON" "$RECOVER_JSON"
exit 0
