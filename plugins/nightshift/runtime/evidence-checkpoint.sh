#!/usr/bin/env bash
# evidence-checkpoint.sh — record the state a risky cluster starts from.
#
#   evidence-checkpoint.sh --project DIR --baseline ID --touched PATH... \
#     --rollback REF --plan TEXT
#
# Written before a risky cluster: the worktree it starts from, the baseline it relies on, the
# exact surface it may touch with a digest of every part that exists, the instruction that undoes
# it, and how it will be verified. Prints the new record id.
#
# Changes nothing and verifies nothing: a checkpoint states where the work began so a morning
# reviewer can put it back.
#
# Exit: 0 ok · 1 usage · 2 contract failure
#
# The record travels through evidence.sh append, so the ledger keeps every decision about
# defaults and validation. jq (preferred) or python3 covers exactly two jobs: confirming the
# named baseline is in the ledger and writing this record as one canonical JSON value.
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
  printf 'usage: evidence-checkpoint.sh --project DIR --baseline ID --touched PATH... --rollback REF --plan TEXT\n' >&2
  exit 1
}

die() {
  printf 'evidence-checkpoint: %s\n' "$1" >&2
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

_mktmp() {
  local base="${TMPDIR:-/tmp}" n=0 d
  case "$base" in
    */) base="${base%/}" ;;
  esac
  while [ "$n" -lt 64 ]; do
    d="$base/ns-checkpoint-$$-$n"
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
    die 'sha256sum, shasum or openssl is required to digest a checkpoint' 2
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

# _dir_digest DIR -> DIGEST: sha256 over the sorted `relative-path<TAB>sha256` lines of every
# regular file beneath DIR. Symlinks are not followed, so a digest never reaches outside.
_dir_digest() {
  local root="$1"
  find "$root" -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    [ -n "$f" ] || continue
    _sha256_file "$f"
    printf '%s%s%s\n' "${f#"$root"/}" "$TAB" "$DIGEST"
  done >"$TMPD/dirlist"
  _sha256_file "$TMPD/dirlist"
}

_utcnow() {
  if [ -n "${NIGHTSHIFT_EVIDENCE_NOW:-}" ]; then
    NOW="$NIGHTSHIFT_EVIDENCE_NOW"
    return 0
  fi
  NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
}

# ---------------------------------------------------------------- JSON bridge

JSON_TOOL=""

_pick_json_tool() {
  if command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq
  elif command -v python3 >/dev/null 2>&1; then
    JSON_TOOL=python3
  else
    die 'JSON parser unavailable; write the checkpoint receipt in the skill' 2
  fi
}

# shellcheck disable=SC2016 # jq program; $baseline must not expand in bash
JQ_HAS='
[ .[]
  | select(type == "object")
  | select(.domain == "baseline")
  | select(.id == $baseline)
]
| if length > 0 then "1" else "" end
'

# shellcheck disable=SC2016 # jq program; $paths/$digests must not expand in bash
JQ_RECORD='
def names($s): $s | split("\n") | map(select(length > 0));

names($paths) as $P
| names($digests) as $D
| { id: $id,
    domain: "checkpoint",
    sourceClass: "git",
    source: "git status --porcelain",
    scope: $target,
    severity: "info",
    confidence: "high",
    impact: "none",
    status: "open",
    ladder: $ladder,
    locator: $target,
    host: $host,
    workTarget: $target,
    rollback: $rollback,
    details: { worktreeDigest: $worktreeDigest,
               head: $head,
               baseline: $baseline,
               artifacts: [ range(0; $P | length) | { digest: $D[.], path: $P[.] } ],
               touched: names($touched),
               rollback: $rollback,
               plan: $plan } }
'

PY='
import json, sys

OP = sys.argv[1]


def names(s):
    return [x for x in s.split("\n") if x]


if OP == "has":
    baseline = sys.argv[2]
    found = ""
    for line in sys.stdin.read().split("\n"):
        if not line:
            continue
        rec = json.loads(line)
        if not isinstance(rec, dict):
            continue
        if rec.get("domain") == "baseline" and rec.get("id") == baseline:
            found = "1"
    sys.stdout.write(found + "\n")
else:
    (ID, BASELINE, LADDER, HOST, TARGET, WORKTREE, HEAD, ROLLBACK, PLAN, TOUCHED,
     PATHS, DIGESTS) = sys.argv[2:14]
    paths, digests = names(PATHS), names(DIGESTS)
    record = {
        "id": ID,
        "domain": "checkpoint",
        "sourceClass": "git",
        "source": "git status --porcelain",
        "scope": TARGET,
        "severity": "info",
        "confidence": "high",
        "impact": "none",
        "status": "open",
        "ladder": LADDER,
        "locator": TARGET,
        "host": HOST,
        "workTarget": TARGET,
        "rollback": ROLLBACK,
        "details": {
            "worktreeDigest": WORKTREE,
            "head": HEAD,
            "baseline": BASELINE,
            "artifacts": [
                {"digest": digests[i], "path": paths[i]} for i in range(len(paths))
            ],
            "touched": names(TOUCHED),
            "rollback": ROLLBACK,
            "plan": PLAN,
        },
    }
    sys.stdout.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
'

# _baseline_known — "1" on stdout when the ledger holds a baseline with this id.
_baseline_known() {
  if [ "$JSON_TOOL" = jq ]; then
    jq -sr --arg baseline "$BASELINE" "$JQ_HAS"
  else
    python3 -c "$PY" has "$BASELINE"
  fi
}

# _build_record — the finished record on stdout.
_build_record() {
  if [ "$JSON_TOOL" = jq ]; then
    jq -ncS --arg id "$ID" --arg baseline "$BASELINE" --arg ladder "$LADDER" \
      --arg host "$HOST" --arg target "$TARGET" --arg worktreeDigest "$WORKTREE_DIGEST" \
      --arg head "$HEAD_REF" --arg rollback "$ROLLBACK" --arg plan "$PLAN" \
      --arg touched "$TOUCHED_LINES" --arg paths "$ART_PATHS" \
      --arg digests "$ART_DIGESTS" "$JQ_RECORD"
  else
    python3 -c "$PY" record "$ID" "$BASELINE" "$LADDER" "$HOST" "$TARGET" \
      "$WORKTREE_DIGEST" "$HEAD_REF" "$ROLLBACK" "$PLAN" "$TOUCHED_LINES" \
      "$ART_PATHS" "$ART_DIGESTS"
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

# _worktree — WORKTREE_DIGEST (sha256 over the sorted `git status --porcelain` lines) and
# HEAD_REF. Both stay empty when the work target is not a repository Git can read, so an
# unmeasured worktree can never read as a clean one.
_worktree() {
  WORKTREE_DIGEST=""
  HEAD_REF=""
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || return 0
  if git -C "$TARGET" status --porcelain >"$TMPD/porcelain.raw" 2>/dev/null; then
    LC_ALL=C sort <"$TMPD/porcelain.raw" >"$TMPD/porcelain"
    _sha256_file "$TMPD/porcelain"
    WORKTREE_DIGEST="$DIGEST"
  fi
  HEAD_REF=$(git -C "$TARGET" rev-parse HEAD 2>/dev/null) || HEAD_REF=""
}

# _inventory — ART_PATHS and ART_DIGESTS, one line each per touched path that exists as a
# regular file or a directory. A symlink is never digested and never inventoried.
_inventory() {
  local rest="$TOUCHED_LINES" path abs
  ART_PATHS=""
  ART_DIGESTS=""
  while [ -n "$rest" ]; do
    path="${rest%%"$NL"*}"
    rest="${rest#*"$NL"}"
    [ -n "$path" ] || continue
    case "$path" in
      /*) abs="$path" ;;
      *) abs="$PROJECT/$path" ;;
    esac
    while [ "${#abs}" -gt 1 ] && [ "${abs%/}" != "$abs" ]; do abs="${abs%/}"; done
    if [ -L "$abs" ]; then continue; fi
    if [ -f "$abs" ]; then
      _sha256_file "$abs"
    elif [ -d "$abs" ]; then
      _dir_digest "$abs"
    else
      continue
    fi
    ART_PATHS="$ART_PATHS$path$NL"
    ART_DIGESTS="$ART_DIGESTS$DIGEST$NL"
  done
}

# ---------------------------------------------------------------- entry point

# _add_touched PATH — one validated path per line. The touched surface is a line-oriented list,
# so a path carrying a newline or a tab could not be read back out of the record it went into.
_add_touched() {
  [ -n "$1" ] || die 'a touched path must not be empty' 1
  case "$1" in
    *"$NL"* | *"$TAB"*) die 'a touched path must not contain a newline or a tab' 1 ;;
  esac
  TOUCHED_RAW="$TOUCHED_RAW$1$NL"
}

PROJECT_ARG=""
BASELINE=""
ROLLBACK=""
PLAN=""
HAVE_ROLLBACK=0
HAVE_PLAN=0
TOUCHED_RAW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || usage
      PROJECT_ARG="$2"
      shift 2
      ;;
    --baseline)
      [ $# -ge 2 ] || usage
      BASELINE="$2"
      shift 2
      ;;
    --rollback)
      [ $# -ge 2 ] || usage
      ROLLBACK="$2"
      HAVE_ROLLBACK=1
      shift 2
      ;;
    --plan)
      [ $# -ge 2 ] || usage
      PLAN="$2"
      HAVE_PLAN=1
      shift 2
      ;;
    --touched)
      shift
      [ $# -gt 0 ] || usage
      while [ $# -gt 0 ]; do
        case "$1" in
          --*) break ;;
        esac
        _add_touched "$1"
        shift
      done
      ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_ARG" ] || usage
[ -n "$BASELINE" ] || usage
[ -n "$TOUCHED_RAW" ] || usage
if [ "$HAVE_ROLLBACK" -ne 1 ] || [ -z "$ROLLBACK" ]; then usage; fi
if [ "$HAVE_PLAN" -ne 1 ] || [ -z "$PLAN" ]; then usage; fi

PROJECT=$(cd -P "$PROJECT_ARG" 2>/dev/null && pwd) ||
  die "not a directory: $PROJECT_ARG" 1
NS="$PROJECT/.nightshift"
[ -d "$NS" ] || die "no .nightshift/ at $PROJECT" 2
JSONL="$NS/evidence/findings.jsonl"

_pick_json_tool
_pick_sha
TMPD=""
trap _cleanup EXIT
_mktmp

printf '%s' "$TOUCHED_RAW" >"$TMPD/touched.raw"
LC_ALL=C sort -u <"$TMPD/touched.raw" >"$TMPD/touched"
TOUCHED_LINES=""
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  TOUCHED_LINES="$TOUCHED_LINES$_line$NL"
done <"$TMPD/touched"

LEDGER_IN=/dev/null
[ ! -f "$JSONL" ] || LEDGER_IN="$JSONL"
if ! _baseline_known <"$LEDGER_IN" >"$TMPD/known" 2>"$TMPD/jsonerr"; then
  die "cannot read the ledger at $JSONL" 2
fi
IFS= read -r KNOWN <"$TMPD/known" || KNOWN=""
[ "$KNOWN" = 1 ] || die "no baseline record with id $BASELINE" 2

_utcnow
{
  printf '%s\n%s\n%s\n%s\n' "$BASELINE" "$ROLLBACK" "$PLAN" "$NOW"
  cat "$TMPD/touched"
} >"$TMPD/idseed"
_sha256_file "$TMPD/idseed"
ID="checkpoint-${DIGEST:0:12}"

_host
_work_target
_worktree
_inventory
LADDER=declared
[ -z "$WORKTREE_DIGEST" ] || LADDER=observed

if ! _build_record >"$TMPD/record" 2>"$TMPD/jsonerr"; then
  die 'cannot build the checkpoint record' 2
fi
IFS= read -r RECORD <"$TMPD/record" || RECORD=""
[ -n "$RECORD" ] || die 'cannot build the checkpoint record' 2

"$EVIDENCE" --project "$PROJECT" append --record "$RECORD" || exit $?
exit 0
