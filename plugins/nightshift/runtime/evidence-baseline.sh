#!/usr/bin/env bash
# evidence-baseline.sh — record the starting state of one originating source.
#
#   evidence-baseline.sh --project DIR --source-class CLASS --command CMD [--scope TEXT] [--raw FILE]
#
# One baseline record per originating source per shift, written before the first fix: the exact
# command, the environment it ran in, a digest of what it printed, and the findings that source
# already has in the ledger. Prints the new record id.
#
# Runs no tool of its own beyond `--version` probes: the caller runs the source command and hands
# over its captured output with --raw. A baseline states what was measured, never that anything
# improved.
#
# Exit: 0 ok · 1 usage · 2 contract failure
#
# The record travels through evidence.sh append, so the ledger keeps every decision about
# defaults, validation, and raw storage. jq (preferred) or python3 covers exactly one
# job: reading the ledger's JSON lines and writing this record back as one canonical JSON value.
# Every other decision — the id, the version set, the digests, the ladder rung — happens here.
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
EVIDENCE="$_here/evidence.sh"

NL='
'
TAB=$(printf '\t')
CR=$(printf '\r')
VT=$(printf '\013')
FF=$(printf '\014')

usage() {
  printf 'usage: evidence-baseline.sh --project DIR --source-class CLASS --command CMD [--scope TEXT] [--raw FILE]\n' >&2
  exit 1
}

die() {
  printf 'evidence-baseline: %s\n' "$1" >&2
  exit "$2"
}

# ---------------------------------------------------------------- small helpers

# _strip_ws TEXT -> STRIPPED, mirroring str.strip() over ASCII whitespace.
_strip_ws() {
  local s="$1"
  while [ -n "$s" ]; do
    case "$s" in
      " "* | "$TAB"* | "$NL"* | "$CR"* | "$VT"* | "$FF"*) s="${s#?}" ;;
      *) break ;;
    esac
  done
  while [ -n "$s" ]; do
    case "$s" in
      *" " | *"$TAB" | *"$NL" | *"$CR" | *"$VT" | *"$FF") s="${s%?}" ;;
      *) break ;;
    esac
  done
  STRIPPED="$s"
}

# _first_line TEXT -> LINE1, the first line with surrounding whitespace gone and tabs flattened,
# so it can never break a tool<TAB>version line.
_first_line() {
  local s
  _strip_ws "$1"
  s="$STRIPPED"
  s="${s%%"$NL"*}"
  s="${s%%"$CR"*}"
  s="${s%%"$VT"*}"
  s="${s%%"$FF"*}"
  s="${s//$TAB/ }"
  if [ "${#s}" -gt 200 ]; then s="${s:0:200}"; fi
  LINE1="$s"
}

# _slug TEXT -> SLUG: runs of non-alphanumerics collapse to one dash, lowercase, trimmed, first
# 40 characters. The id carries it, and the ledger names the raw file after the id.
_slug() {
  local s
  s=$(printf '%s' "$1" | tr -cs 'A-Za-z0-9' '-' | tr '[:upper:]' '[:lower:]')
  s="${s#-}"
  s="${s%-}"
  if [ "${#s}" -gt 40 ]; then s="${s:0:40}"; fi
  s="${s%-}"
  [ -n "$s" ] || s=source
  SLUG="$s"
}

_mktmp() {
  local base="${TMPDIR:-/tmp}" n=0 d
  case "$base" in
    */) base="${base%/}" ;;
  esac
  while [ "$n" -lt 64 ]; do
    d="$base/ns-baseline-$$-$n"
    if mkdir "$d" 2>/dev/null; then
      TMPD="$d"
      return 0
    fi
    n=$((n + 1))
  done
  die 'cannot create a temporary directory' 2
}

# shellcheck disable=SC2329 # trap EXIT invokes this
_cleanup() { [ -z "${TMPD:-}" ] || rm -rf "$TMPD"; }

# ---------------------------------------------------------------- digests and time

SHA_TOOL=""

