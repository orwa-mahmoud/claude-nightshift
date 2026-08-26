#!/usr/bin/env bash
# apply-profile.sh — preview or copy a shipped local rules profile.
#
# One-time local copy. No network, no subscription, no overwrite in fill mode.
#   apply-profile.sh [--project DIR] --list
#   apply-profile.sh [--project DIR] --profile NAME --mode replace|fill [--apply]
#
# Default is preview. --apply writes only while unarmed.
# Exit: 0 previewed or applied · 1 usage · 2 refused
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROFILES="$_here/../skills/nightshift/references/profiles"
SCHEMA="$_here/../skills/nightshift/references/nightshift-rules.schema.json"
TEMPLATE="$_here/../skills/nightshift/references/nightshift-rules-template.json"
PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
MODE=""
PROFILE=""
APPLY=0
LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || exit 1; PROJECT="$2"; shift 2 ;;
    --profile) [ $# -ge 2 ] || exit 1; PROFILE="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || exit 1; MODE="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --list) LIST=1; shift ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'apply-profile: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'apply-profile: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}
WORKSPACE="$HOST"
if [ -e "$HOST/.nightshift-link" ] || [ -L "$HOST/.nightshift-link" ]; then
  WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)" || {
    printf 'apply-profile: invalid .nightshift-link\n' >&2
    exit 2
  }
fi
NS="$WORKSPACE/.nightshift"
RULES="$NS/rules.json"

if [ "$LIST" -eq 1 ]; then
  printf 'Nightshift rule profiles (local copies, not a subscription)\n'
  for f in "$PROFILES"/*.json; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      jq -r '"  \(.name)  risk=\(.risk)  v\(.version)  \(.use)"' "$f"
    else
      printf '  %s\n' "${f##*/}"
    fi
  done
  exit 0
fi

case "$MODE" in
  replace | fill) ;;
  *) printf 'apply-profile: --mode must be replace or fill\n' >&2; exit 1 ;;
esac
case "$PROFILE" in
  balanced | no-push | strict-secrets | isolated-branch) ;;
  *) printf 'apply-profile: unknown profile %s\n' "$PROFILE" >&2; exit 1 ;;
esac
SRC="$PROFILES/${PROFILE}.json"
[ -f "$SRC" ] || {
  printf 'apply-profile: missing profile file\n' >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'apply-profile: jq is required to preview and apply profiles\n' >&2
  exit 2
fi

if ! jq -e '.name and .version == 1 and .rules and (.rules | type == "object")' "$SRC" >/dev/null 2>&1; then
  printf 'apply-profile: profile is malformed or not version 1\n' >&2
  exit 2
fi

unknown="$(jq -r --slurpfile s "$SCHEMA" '
  .rules | keys[] as $k
  | select(($s[0].properties | has($k) | not) or $k == "$schema")
  | $k
' "$SRC")"
if [ -n "$unknown" ]; then
  printf 'apply-profile: profile has unsupported keys: %s\n' "$unknown" >&2
  exit 2
fi

[ -d "$NS" ] || {
  printf 'apply-profile: no .nightshift/ — run setup first\n' >&2
  exit 2
}

if [ -f "$NS/.shift-armed" ] && [ "$APPLY" -eq 1 ]; then
  printf 'apply-profile: refuse to write rules while the shift is armed\n' >&2
  exit 2
fi

current='{}'
if [ -f "$RULES" ] && jq -e 'type == "object"' "$RULES" >/dev/null 2>&1; then
  current="$(cat "$RULES")"
fi

proposed="$(PROFILE_MODE="$MODE" jq -n --argjson cur "$current" \
  --slurpfile p "$SRC" --slurpfile t "$TEMPLATE" '
  def fill:
    ($cur)
    + (
        $p[0].rules
        | to_entries
        | map(select(($cur[.key] | not)))
        | from_entries
      );
  def replace:
    $t[0]
    + $p[0].rules
    + (
        if ($cur["$schema"] | type) == "string" and ($cur["$schema"] | length) > 0
        then {"$schema": $cur["$schema"]}
        else {}
        end
      );
  if env.PROFILE_MODE == "fill" then fill else replace end
')"

if ! printf '%s' "$proposed" | jq -e '
  (.toolDeny | type) == "object"
  and (.toolDeny | has("AskUserQuestion"))
  and (.toolDeny | has("request_user_input"))
  and (.toolDeny.AskUserQuestion | type) == "string"
  and (.toolDeny.request_user_input | type) == "string"
' >/dev/null 2>&1; then
  printf 'apply-profile: proposed rules lack an explicit native question policy — re-run setup first\n' >&2
  exit 2
fi

printf 'Profile: %s\n' "$(jq -r '.name' "$SRC")"
printf 'Risk:    %s\n' "$(jq -r '.risk' "$SRC")"
printf 'Use:     %s\n' "$(jq -r '.use' "$SRC")"
printf 'Mode:    %s\n' "$MODE"
printf 'Rules the profile sets:\n'
jq -r '.rules | to_entries[] | "  \(.key)=\(.value|tojson)"' "$SRC"
printf '\nProposed rules.json\n'
printf '%s\n' "$proposed" | jq -S .

if [ "$APPLY" -eq 0 ]; then
  printf '\nDry run. Re-run with --apply after explicit confirmation.\n'
  exit 0
fi

tmp="$NS/.rules.json.$$"
printf '%s\n' "$proposed" | jq -S . >"$tmp" || {
  rm -f "$tmp"
  exit 2
}
mv "$tmp" "$RULES" || {
  rm -f "$tmp"
  exit 2
}
printf 'Wrote %s\n' "$RULES"
exit 0
