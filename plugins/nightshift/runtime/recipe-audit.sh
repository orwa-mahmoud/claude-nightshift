#!/usr/bin/env bash
# recipe-audit.sh — the capability recipe registry's own maintenance check.
#
#   recipe-audit.sh --project DIR index [--json]
#   recipe-audit.sh --project DIR audit [--json]
#
# index rewrites references/recipes/index.json from the registry on disk: one entry per recipe
# with ecosystem, capabilityId, recipeVersion, lastVerified, upstream and path, sorted by
# ecosystem then capabilityId, pretty-printed with sorted keys. It reads the registry and runs
# nothing.
#
# audit reports every recipe as one of inadmissible, missing-maintenance, missing-upstream, stale,
# unresolved or ok — the first state it matches, in that order. Specialist recipes — any whose
# enabledShifts entries carry a fallback — must ship a complete admission block; a recipe is
# stale when lastVerified is
# absent, unusable or more than 180 days before NIGHTSHIFT_EVIDENCE_NOW (today when unset), and
# unresolved when its maintenance.resolves query does not succeed. Only audit runs that query,
# so only audit reaches the network; it runs it as argv in a scratch directory, never through a
# shell, and never against the project.
#
# This is a maintainer tool: index writes inside the plugin's own registry. No hook, no Start and
# no shift ever calls it. The project is resolved so the command line matches the other runtime
# helpers; nothing is read from it and nothing is written to it.
#
# NIGHTSHIFT_RECIPE_REGISTRY overrides the registry root for a session.
# Exit: 0 every recipe is ok · 1 usage · 2 contract failure, naming the file · 3 a recipe is not ok
set -u

_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

TAB=$(printf '\t')
STALE_DAYS=180
STATES="inadmissible missing-maintenance missing-upstream stale unresolved ok"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" >&2
  exit 1
}

die() {
  printf 'recipe-audit: %s\n' "$1" >&2
  exit "$2"
}

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
CMD=""
FORMAT=text

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    --json)
      FORMAT=json
      shift
      ;;
    index | audit)
      [ -z "$CMD" ] || usage
      CMD="$1"
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf 'recipe-audit: unknown argument: %s\n' "$1" >&2
      usage
      ;;
  esac
done
[ -n "$CMD" ] || usage

cd -P "$PROJECT" >/dev/null 2>&1 || die "cannot cd to $PROJECT" 1

ns_policy_json_tool >/dev/null || die 'JSON parser unavailable; recipe audit is unused without a parser' 2

REGISTRY="$_here/../skills/nightshift/references/recipes"
[ -z "${NIGHTSHIFT_RECIPE_REGISTRY:-}" ] || REGISTRY="$NIGHTSHIFT_RECIPE_REGISTRY"
if [ -d "$REGISTRY" ]; then
  REGISTRY="$(cd -P "$REGISTRY" && pwd)" || die "cannot read the registry at $REGISTRY" 2
fi
REGISTRY_NAME="${REGISTRY%/}"
REGISTRY_NAME="${REGISTRY_NAME##*/}"
case "$REGISTRY_NAME" in
  '' | *[!A-Za-z0-9._-]*) die "the registry directory name is unusable: $REGISTRY" 2 ;;
esac
INDEX="$REGISTRY/index.json"

# The resolves query runs somewhere it can neither read nor dirty the project.
SCRATCH=""
cleanup() {
  [ -z "$SCRATCH" ] || rm -rf "$SCRATCH"
}
trap cleanup EXIT

# ---------------------------------------------------------------- today

# The audit's idea of now, as a date. NIGHTSHIFT_EVIDENCE_NOW may carry a full timestamp; only
# the date part decides staleness, so a fixture and a real run age a recipe the same way.
NOW=""
_now_date() {
  local fixed="${NIGHTSHIFT_EVIDENCE_NOW:-}"
  if [ -n "$fixed" ]; then
    NOW="${fixed%%T*}"
    _date_days "$NOW" || die "NIGHTSHIFT_EVIDENCE_NOW does not start with a date: $fixed" 2
    return 0
  fi
  NOW=$(date -u '+%Y-%m-%d')
}