_pick_sha() {
  [ -z "$SHA_TOOL" ] || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    SHA_TOOL=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    SHA_TOOL=shasum
  elif command -v openssl >/dev/null 2>&1; then
    SHA_TOOL=openssl
  else
    die 'sha256sum, shasum or openssl is required to digest a baseline' 2
  fi
}

# _sha256_file FILE -> DIGEST, lowercase hex.
_sha256_file() {
  local line
  _pick_sha
  case "$SHA_TOOL" in
    sha256sum) line=$(sha256sum <"$1"); DIGEST="${line%% *}" ;;
    shasum) line=$(shasum -a 256 <"$1"); DIGEST="${line%% *}" ;;
    *) line=$(openssl dgst -sha256 <"$1"); DIGEST="${line##* }" ;;
  esac
}

_utcnow() {
  if [ -n "${NIGHTSHIFT_EVIDENCE_NOW:-}" ]; then
    NOW="$NIGHTSHIFT_EVIDENCE_NOW"
    return 0
  fi
  NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
}

# ---------------------------------------------------------------- the environment

# _lead_exe COMMAND -> LEADEXE: the first word that is not an environment assignment, so
# `CI=1 eslint .` probes eslint. Empty when the command has no such word.
_lead_exe() {
  local rest="$1" tok
  LEADEXE=""
  while [ -n "$rest" ]; do
    case "$rest" in
      " "* | "$TAB"*)
        rest="${rest#?}"
        continue
        ;;
    esac
    tok=""
    while [ -n "$rest" ]; do
      case "$rest" in
        " "* | "$TAB"*) break ;;
      esac
      tok="$tok${rest:0:1}"
      rest="${rest#?}"
    done
    case "$tok" in
      *=*) ;;
      *)
        LEADEXE="$tok"
        return 0
        ;;
    esac
  done
}

# _probe_version NAME -> VERSION. Runs `NAME --version` and nothing else. A name that is not on
# PATH reads as unavailable; a failing probe carries its exit status. Never blocks on stdin.
_probe_version() {
  local rc
  if ! command -v "$1" >/dev/null 2>&1; then
    VERSION=unavailable
    return 0
  fi
  "$1" --version >"$TMPD/vo" 2>"$TMPD/ve" </dev/null
  rc=$?
  _first_line "$(cat "$TMPD/vo" "$TMPD/ve" 2>/dev/null)"
  if [ "$rc" -ne 0 ]; then
    if [ -n "$LINE1" ]; then VERSION="exit $rc: $LINE1"; else VERSION="exit $rc"; fi
    return 0
  fi
  if [ -n "$LINE1" ]; then VERSION="$LINE1"; else VERSION="no version text"; fi
}

# _uname_fact FLAG -> UFACT, one flattened line, unknown when uname says nothing.
_uname_fact() {
  _first_line "$(uname "$1" 2>/dev/null)"
  if [ -n "$LINE1" ]; then UFACT="$LINE1"; else UFACT=unknown; fi
}

# _environment — VERSION_LINES (sorted tool<TAB>version lines, newline separated) and
# ENV_DIGEST (sha256 over those lines, each newline terminated). Three facts at most: the
# kernel, its release, and the `--version` of the command's own executable.
_environment() {
  local line os osrel
  _uname_fact -s
  os="$UFACT"
  _uname_fact -r
  osrel="$UFACT"
  VERSION=""
  [ -z "$LEADEXE" ] || _probe_version "$LEADEXE"
  {
    printf 'os%s%s\n' "$TAB" "$os"
    printf 'osRelease%s%s\n' "$TAB" "$osrel"
    [ -z "$LEADEXE" ] || printf '%s%s%s\n' "$LEADEXE" "$TAB" "$VERSION"
  } >"$TMPD/versions.raw"
  LC_ALL=C sort <"$TMPD/versions.raw" >"$TMPD/versions"
  _sha256_file "$TMPD/versions"
  ENV_DIGEST="$DIGEST"
  VERSION_LINES=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    VERSION_LINES="$VERSION_LINES$line$NL"
  done <"$TMPD/versions"
}

# ---------------------------------------------------------------- JSON bridge