# _date_days <YYYY-MM-DD> -> DAYS since 1970-01-01. Status 1 when the text is not a calendar
# date. Pure arithmetic: date(1) reads a stored date on neither host the same way.
DAYS=0
_date_days() {
  local t="$1" y m d yy era yoe doy doe mp
  case "$t" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  y="${t%%-*}"
  m="${t:5:2}"
  d="${t:8:2}"
  while :; do
    case "$y" in
      0?*) y="${y#0}" ;;
      *) break ;;
    esac
  done
  m="${m#0}"
  d="${d#0}"
  [ "$y" -ge 1 ] || return 1
  [ "$m" -ge 1 ] && [ "$m" -le 12 ] || return 1
  [ "$d" -ge 1 ] || return 1
  case "$m" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) [ "$d" -le 31 ] || return 1 ;;
    4 | 6 | 9 | 11) [ "$d" -le 30 ] || return 1 ;;
    2)
      if [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; }; then
        [ "$d" -le 29 ] || return 1
      else
        [ "$d" -le 28 ] || return 1
      fi
      ;;
  esac
  if [ "$m" -le 2 ]; then
    yy=$((y - 1))
    mp=$((m + 9))
  else
    yy="$y"
    mp=$((m - 3))
  fi
  era=$((yy / 400))
  yoe=$((yy - era * 400))
  doy=$(((153 * mp + 2) / 5 + d - 1))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  DAYS=$((era * 146097 + doe - 719468))
}

# _age_words <days> -> AGE_WORDS, the age as the report prints it.
AGE_WORDS=""
_age_words() {
  if [ "$1" -eq 1 ]; then
    AGE_WORDS='1 day old'
  else
    AGE_WORDS="$1 days old"
  fi
}

# ---------------------------------------------------------------- JSON reading

# One fact program reads a recipe. Every value travels as a JSON text, so no field can carry a
# tab or a newline and the stream stays line-safe. The two halves emit the same bytes.
FACTS_JQ='
def p: tojson;
if type != "object" then "k\tother"
else
  "k\tobject",
  ("i\t" + (.capabilityId | p)),
  ("v\t" + (.recipeVersion | p)),
  ("d\t" + (.lastVerified | p)),
  ("u\t" + (.upstream | p)),
  ("m\t" + (.maintenance | type)),
  ("c\t" + (if (.maintenance | type) == "object" then (.maintenance.check | p) else "null" end)),
  ("r\t" + (if (.maintenance | type) == "object" then (.maintenance.resolves | p) else "null" end)),
  ("y\t" + (.enabledShifts | type)),
  ("ys\t" + (if (.enabledShifts | type) == "array" then (([.enabledShifts[] | type] | any(. == "object")) | tostring) else "false" end)),
  ("a\t" + (.admission | type)),
  ("ac\t" + (if (.admission | type) == "object" then (.admission.contract | p) else "null" end)),
  ("af\t" + (if (.admission | type) == "object" then (.admission.fixture | p) else "null" end)),
  ("ad\t" + (if (.admission | type) == "object" then (.admission.demand | p) else "null" end))
end'

FACTS_PY='import json, sys


def jtype(v):
    if v is None:
        return "null"
    if v is True or v is False:
        return "boolean"
    if isinstance(v, str):
        return "string"
    if isinstance(v, dict):
        return "object"
    if isinstance(v, list):
        return "array"
    return "number"


def p(v):
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
out = []
if not isinstance(d, dict):
    out.append("k\tother")