JSON_TOOL=""

_pick_json_tool() {
  if command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq
  elif command -v python3 >/dev/null 2>&1; then
    JSON_TOOL=python3
  else
    die 'JSON parser unavailable; write the baseline receipt in the skill' 2
  fi
}

# shellcheck disable=SC2016 # jq program; $names must not expand in bash
JQ='
def names($s): $s | split("\n") | map(select(length > 0));

[ .[]
  | select(type == "object")
  | select(.sourceClass == $class)
  | select(.domain != "baseline" and .domain != "checkpoint")
  | select((.id | type) == "string")
]
| reduce .[] as $r ({};
    .[$r.id] = (if ($r.digest | type) == "string" then $r.digest else "" end))
| [ to_entries | sort_by(.key)[] | { digest: .value, id: .key } ] as $findings
| { id: $id,
    domain: "baseline",
    sourceClass: $class,
    source: $command,
    scope: $scope,
    severity: "info",
    confidence: "high",
    impact: "none",
    status: "open",
    ladder: $ladder,
    locator: $locator,
    host: $host,
    workTarget: $target,
    details: { sourceClass: $class,
               command: $command,
               scope: $scope,
               versions: names($versions),
               environmentDigest: $envDigest,
               rawDigest: $rawDigest,
               seen: $findings } }
'

PY='
import json, sys

(ID, CLASS, COMMAND, SCOPE, LADDER, LOCATOR, HOST, TARGET, VERSIONS, ENVDIGEST,
 RAWDIGEST) = sys.argv[1:12]


def names(s):
    return [x for x in s.split("\n") if x]


digests = {}
for line in sys.stdin.read().split("\n"):
    if not line:
        continue
    rec = json.loads(line)
    if not isinstance(rec, dict):
        continue
    if rec.get("sourceClass") != CLASS:
        continue
    if rec.get("domain") in ("baseline", "checkpoint"):
        continue
    ident = rec.get("id")
    if not isinstance(ident, str):
        continue
    digest = rec.get("digest")
    digests[ident] = digest if isinstance(digest, str) else ""

findings = [{"digest": digests[k], "id": k} for k in sorted(digests)]
record = {
    "id": ID,
    "domain": "baseline",
    "sourceClass": CLASS,
    "source": COMMAND,
    "scope": SCOPE,
    "severity": "info",
    "confidence": "high",
    "impact": "none",
    "status": "open",
    "ladder": LADDER,
    "locator": LOCATOR,
    "host": HOST,
    "workTarget": TARGET,
    "details": {
        "sourceClass": CLASS,
        "command": COMMAND,
        "scope": SCOPE,
        "versions": names(VERSIONS),
        "environmentDigest": ENVDIGEST,
        "rawDigest": RAWDIGEST,
        "seen": findings,
    },
}
sys.stdout.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
'

# _build_record — the finished record on stdout, the ledger's own lines on stdin.
_build_record() {
  if [ "$JSON_TOOL" = jq ]; then
    jq -scS --arg id "$ID" --arg class "$CLASS" --arg command "$COMMAND" \
      --arg scope "$SCOPE" --arg ladder "$LADDER" --arg locator "$LOCATOR" \
      --arg host "$HOST" --arg target "$TARGET" --arg versions "$VERSION_LINES" \
      --arg envDigest "$ENV_DIGEST" --arg rawDigest "$RAW_DIGEST" "$JQ"
  else
    python3 -c "$PY" "$ID" "$CLASS" "$COMMAND" "$SCOPE" "$LADDER" "$LOCATOR" \
      "$HOST" "$TARGET" "$VERSION_LINES" "$ENV_DIGEST" "$RAW_DIGEST"
  fi
}

# ---------------------------------------------------------------- shift facts

# _host — the host this shift is bound to, from the conversation record. An absent record is
# Claude's: nothing else could have written a shift without one.
_host() {
  local rec="$NS/.shift-session" line=""
  HOST=claude
  [ -f "$rec" ] && [ ! -L "$rec" ] || return 0
  line=$(sed -n 5p "$rec" 2>/dev/null)
  _strip_ws "$line"
  [ -z "$STRIPPED" ] || HOST="$STRIPPED"
}