else:
    out.append("k\tobject")
    for tag, key in (("i", "capabilityId"), ("v", "recipeVersion"),
                     ("d", "lastVerified"), ("u", "upstream")):
        out.append("%s\t%s" % (tag, p(d.get(key))))
    m = d.get("maintenance")
    out.append("m\t%s" % jtype(m))
    check, resolves = "null", "null"
    if isinstance(m, dict):
        check, resolves = p(m.get("check")), p(m.get("resolves"))
    out.append("c\t%s" % check)
    out.append("r\t%s" % resolves)
    shifts = d.get("enabledShifts")
    out.append("y\t%s" % jtype(shifts))
    specialist = "false"
    if isinstance(shifts, list):
        specialist = str(any(isinstance(item, dict) for item in shifts))
    out.append("ys\t%s" % specialist)
    adm = d.get("admission")
    out.append("a\t%s" % jtype(adm))
    ac, af, ad = "null", "null", "null"
    if isinstance(adm, dict):
        ac, af, ad = p(adm.get("contract")), p(adm.get("fixture")), p(adm.get("demand"))
    out.append("ac\t%s" % ac)
    out.append("af\t%s" % af)
    out.append("ad\t%s" % ad)
sys.stdout.write("".join(line + "\n" for line in out))
'

# The index document: rows of tab-separated columns in, one pretty array out. Ecosystem,
# capability and path are text this helper built and validated; the three recipe values travel
# as JSON texts so an absent field stays null and a wrong type stays visible.
INDEX_JQ='
split("\n") | map(select(length > 0)) | map(split("\t")) | map({
  ecosystem: .[0],
  capabilityId: .[1],
  recipeVersion: (.[2] | fromjson),
  lastVerified: (.[3] | fromjson),
  upstream: (.[4] | fromjson),
  path: .[5]
}) | sort_by(.ecosystem, .capabilityId)'

INDEX_PY='import json, sys
rows = [line for line in sys.stdin.read().split("\n") if line]
out = []
for row in rows:
    eco, cap, version, last, upstream, path = row.split("\t")
    out.append({"ecosystem": eco, "capabilityId": cap,
                "recipeVersion": json.loads(version), "lastVerified": json.loads(last),
                "upstream": json.loads(upstream), "path": path})
out.sort(key=lambda row: (row["ecosystem"], row["capabilityId"]))
sys.stdout.write(json.dumps(out, sort_keys=True, indent=2, ensure_ascii=False) + "\n")
'

# The audit document. The counts and the verdict are derived from the rows, so the summary can
# never disagree with the list it summarises.
AUDIT_JQ='
(split("\n") | map(select(length > 0)) | map(split("\t")) | map({
  ecosystem: .[0],
  capabilityId: .[1],
  path: .[2],
  state: .[3],
  detail: .[4]
})) as $rows |
{
  ok: ($rows | all(.state == "ok")),
  now: $now,
  staleDays: ($stale | tonumber),
  total: ($rows | length),
  counts: (reduce $rows[] as $row (
    {"inadmissible": 0, "missing-maintenance": 0, "missing-upstream": 0, "stale": 0, "unresolved": 0, "ok": 0};
    .[$row.state] += 1)),
  recipes: $rows
}'

AUDIT_PY='import json, sys
now, stale = sys.argv[1], int(sys.argv[2])
rows = []
counts = {"inadmissible": 0, "missing-maintenance": 0, "missing-upstream": 0, "stale": 0, "unresolved": 0, "ok": 0}
for line in sys.stdin.read().split("\n"):
    if not line:
        continue
    eco, cap, path, state, detail = line.split("\t")
    rows.append({"ecosystem": eco, "capabilityId": cap, "path": path,
                 "state": state, "detail": detail})
    counts[state] += 1
doc = {"ok": all(row["state"] == "ok" for row in rows), "now": now, "staleDays": stale,
       "total": len(rows), "counts": counts, "recipes": rows}
sys.stdout.write(json.dumps(doc, sort_keys=True, separators=(",", ":"),
                            ensure_ascii=False) + "\n")
'

# _facts <file> — the fact stream on stdout. Status 1 when the file is not JSON.
_facts() {
  local tool
  tool="$(ns_policy_json_tool)" || return 2
  if [ "$tool" = jq ]; then
    jq -r "$FACTS_JQ" "$1" 2>/dev/null || return 1
  else
    python3 -c "$FACTS_PY" "$1" 2>/dev/null || return 1
  fi
}

# _emit_index — rows on stdin, the pretty index document on stdout.
_emit_index() {
  local tool
  tool="$(ns_policy_json_tool)" || return 2
  if [ "$tool" = jq ]; then
    jq -S -R -s "$INDEX_JQ"
  else
    python3 -c "$INDEX_PY"
  fi
}

# _emit_audit — rows on stdin, one line of compact sorted JSON on stdout.
_emit_audit() {
  local tool
  tool="$(ns_policy_json_tool)" || return 2
  if [ "$tool" = jq ]; then
    jq -S -c -R -s --arg now "$NOW" --arg stale "$STALE_DAYS" "$AUDIT_JQ"
  else
    python3 -c "$AUDIT_PY" "$NOW" "$STALE_DAYS"
  fi
}

F_TYPE=""
F_CAP=null
F_VERSION=null
F_LAST=null
F_UPSTREAM=null
F_MAINT=null
F_CHECK=null
F_RESOLVES=null
F_SHIFTS=null
F_SPECIALIST=false
F_ADM=null
F_ADM_CONTRACT=null
F_ADM_FIXTURE=null
F_ADM_DEMAND=null

# _parse_facts <stream> — load one recipe's facts into the F_* view.
_parse_facts() {
  local tag value
  F_TYPE=""
  F_CAP=null
  F_VERSION=null
  F_LAST=null
  F_UPSTREAM=null
  F_MAINT=null
  F_CHECK=null
  F_RESOLVES=null
  F_SHIFTS=null
  F_SPECIALIST=false
  F_ADM=null
  F_ADM_CONTRACT=null
  F_ADM_FIXTURE=null
  F_ADM_DEMAND=null
  while IFS="$TAB" read -r tag value; do
    case "$tag" in
      k) F_TYPE="$value" ;;
      i) F_CAP="$value" ;;
      v) F_VERSION="$value" ;;
      d) F_LAST="$value" ;;
      u) F_UPSTREAM="$value" ;;
      m) F_MAINT="$value" ;;
      c) F_CHECK="$value" ;;
      r) F_RESOLVES="$value" ;;
      y) F_SHIFTS="$value" ;;
      ys) F_SPECIALIST="$value" ;;
      a) F_ADM="$value" ;;
      ac) F_ADM_CONTRACT="$value" ;;
      af) F_ADM_FIXTURE="$value" ;;
      ad) F_ADM_DEMAND="$value" ;;
    esac
  done <<<"$1"
}

# _plain <json-text> -> PLAIN. A value the report prints or executes must be a JSON string with
# nothing escaped in it; refusing everything else keeps the reader exact without a second parser.
PLAIN=""
_plain() {
  local s="$1"
  case "$s" in
    '"'*'"') ;;
    *) return 1 ;;
  esac
  s="${s#\"}"
  s="${s%\"}"
  case "$s" in
    *'\'* | *'"'*) return 1 ;;
  esac
  PLAIN="$s"
}

# _show <json-text> -> SHOWN, the value as a report line names it.
SHOWN=""
_show() {
  if _plain "$1"; then
    SHOWN="$PLAIN"
  else
    SHOWN="$1"
  fi
}

# ---------------------------------------------------------------- the resolves query

# _resolves_form_ok <text> — one plain command: argv words of the allowed characters, single
# spaces between them. Anything a shell would treat specially is refused rather than run.
_resolves_form_ok() {
  case "$1" in
    '' | *[!A-Za-z0-9._/@:=+,\ -]*) return 1 ;;
  esac
  case "$1" in
    ' '* | *' ' | *'  '*) return 1 ;;
  esac
}

# _run_resolves <text> — 0 the query succeeded · 1 the command is not on PATH · 2 it failed.
_run_resolves() {
  local -a argv=()
  IFS=' ' read -r -a argv <<<"$1"
  [ "${#argv[@]}" -gt 0 ] || return 1
  command -v "${argv[0]}" >/dev/null 2>&1 || return 1
  if [ -z "$SCRATCH" ]; then
    SCRATCH="$(mktemp -d)" || die 'cannot create a temporary directory' 2
  fi
  (cd "$SCRATCH" && "${argv[@]}") >/dev/null 2>&1 || return 2
}