# _work_target — the folder the work happens in, from .nightshift/work-target when Setup stored
# one (absolute, or relative to the workspace), otherwise the workspace itself.
_work_target() {
  local rec="$NS/work-target" text="" cand
  TARGET="$PROJECT"
  [ -f "$rec" ] && [ ! -L "$rec" ] || return 0
  IFS= read -r text <"$rec" || true
  _strip_ws "$text"
  [ -n "$STRIPPED" ] || return 0
  case "$STRIPPED" in
    /*) cand="$STRIPPED" ;;
    *) cand="$PROJECT/$STRIPPED" ;;
  esac
  if TARGET=$(cd -P "$cand" 2>/dev/null && pwd); then return 0; fi
  TARGET="$cand"
}

# ---------------------------------------------------------------- entry point

PROJECT_ARG=""
CLASS=""
COMMAND=""
SCOPE=""
RAW_FILE=""
HAVE_COMMAND=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || usage
      PROJECT_ARG="$2"
      shift 2
      ;;
    --source-class)
      [ $# -ge 2 ] || usage
      CLASS="$2"
      shift 2
      ;;
    --command)
      [ $# -ge 2 ] || usage
      COMMAND="$2"
      HAVE_COMMAND=1
      shift 2
      ;;
    --scope)
      [ $# -ge 2 ] || usage
      SCOPE="$2"
      shift 2
      ;;
    --raw)
      [ $# -ge 2 ] || usage
      RAW_FILE="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_ARG" ] || usage
[ -n "$CLASS" ] || usage
if [ "$HAVE_COMMAND" -ne 1 ] || [ -z "$COMMAND" ]; then usage; fi

PROJECT=$(cd -P "$PROJECT_ARG" 2>/dev/null && pwd) ||
  die "not a directory: $PROJECT_ARG" 1
NS="$PROJECT/.nightshift"
[ -d "$NS" ] || die "no .nightshift/ at $PROJECT" 2
JSONL="$NS/evidence/findings.jsonl"
if [ -n "$RAW_FILE" ] && [ ! -f "$RAW_FILE" ]; then
  die "no raw output at $RAW_FILE" 1
fi

_pick_json_tool
TMPD=""
trap _cleanup EXIT
_mktmp

_utcnow
_slug "$CLASS"
printf '%s\n%s\n%s\n%s\n' "$CLASS" "$COMMAND" "$SCOPE" "$NOW" >"$TMPD/idseed"
_sha256_file "$TMPD/idseed"
ID="baseline-$SLUG-${DIGEST:0:12}"

_lead_exe "$COMMAND"
_environment

# The raw output travels to the ledger as text, trailing newlines and all, so the digest here
# and the ledger's own rawDigest describe the same bytes.
RAW_DIGEST=""
RAW_TEXT=""
LADDER=observed
_host
_work_target
LOCATOR="$TARGET"
if [ -n "$RAW_FILE" ]; then
  _sha256_file "$RAW_FILE"
  RAW_DIGEST="$DIGEST"
  RAW_TEXT=$(cat "$RAW_FILE"; printf x)
  RAW_TEXT="${RAW_TEXT%x}"
  LADDER=measured
  LOCATOR="evidence/raw/$ID.txt"
fi

LEDGER_IN=/dev/null
[ ! -f "$JSONL" ] || LEDGER_IN="$JSONL"
if ! _build_record <"$LEDGER_IN" >"$TMPD/record" 2>"$TMPD/jsonerr"; then
  die "cannot read the ledger at $JSONL" 2
fi
IFS= read -r RECORD <"$TMPD/record" || RECORD=""
[ -n "$RECORD" ] || die 'cannot build the baseline record' 2

if [ -n "$RAW_FILE" ]; then
  "$EVIDENCE" --project "$PROJECT" append --record "$RECORD" --raw "$RAW_TEXT" || exit $?
else
  "$EVIDENCE" --project "$PROJECT" append --record "$RECORD" || exit $?
fi
exit 0