# ---------------------------------------------------------------- the registry

# _recipes — every registered recipe as <ecosystem>/<capabilityId>, in byte order.
_recipes() {
  local dir file eco cap
  [ -d "$REGISTRY" ] || return 0
  for dir in "$REGISTRY"/*/; do
    [ -d "$dir" ] || continue
    eco="${dir%/}"
    eco="${eco##*/}"
    for file in "$dir"*.json; do
      [ -f "$file" ] || continue
      cap="${file##*/}"
      cap="${cap%.json}"
      printf '%s/%s\n' "$eco" "$cap"
    done
  done | LC_ALL=C sort
}

# _load <ecosystem> <capabilityId> — the recipe's facts, or a contract failure naming the file.
_load() {
  local rel="$REGISTRY_NAME/$1/$2.json" file="$REGISTRY/$1/$2.json" stream rc
  case "$1" in
    '' | *[!A-Za-z0-9-]*) die "$rel: an ecosystem directory is named outside [A-Za-z0-9-]" 2 ;;
  esac
  case "$2" in
    '' | *[!A-Za-z0-9-]*) die "$rel: a recipe is named outside [A-Za-z0-9-]" 2 ;;
  esac
  stream="$(_facts "$file")"
  rc=$?
  [ "$rc" -ne 2 ] || die 'JSON parser unavailable; recipe audit is unused without a parser' 2
  [ "$rc" -eq 0 ] || die "$rel: not JSON" 2
  _parse_facts "$stream"
  [ "$F_TYPE" = object ] || die "$rel: a recipe must be an object" 2
  _plain "$F_CAP" || die "$rel: capabilityId is missing or is not a plain string" 2
}

# _admission_field_ok <json-text> — a non-empty admission string.
_admission_field_ok() {
  _plain "$1" && [ -n "$PLAIN" ]
}

# ---------------------------------------------------------------- index

cmd_index() {
  local entry eco cap rows="" count=0 tmp
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    eco="${entry%%/*}"
    cap="${entry##*/}"
    _load "$eco" "$cap"
    _plain "$F_CAP" || die "$REGISTRY_NAME/$eco/$cap.json: capabilityId is missing or is not a plain string" 2
    rows="${rows}${eco}${TAB}${PLAIN}${TAB}${F_VERSION}${TAB}${F_LAST}${TAB}${F_UPSTREAM}${TAB}${REGISTRY_NAME}/${eco}/${cap}.json
"
    count=$((count + 1))
  done <<<"$(_recipes)"

  [ -d "$REGISTRY" ] || die "no registry at $REGISTRY" 2
  tmp="$INDEX.tmp.$$"
  printf '%s' "$rows" | _emit_index >"$tmp" || {
    rm -f "$tmp"
    die "cannot render $INDEX" 2
  }
  mv "$tmp" "$INDEX" || {
    rm -f "$tmp"
    die "cannot write $INDEX" 2
  }
  if [ "$FORMAT" = json ]; then
    printf '{"count":%s,"ok":true,"path":"%s"}\n' "$count" "$INDEX"
  else
    printf '%s\n' "$INDEX"
  fi
  exit 0
}

# ---------------------------------------------------------------- audit

# _state <ecosystem> <capabilityId> — the first state the loaded recipe matches, and the line
# that explains it.
STATE=""
DETAIL=""
_state() {
  local last days age need_adm
  STATE=""
  DETAIL=""
  need_adm=false
  [ "$F_SPECIALIST" = true ] && need_adm=true
  [ "$F_ADM" != null ] && need_adm=true
  if [ "$need_adm" = true ]; then
    if [ "$F_ADM" != object ]; then
      STATE=inadmissible
      DETAIL='no admission block'
      return 0
    fi
    if ! _admission_field_ok "$F_ADM_CONTRACT"; then
      STATE=inadmissible
      DETAIL='no admission.contract'
      return 0
    fi
    if ! _admission_field_ok "$F_ADM_FIXTURE"; then
      STATE=inadmissible
      DETAIL='no admission.fixture'
      return 0
    fi
    if ! _admission_field_ok "$F_ADM_DEMAND"; then
      STATE=inadmissible
      DETAIL='no admission.demand'
      return 0
    fi
  fi
  if [ "$F_MAINT" != object ]; then
    STATE=missing-maintenance
    DETAIL='no maintenance'
    return 0
  fi
  if ! _plain "$F_CHECK" || [ -z "$PLAIN" ]; then
    STATE=missing-maintenance
    DETAIL='no maintenance.check'
    return 0
  fi
  if ! _plain "$F_RESOLVES" || [ -z "$PLAIN" ]; then
    STATE=missing-maintenance
    DETAIL='no maintenance.resolves'
    return 0
  fi
  if ! _plain "$F_UPSTREAM"; then
    STATE=missing-upstream
    DETAIL='no upstream URL'
    return 0
  fi
  case "$PLAIN" in
    https://?* | http://?*) ;;
    *)
      STATE=missing-upstream
      DETAIL="upstream is not a URL: $PLAIN"
      return 0
      ;;
  esac
  if ! _plain "$F_LAST"; then
    STATE=stale
    DETAIL='no lastVerified'
    return 0
  fi
  last="$PLAIN"
  if ! _date_days "$last"; then
    STATE=stale
    DETAIL="lastVerified is not a date: $last"
    return 0
  fi
  days="$DAYS"
  _date_days "$NOW"
  age=$((DAYS - days))
  if [ "$age" -lt 0 ]; then
    STATE=stale
    DETAIL="lastVerified $last is ahead of $NOW"
    return 0
  fi
  if [ "$age" -gt "$STALE_DAYS" ]; then
    _age_words "$age"
    STATE=stale
    DETAIL="lastVerified $last is $AGE_WORDS (limit $STALE_DAYS)"
    return 0
  fi
  _plain "$F_RESOLVES"
  if ! _resolves_form_ok "$PLAIN"; then
    STATE=unresolved
    DETAIL="resolves is not a plain command: $PLAIN"
    return 0
  fi
  _run_resolves "$PLAIN"
  case $? in
    0) ;;
    1)
      STATE=unresolved
      DETAIL="resolves command not found: ${PLAIN%% *}"
      return 0
      ;;
    *)
      STATE=unresolved
      DETAIL="resolves failed: $PLAIN"
      return 0
      ;;
  esac
  _age_words "$age"
  STATE=ok
  DETAIL="lastVerified $last is $AGE_WORDS"
}

cmd_audit() {
  local entry eco cap rows="" total=0 failed=0 state line name
  _now_date
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    eco="${entry%%/*}"
    cap="${entry##*/}"
    _load "$eco" "$cap"
    _state "$eco" "$cap"
    [ "$STATE" = ok ] || failed=$((failed + 1))
    rows="${rows}${eco}${TAB}${cap}${TAB}${REGISTRY_NAME}/${eco}/${cap}.json${TAB}${STATE}${TAB}${DETAIL}
"
    total=$((total + 1))
  done <<<"$(_recipes)"

  if [ "$FORMAT" = json ]; then
    printf '%s' "$rows" | _emit_audit || die 'cannot render the audit' 2
  else
    while IFS="$TAB" read -r eco cap name state line; do
      [ -n "$eco" ] || continue
      printf '%s/%s\t%s\t%s\n' "$eco" "$cap" "$state" "$line"
    done <<<"$rows"
    printf 'total=%s' "$total"
    for state in $STATES; do
      printf ' %s=%s' "$state" "$(printf '%s' "$rows" | _count_state "$state")"
    done
    printf '\n'
  fi
  [ "$failed" -eq 0 ] || exit 3
  exit 0
}

# _count_state <state> — how many rows on stdin carry exactly that state.
_count_state() {
  local eco cap name state line n=0
  while IFS="$TAB" read -r eco cap name state line; do
    [ -n "$eco" ] || continue
    [ "$state" = "$1" ] || continue
    n=$((n + 1))
  done
  printf '%s' "$n"
}

case "$CMD" in
  index) cmd_index ;;
  audit) cmd_audit ;;
esac
