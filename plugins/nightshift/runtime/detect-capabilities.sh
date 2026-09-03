#!/usr/bin/env bash
# detect-capabilities.sh — read-only applicability detector.
#
#   detect-capabilities.sh --project DIR [--host claude|codex|cursor] [--normalize]
#
# Prints JSON on stdout. Never writes inside the project. Exit 0 on success, 1 on usage,
# 2 when neither jq nor python3 is present to read JSON.
#
# The detection logic is bash. jq (preferred) or python3 covers exactly two jobs: reading
# the JSON inputs (the v1 schemas and each package.json) and serialising the finished
# document. Every decision — traversal, ordering, probing, ranking, contract evaluation —
# happens here. Sorting is byte order throughout.
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
SCHEMA="$_here/../skills/nightshift/references/schemas/v1"
EMIT_JQ="$_here/detect-capabilities-emit.jq"

NL='
'
TAB=$(printf '\t')
CR=$(printf '\r')
VT=$(printf '\013')
FF=$(printf '\014')
FS=$(printf '\037')
RS=$(printf '\036')

usage() {
  printf 'usage: detect-capabilities.sh --project DIR [--host claude|codex|cursor] [--normalize]\n' >&2
  exit 1
}

# ---------------------------------------------------------------- small helpers

# _join DIR NAME -> JOINED, mirroring os.path.join for the two-argument case.
_join() {
  case "$1" in
    */) JOINED="$1$2" ;;
    *) JOINED="$1/$2" ;;
  esac
}

# _strip_ws TEXT -> STRIPPED, mirroring str.strip() over ASCII whitespace.
_strip_ws() {
  local s="$1"
  while [ -n "$s" ]; do
    case "$s" in
      " "*|"$TAB"*|"$NL"*|"$CR"*|"$VT"*|"$FF"*) s="${s#?}" ;;
      *) break ;;
    esac
  done
  while [ -n "$s" ]; do
    case "$s" in
      *" "|*"$TAB"|*"$NL"|*"$CR"|*"$VT"|*"$FF") s="${s%?}" ;;
      *) break ;;
    esac
  done
  STRIPPED="$s"
}

# _normpath PATH -> NORMPATH, mirroring posixpath.normpath.
_normpath() {
  local path="$1" initial rest comp stack tail joined
  if [ -z "$path" ]; then
    NORMPATH="."
    return 0
  fi
  case "$path" in
    ///*) initial=1 ;;
    //*) initial=2 ;;
    /*) initial=1 ;;
    *) initial=0 ;;
  esac
  stack="$NL"
  rest="$path/"
  while [ -n "$rest" ]; do
    comp="${rest%%/*}"
    rest="${rest#*/}"
    [ -n "$comp" ] || continue
    [ "$comp" = "." ] && continue
    if [ "$comp" != ".." ]; then
      stack="$stack$comp$NL"
      continue
    fi
    if [ "$stack" = "$NL" ]; then
      [ "$initial" -eq 0 ] && stack="$stack..$NL"
      continue
    fi
    tail="${stack%"$NL"}"
    if [ "${tail##*"$NL"}" = ".." ]; then
      stack="$stack..$NL"
    else
      stack="${tail%"$NL"*}$NL"
    fi
  done
  joined=""
  tail="${stack#"$NL"}"
  while [ -n "$tail" ]; do
    comp="${tail%%"$NL"*}"
    tail="${tail#*"$NL"}"
    if [ -z "$joined" ]; then joined="$comp"; else joined="$joined/$comp"; fi
  done
  case "$initial" in
    1) joined="/$joined" ;;
    2) joined="//$joined" ;;
  esac
  [ -n "$joined" ] || joined="."
  NORMPATH="$joined"
}

# _abspath PATH -> ABSPATH, mirroring os.path.abspath.
_abspath() {
  local p="$1" cwd
  case "$p" in
    /*) ;;
    *)
      cwd=$(pwd -P)
      case "$cwd" in
        */) p="$cwd$p" ;;
        *) p="$cwd/$p" ;;
      esac
      ;;
  esac
  _normpath "$p"
  ABSPATH="$NORMPATH"
}

# _sortlines_u TEXT -> SORTED: byte order, deduplicated, newline-terminated.
_sortlines_u() {
  if [ -z "$1" ]; then
    SORTED=""
    return 0
  fi
  SORTED=$(printf '%s' "$1" | LC_ALL=C sort -u)
  [ -z "$SORTED" ] || SORTED="$SORTED$NL"
}

# _has_line LIST ENTRY — exact membership in a newline-terminated list.
_has_line() {
  case "$NL$1" in
    *"$NL$2$NL"*) return 0 ;;
  esac
  return 1
}

_mktmp() {
  local base="${TMPDIR:-/tmp}" n=0 d
  case "$base" in
    */) base="${base%/}" ;;
  esac
  while [ "$n" -lt 64 ]; do
    d="$base/ns-detect-$$-$n"
    if mkdir "$d" 2>/dev/null; then
      TMPD="$d"
      return 0
    fi
    n=$((n + 1))
  done
  printf 'detect-capabilities: cannot create a temporary directory\n' >&2
  exit 1
}

_cleanup() { [ -z "${TMPD:-}" ] || rm -rf "$TMPD"; }

# ---------------------------------------------------------------- JSON bridge

JSON_TOOL=""

_pick_json_tool() {
  if command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq
  elif command -v python3 >/dev/null 2>&1; then
    JSON_TOOL=python3
  else
    printf 'detect-capabilities: unused; inspect the repo in the skill\n' >&2
    exit 2
  fi
}

# One tab-separated line per fact: H host, C capability id, P provisioning default (as
# JSON), then per contract K id, A id artifact, Fs/Fn id fallback, R id "cap cap",
# Y id "cap cap". Capability ids never contain a space, so one line carries the whole list.
JQ_CONTRACTS='
  .contracts | to_entries | sort_by(.key)[] |
    ("K\t" + .key),
    ("A\t" + .key + "\t" + (.value.artifact | tojson)),
    (if (.value.fallback | type) == "string"
       then "Fs\t" + .key + "\t" + .value.fallback
       else "Fn\t" + .key end),
    ("R\t" + .key + "\t" + ((.value.requires // []) | join(" "))),
    ("Y\t" + .key + "\t" + ((.value.requiresAny // []) | join(" ")))
'

PY_META='
import json, sys
base = sys.argv[1]


def load(name):
    with open(base + "/" + name) as fh:
        return json.load(fh)


ident = load("identifiers.json")
registry = load("capabilities.json")
reqs = load("catalog-requirements.json")
out = []
for host in ident["hosts"]:
    out.append("H\t" + host)
for cap in registry["capabilities"]:
    out.append("C\t" + cap)
out.append("P\t" + json.dumps(registry["provisioningDefault"]))
contracts = reqs["contracts"]
for cid in sorted(contracts):
    req = contracts[cid]
    out.append("K\t" + cid)
    out.append("A\t" + cid + "\t" + json.dumps(req.get("artifact")))
    fallback = req.get("fallback")
    if isinstance(fallback, str):
        out.append("Fs\t" + cid + "\t" + fallback)
    else:
        out.append("Fn\t" + cid)
    out.append("R\t" + cid + "\t" + " ".join(req.get("requires") or []))
    out.append("Y\t" + cid + "\t" + " ".join(req.get("requiresAny") or []))
sys.stdout.write("".join(line + "\n" for line in out))
'

JQ_SCRIPTS='
  if type == "object" then .scripts else null end
  | if type == "object" then (keys | .[]) else empty end
'

PY_SCRIPTS='
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
scripts = data.get("scripts") or {}
if not isinstance(scripts, dict):
    sys.exit(0)
sys.stdout.write("".join(name + "\n" for name in sorted(scripts)))
'

PY_EMIT='
import json, sys
fs, rs = sys.argv[1], sys.argv[2]
doc = {}
for rec in sys.stdin.buffer.read().decode("utf-8", "replace").split(rs):
    if not rec:
        continue
    fields = rec.split(fs)
    depth = int(fields[1])
    path = fields[2:2 + depth]
    value = fields[2 + depth]
    kind = fields[0]
    node = doc
    for comp in path[:-1]:
        node = node.setdefault(comp, {})
    key = path[-1]
    if kind == "s":
        node[key] = value
    elif kind == "n":
        node[key] = int(value)
    elif kind == "b":
        node[key] = value == "1"
    elif kind == "z":
        node[key] = None
    elif kind == "j":
        node[key] = json.loads(value)
    elif kind == "A":
        node.setdefault(key, [])
    elif kind == "a":
        node.setdefault(key, []).append(value)
json.dump(doc, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
'

_load_meta() {
  if [ "$JSON_TOOL" = jq ]; then
    jq -r '.hosts[] | "H\t" + .' "$SCHEMA/identifiers.json" &&
      jq -r '.capabilities[] | "C\t" + .' "$SCHEMA/capabilities.json" &&
      jq -r '"P\t" + (.provisioningDefault | tojson)' "$SCHEMA/capabilities.json" &&
      jq -r "$JQ_CONTRACTS" "$SCHEMA/catalog-requirements.json"
  else
    python3 -c "$PY_META" "$SCHEMA"
  fi
}

# _script_names PACKAGE_JSON — sorted package.json script keys on stdout, one per line.
_script_names() {
  [ -f "$1" ] || return 0
  if [ "$JSON_TOOL" = jq ]; then
    jq -r "$JQ_SCRIPTS" "$1" 2>/dev/null
  else
    python3 -c "$PY_SCRIPTS" "$1" 2>/dev/null
  fi
}

_serialize() {
  if [ "$JSON_TOOL" = jq ]; then
    jq -Rs -S --indent 2 -a --arg FS "$FS" --arg RS "$RS" -f "$EMIT_JQ" "$1"
  else
    python3 -c "$PY_EMIT" "$FS" "$RS" <"$1"
  fi
}

# ---------------------------------------------------------------- record emitter

# emit TYPE COMPONENT... VALUE
emit() {
  local out="$1" n
  shift
  n=$(($# - 1))
  out="$out$FS$n"
  while [ $# -gt 0 ]; do
    out="$out$FS$1"
    shift
  done
  printf '%s%s' "$out" "$RS" >&3
}

# ---------------------------------------------------------------- PATH probing

# _which CMD -> WHICH_PATH. Searches ENV_PATH in order; a candidate must be a regular
# file and executable. An empty command, or one starting with "-", is never found.
_which() {
  local rest dir cand
  WHICH_PATH=""
  case "$1" in
    ""|-*) return 1 ;;
  esac
  rest="$ENV_PATH:"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    [ -n "$dir" ] || continue
    case "$dir" in
      */) cand="$dir$1" ;;
      *) cand="$dir/$1" ;;
    esac
    if [ -f "$cand" ] && [ -x "$cand" ]; then
      WHICH_PATH="$cand"
      return 0
    fi
  done
  return 1
}

# _first_line TEXT -> LINE1, mirroring text.strip().splitlines()[0].
_first_line() {
  local s
  _strip_ws "$1"
  s="$STRIPPED"
  s="${s%%"$NL"*}"
  s="${s%%"$CR"*}"
  s="${s%%"$VT"*}"
  s="${s%%"$FF"*}"
  LINE1="$s"
}

# _trunc TEXT -> TRUNC, mirroring text[:200].
_trunc() {
  local s="$1"
  if [ "${#s}" -gt 200 ]; then
    s="${s:0:200}"
  fi
  TRUNC="$s"
}

# _version_probe PATH -> VP_STATUS, VP_DETAIL. Runs `<path> --version`, never real work.
_version_probe() {
  local rc text
  "$1" --version >"$TMPD/vo" 2>"$TMPD/ve" 3>&-
  rc=$?
  text=$(cat "$TMPD/vo" "$TMPD/ve" 2>/dev/null)
  _first_line "$text"
  _trunc "$LINE1"
  if [ "$rc" -eq 0 ]; then
    VP_STATUS="available-and-verified"
    VP_DETAIL="$TRUNC"
  else
    VP_STATUS="available-but-failing"
    VP_DETAIL="exit $rc: $TRUNC"
  fi
}

# _probe_command CMD MISSING_LOCATOR -> PC_STATUS, PC_REASON, PC_LOCATOR, PC_LADDER
_probe_command() {
  local detail
  if ! _which "$1"; then
    PC_STATUS="unavailable"
    PC_REASON="command $1 is not on PATH"
    PC_LOCATOR="$2"
    PC_LADDER="observed"
    return 0
  fi
  _version_probe "$WHICH_PATH"
  detail="$VP_DETAIL"
  [ -n "$detail" ] || detail="no version text"
  PC_STATUS="$VP_STATUS"
  PC_REASON="$1 -> $WHICH_PATH ($detail)"
  PC_LOCATOR="$WHICH_PATH"
  if [ "$VP_STATUS" = "available-and-verified" ]; then
    PC_LADDER="measured"
  else
    PC_LADDER="observed"
  fi
}

# ---------------------------------------------------------------- capability store

# Statuses accumulate as NL <id> TAB <status> NL, so a contract can look one up without
# an associative array.
CAP_STATUSES="$NL"

# _set_cap ID STATUS REASON LOCATOR LADDER
_set_cap() {
  CAP_STATUSES="$CAP_STATUSES$1$TAB$2$NL"
  emit s capabilities "$1" status "$2"
  emit s capabilities "$1" reason "$3"
  emit s capabilities "$1" locator "$4"
  emit s capabilities "$1" evidenceLadder "$5"
}

# _cap_status ID -> CAPSTATUS; an id that was never detected reads as unavailable.
_cap_status() {
  local rest="${CAP_STATUSES#*"$NL$1$TAB"}"
  if [ "$rest" = "$CAP_STATUSES" ]; then
    CAPSTATUS="unavailable"
  else
    CAPSTATUS="${rest%%"$NL"*}"
  fi
}

# ---------------------------------------------------------------- merge_status

_rank() {
  case "$1" in
    available-and-verified) RANK=5 ;;
    available-but-failing) RANK=4 ;;
    fallback-only) RANK=3 ;;
    provisionable) RANK=2 ;;
    unavailable) RANK=1 ;;
    *) RANK=0 ;;
  esac
}

_merge_reset() {
  MG_RANK=0
  MG_STATUS=""
  MG_REASON=""
  MG_LOCATOR=""
  MG_LADDER=""
}

# _merge_offer STATUS REASON LOCATOR LADDER — best status wins, first one on a tie.
_merge_offer() {
  _rank "$1"
  if [ "$RANK" -gt "$MG_RANK" ]; then
    MG_RANK="$RANK"
    MG_STATUS="$1"
    MG_REASON="$2"
    MG_LOCATOR="$3"
    MG_LADDER="$4"
  fi
}

# _merge_commit ID
_merge_commit() {
  if [ "$MG_RANK" -eq 0 ]; then
    _set_cap "$1" "unavailable" "not probed" "" "declared"
  else
    _set_cap "$1" "$MG_STATUS" "$MG_REASON" "$MG_LOCATOR" "$MG_LADDER"
  fi
}

# ---------------------------------------------------------------- traversal

# _list_dir DIR -> DIR_ENTRIES: every child path, byte-sorted, newline-terminated. The
# trailing slash makes a symlinked directory resolve, as scandir does; the entries
# themselves are never followed.
_list_dir() {
  local d
  case "$1" in
    -*) d="./$1/" ;;
    *) d="$1/" ;;
  esac
  DIR_ENTRIES=$(find "$d" -mindepth 1 -maxdepth 1 -print 2>/dev/null | LC_ALL=C sort)
  [ -z "$DIR_ENTRIES" ] || DIR_ENTRIES="$DIR_ENTRIES$NL"
}

# Markdown/HTML census. Mirrors the detector walk: a directory's files in sorted order,
# then its non-symlink subdirectories in sorted order, pruning .git and node_modules, and
# stopping once more than 40 documents have been seen.
_walk_docs() {
  local dir="$1" entries entry name path subdirs=""
  _list_dir "$dir"
  entries="$DIR_ENTRIES"
  while [ -n "$entries" ]; do
    entry="${entries%%"$NL"*}"
    entries="${entries#*"$NL"}"
    name="${entry##*/}"
    case "$dir" in
      */) path="$dir$name" ;;
      *) path="$dir/$name" ;;
    esac
    if [ -d "$path" ]; then
      case "$name" in
        .git|node_modules) ;;
        *) subdirs="$subdirs$name$NL" ;;
      esac
      continue
    fi
    case "$name" in
      *.[Mm][Dd]|*.[Mm][Aa][Rr][Kk][Dd][Oo][Ww][Nn])
        DOC_MD_N=$((DOC_MD_N + 1))
        [ -n "$DOC_MD_FIRST" ] || DOC_MD_FIRST="$path"
        ;;
      *.[Hh][Tt][Mm][Ll]|*.[Hh][Tt][Mm])
        DOC_HTML_N=$((DOC_HTML_N + 1))
        [ -n "$DOC_HTML_FIRST" ] || DOC_HTML_FIRST="$path"
        ;;
    esac
  done
  if [ $((DOC_MD_N + DOC_HTML_N)) -gt 40 ]; then
    DOC_STOP=1
    return 0
  fi
  while [ -n "$subdirs" ]; do
    name="${subdirs%%"$NL"*}"
    subdirs="${subdirs#*"$NL"}"
    case "$dir" in
      */) path="$dir$name" ;;
      *) path="$dir/$name" ;;
    esac
    [ -L "$path" ] && continue
    _walk_docs "$path"
    [ "$DOC_STOP" -eq 0 ] || return 0
  done
  return 0
}

# First file named FND_NAME in scan order, pruning .git node_modules vendor target. The
# reference collects up to 20 hits and reports the first, so landing one ends the search.
_walk_find() {
  local dir="$1" entries entry name path subdirs=""
  _list_dir "$dir"
  entries="$DIR_ENTRIES"
  while [ -n "$entries" ]; do
    entry="${entries%%"$NL"*}"
    entries="${entries#*"$NL"}"
    name="${entry##*/}"
    case "$dir" in
      */) path="$dir$name" ;;
      *) path="$dir/$name" ;;
    esac
    if [ -d "$path" ]; then
      case "$name" in
        .git|node_modules|vendor|target) ;;
        *) subdirs="$subdirs$name$NL" ;;
      esac
      continue
    fi
    if [ "$name" = "$FND_NAME" ]; then
      FND_HIT="$path"
      return 0
    fi
  done
  while [ -n "$subdirs" ]; do
    name="${subdirs%%"$NL"*}"
    subdirs="${subdirs#*"$NL"}"
    case "$dir" in
      */) path="$dir$name" ;;
      *) path="$dir/$name" ;;
    esac
    [ -L "$path" ] && continue
    _walk_find "$path"
    [ -z "$FND_HIT" ] || return 0
  done
  return 0
}

# _find_first ROOT NAME -> FND_HIT ("" when the file is nowhere in scan range)
_find_first() {
  FND_NAME="$2"
  FND_HIT=""
  _walk_find "$1"
}

# ---------------------------------------------------------------- package survey

# Root plus immediate non-symlink child directories that carry a package signal.
_list_packages() {
  local target="$1" entries entry name path
  PKG_PATH=("$target")
  PKG_REL=(".")
  _list_dir "$target"
  entries="$DIR_ENTRIES"
  while [ -n "$entries" ]; do
    entry="${entries%%"$NL"*}"
    entries="${entries#*"$NL"}"
    name="${entry##*/}"
    case "$name" in
      .*) continue ;;
    esac
    _join "$target" "$name"
    path="$JOINED"
    [ -L "$path" ] && continue
    [ -d "$path" ] || continue
    if [ -e "$path/package.json" ] || [ -e "$path/pyproject.toml" ] ||
      [ -e "$path/requirements.txt" ] || [ -e "$path/go.mod" ] ||
      [ -e "$path/Cargo.toml" ] || [ -e "$path/Makefile" ] ||
      [ -e "$path/.claude-plugin" ] || [ -e "$path/.codex-plugin" ]; then
      PKG_PATH[${#PKG_PATH[@]}]="$path"
      PKG_REL[${#PKG_REL[@]}]="$name"
    fi
  done
}

# _detect_stack PACKAGE -> STACKS_OUT, one stack per line.
_detect_stack() {
  local pkg="$1" out="" plugin=0
  [ -f "$pkg/package.json" ] && out="${out}javascript-typescript$NL"
  if [ -f "$pkg/pyproject.toml" ] || [ -f "$pkg/requirements.txt" ]; then
    out="${out}python$NL"
  fi
  [ -f "$pkg/go.mod" ] && out="${out}go$NL"
  [ -f "$pkg/Cargo.toml" ] && out="${out}rust$NL"
  [ -e "$pkg/.claude-plugin" ] && plugin=1
  [ -e "$pkg/.codex-plugin" ] && plugin=1
  [ -e "$pkg/plugins" ] && plugin=1
  [ "$plugin" -eq 1 ] && out="${out}shell-plugin$NL"
  [ -f "$pkg/Makefile" ] && out="${out}make$NL"
  STACKS_OUT="$out"
  return 0
}

# _makefile_targets PACKAGE -> MK_TARGETS, sorted and deduplicated, one per line.
_makefile_targets() {
  local raw
  MK_TARGETS=""
  [ -f "$1/Makefile" ] || return 0
  raw=$(LC_ALL=C sed -n 's/^\([A-Za-z0-9][^:]*\):.*/\1/p' "$1/Makefile" 2>/dev/null)
  _sortlines_u "$raw"
  MK_TARGETS="$SORTED"
}

# ---------------------------------------------------------------- capabilities

_owner_gates() {
  local punch
  _join "$1" "punch-list.md"
  punch="$JOINED"
  if [ ! -f "$punch" ]; then
    _set_cap "owner-gates" "unavailable" "no punch-list.md" "$punch" "declared"
  elif LC_ALL=C grep -qF -- '## Gates' "$punch" 2>/dev/null; then
    _set_cap "owner-gates" "available-and-verified" "owner Gates block present" "$punch" "declared"
  else
    _set_cap "owner-gates" "unavailable" "punch list has no Gates block" "$punch" "declared"
  fi
}

# Markdown, HTML and source-export capabilities. Reported in both work modes.
_doc_caps() {
  local target="$1"
  DOC_MD_N=0
  DOC_MD_FIRST=""
  DOC_HTML_N=0
  DOC_HTML_FIRST=""
  DOC_STOP=0
  _walk_docs "$target"
  if [ "$DOC_MD_N" -gt 0 ]; then
    _set_cap "local-markdown" "available-and-verified" "$DOC_MD_N markdown files" "$DOC_MD_FIRST" "observed"
    _set_cap "source-export" "available-and-verified" "local files can be cited" "$DOC_MD_FIRST" "observed"
  else
    _set_cap "local-markdown" "unavailable" "no markdown files" "$target" "observed"
    _set_cap "source-export" "unavailable" "no local source files" "$target" "observed"
  fi
  if [ "$DOC_HTML_N" -gt 0 ]; then
    _set_cap "local-html" "available-and-verified" "$DOC_HTML_N html files" "$DOC_HTML_FIRST" "observed"
  else
    _set_cap "local-html" "unavailable" "no html files" "$target" "observed"
  fi
}

# _cap_probes CAP -> PROBES, one "<command> <stack>" per line; "-" means any stack.
_cap_probes() {
  case "$1" in
    lint) PROBES="eslint javascript-typescript${NL}ruff python${NL}golangci-lint go$NL" ;;
    typecheck) PROBES="tsc javascript-typescript${NL}mypy python$NL" ;;
    test) PROBES="node javascript-typescript${NL}pytest python${NL}go go${NL}cargo rust${NL}bats shell-plugin$NL" ;;
    coverage) PROBES="c8 javascript-typescript${NL}pytest python${NL}go go$NL" ;;
    dead-code) PROBES="knip javascript-typescript${NL}vulture python$NL" ;;
    build) PROBES="tsc javascript-typescript${NL}go go${NL}cargo rust$NL" ;;
    security) PROBES="npm javascript-typescript${NL}pip-audit python${NL}govulncheck go$NL" ;;
    documentation-link) PROBES="markdown-link-check -$NL" ;;
    accessibility) PROBES="axe -${NL}pa11y -$NL" ;;
    browser) PROBES="chrome -${NL}chromium -$NL" ;;
    connector) PROBES="gh -$NL" ;;
    *) PROBES="" ;;
  esac
}

# _script_hint CAP -> HINT_KEY, empty when the capability has no package.json hint.
_script_hint() {
  case "$1" in
    test) HINT_KEY="test" ;;
    lint) HINT_KEY="lint" ;;
    typecheck) HINT_KEY="typecheck" ;;
    coverage) HINT_KEY="coverage" ;;
    build) HINT_KEY="build" ;;
    *) HINT_KEY="" ;;
  esac
}

_repo_caps() {
  local target="$1" ns="$2"
  local i n pkg rel names name targets probes probe scripts scripts_n stacks all_stacks
  local cap cmd stack hit found declared path

  _doc_caps "$target"
  _list_packages "$target"
  n=${#PKG_PATH[@]}

  PKG_SCRIPTS=()
  PKG_TARGETS=()
  all_stacks=""
  i=0
  while [ "$i" -lt "$n" ]; do
    pkg="${PKG_PATH[$i]}"
    _detect_stack "$pkg"
    all_stacks="$all_stacks$STACKS_OUT"
    _join "$pkg" "package.json"
    names=$(_script_names "$JOINED")
    [ -z "$names" ] || names="$names$NL"
    PKG_SCRIPTS[i]="$names"
    _makefile_targets "$pkg"
    PKG_TARGETS[i]="$MK_TARGETS"
    i=$((i + 1))
  done
  _sortlines_u "$all_stacks"
  stacks="$SORTED"

  emit s topology root "$target"
  i=0
  while [ "$i" -lt "$n" ]; do
    emit a topology packages "${PKG_PATH[$i]}"
    i=$((i + 1))
  done
  if [ "$n" -gt 1 ]; then
    emit b topology monorepo 1
  else
    emit b topology monorepo 0
  fi
  emit A topology stacks ""
  names="$stacks"
  while [ -n "$names" ]; do
    name="${names%%"$NL"*}"
    names="${names#*"$NL"}"
    emit a topology stacks "$name"
  done

  _owner_gates "$ns"

  scripts=""
  scripts_n=0
  i=0
  while [ "$i" -lt "$n" ]; do
    rel="${PKG_REL[$i]}"
    names="${PKG_SCRIPTS[$i]}"
    while [ -n "$names" ]; do
      name="${names%%"$NL"*}"
      names="${names#*"$NL"}"
      if [ "$scripts_n" -lt 12 ]; then
        [ -z "$scripts" ] || scripts="$scripts, "
        scripts="$scripts$rel:$name"
      fi
      scripts_n=$((scripts_n + 1))
    done
    targets="${PKG_TARGETS[$i]}"
    while [ -n "$targets" ]; do
      name="${targets%%"$NL"*}"
      targets="${targets#*"$NL"}"
      if [ "$scripts_n" -lt 12 ]; then
        [ -z "$scripts" ] || scripts="$scripts, "
        scripts="${scripts}make:$name"
      fi
      scripts_n=$((scripts_n + 1))
    done
    i=$((i + 1))
  done
  if [ "$scripts_n" -gt 0 ]; then
    _set_cap "scripts" "available-and-verified" "declared scripts: $scripts" "$target" "declared"
    _set_cap "task-runner" "available-and-verified" "declared scripts: $scripts" "$target" "declared"
  else
    _set_cap "scripts" "unavailable" "no package.json scripts or Makefile targets" "$target" "observed"
    _set_cap "task-runner" "unavailable" "no package.json scripts or Makefile targets" "$target" "observed"
  fi

  hit=""
  for rel in ".github/workflows" ".gitlab-ci.yml" "azure-pipelines.yml"; do
    _join "$target" "$rel"
    if [ -e "$JOINED" ]; then
      hit="$JOINED"
      break
    fi
  done
  if [ -n "$hit" ]; then
    _set_cap "ci" "available-and-verified" "CI config present" "$hit" "observed"
  else
    _set_cap "ci" "unavailable" "no CI config" "$target" "observed"
  fi

  for cap in lint typecheck test coverage dead-code build security documentation-link \
    accessibility api-schema localization benchmark mutation-fuzz seo-performance \
    browser connector structured-results; do
    _merge_reset
    _cap_probes "$cap"
    probes="$PROBES"
    while [ -n "$probes" ]; do
      probe="${probes%%"$NL"*}"
      probes="${probes#*"$NL"}"
      cmd="${probe%% *}"
      stack="${probe#* }"
      if [ "$stack" != "-" ] && ! _has_line "$stacks" "$stack"; then
        continue
      fi
      _probe_command "$cmd" "$target"
      _merge_offer "$PC_STATUS" "$PC_REASON" "$PC_LOCATOR" "$PC_LADDER"
    done

    _script_hint "$cap"
    if [ -n "$HINT_KEY" ]; then
      declared=0
      i=0
      while [ "$i" -lt "$n" ]; do
        if _has_line "${PKG_SCRIPTS[$i]}" "$HINT_KEY"; then
          declared=1
          break
        fi
        i=$((i + 1))
      done
      if [ "$declared" -eq 1 ]; then
        _join "${PKG_PATH[0]}" "package.json"
        _merge_offer "available-and-verified" \
          "package.json scripts.$HINT_KEY is declared; not proof of a binary" \
          "$JOINED" "declared"
      fi
    fi

    if [ "$cap" = "test" ]; then
      declared=0
      i=0
      while [ "$i" -lt "$n" ]; do
        if _has_line "${PKG_TARGETS[$i]}" "test"; then
          declared=1
          break
        fi
        i=$((i + 1))
      done
      if [ "$declared" -eq 1 ]; then
        _merge_offer "available-and-verified" "Makefile test target declared" "$target" "declared"
      fi
    fi

    if [ "$cap" = "structured-results" ]; then
      found=""
      for name in "junit.xml" "coverage.lcov" "lcov.info"; do
        _find_first "$target" "$name"
        if [ -n "$FND_HIT" ]; then
          found="$FND_HIT"
          break
        fi
      done
      if [ -n "$found" ]; then
        _merge_offer "available-and-verified" "structured result file present" "$found" "observed"
      fi
    fi

    if [ "$cap" = "api-schema" ]; then
      for name in "openapi.yaml" "openapi.yml" "openapi.json" "schema.graphql"; do
        _join "$target" "$name"
        path="$JOINED"
        if [ -f "$path" ]; then
          _merge_offer "available-and-verified" "schema file present" "$path" "observed"
        fi
      done
    fi

    if [ "$cap" = "localization" ]; then
      for name in "locales" "i18n" "translations"; do
        _join "$target" "$name"
        path="$JOINED"
        if [ -d "$path" ]; then
          _merge_offer "available-and-verified" "locale directory present" "$path" "observed"
        fi
      done
    fi

    _merge_commit "$cap"
  done
}

_artifact_caps() {
  local target="$1" caps="$2" name
  _doc_caps "$target"
  emit s topology root "$target"
  emit a topology packages "$target"
  emit b topology monorepo 0
  emit A topology stacks ""
  while [ -n "$caps" ]; do
    name="${caps%%"$NL"*}"
    caps="${caps#*"$NL"}"
    case "$name" in
      local-markdown|local-html|source-export) continue ;;
    esac
    _set_cap "$name" "unavailable" "artifact mode does not probe repository tools" "$target" "declared"
  done
}

# ---------------------------------------------------------------- contracts

_flush_contract() {
  local cap rest missing missing_n any_ok reason
  [ -n "$CT_ID" ] || return 0

  if [ "$CT_ARTIFACT" = "false" ] && [ "$WORK_MODE" = "artifact" ]; then
    emit b contracts "$CT_ID" applies 0
    emit s contracts "$CT_ID" reason "contract is skipped in artifact mode"
    emit A contracts "$CT_ID" missing ""
    if [ "$CT_FB_NULL" -eq 1 ]; then
      emit z contracts "$CT_ID" fallback ""
    else
      emit s contracts "$CT_ID" fallback "$CT_FALLBACK"
    fi
    CT_ID=""
    return 0
  fi

  missing=""
  missing_n=0
  rest="$CT_REQUIRES"
  while [ -n "$rest" ]; do
    cap="${rest%%"$NL"*}"
    rest="${rest#*"$NL"}"
    _cap_status "$cap"
    case "$CAPSTATUS" in
      unavailable|provisionable)
        missing="$missing$cap$NL"
        missing_n=$((missing_n + 1))
        ;;
    esac
  done

  if [ -n "$CT_ANY" ]; then
    any_ok=0
    rest="$CT_ANY"
    while [ -n "$rest" ]; do
      cap="${rest%%"$NL"*}"
      rest="${rest#*"$NL"}"
      _cap_status "$cap"
      case "$CAPSTATUS" in
        available-and-verified|available-but-failing|fallback-only)
          any_ok=1
          break
          ;;
      esac
    done
    if [ "$any_ok" -eq 0 ]; then
      rest="$CT_ANY"
      while [ -n "$rest" ]; do
        cap="${rest%%"$NL"*}"
        rest="${rest#*"$NL"}"
        missing="$missing$cap$NL"
        missing_n=$((missing_n + 1))
      done
    fi
  fi

  emit A contracts "$CT_ID" missing ""
  reason=""
  rest="$missing"
  while [ -n "$rest" ]; do
    cap="${rest%%"$NL"*}"
    rest="${rest#*"$NL"}"
    emit a contracts "$CT_ID" missing "$cap"
    [ -z "$reason" ] || reason="$reason, "
    reason="$reason$cap"
  done

  if [ "$missing_n" -gt 0 ]; then
    if [ "$CT_FB_NULL" -eq 0 ] && [ -n "$CT_FALLBACK" ]; then
      emit b contracts "$CT_ID" applies 1
      emit s contracts "$CT_ID" reason "fallback: $CT_FALLBACK"
      emit s contracts "$CT_ID" fallback "$CT_FALLBACK"
      emit s contracts "$CT_ID" status "fallback-only"
    else
      emit b contracts "$CT_ID" applies 0
      emit s contracts "$CT_ID" reason "missing capabilities: $reason"
      emit z contracts "$CT_ID" fallback ""
    fi
  else
    emit b contracts "$CT_ID" applies 1
    emit s contracts "$CT_ID" reason "required capabilities are present"
    if [ "$CT_FB_NULL" -eq 1 ]; then
      emit z contracts "$CT_ID" fallback ""
    else
      emit s contracts "$CT_ID" fallback "$CT_FALLBACK"
    fi
  fi
  CT_ID=""
}

_emit_contracts() {
  local line tag rest
  CT_ID=""
  CT_ARTIFACT="null"
  CT_FB_NULL=1
  CT_FALLBACK=""
  CT_REQUIRES=""
  CT_ANY=""
  while IFS= read -r line; do
    tag="${line%%"$TAB"*}"
    rest="${line#*"$TAB"}"
    case "$tag" in
      K)
        _flush_contract
        CT_ID="$rest"
        CT_ARTIFACT="null"
        CT_FB_NULL=1
        CT_FALLBACK=""
        CT_REQUIRES=""
        CT_ANY=""
        ;;
      A) CT_ARTIFACT="${rest#*"$TAB"}" ;;
      Fs)
        CT_FB_NULL=0
        CT_FALLBACK="${rest#*"$TAB"}"
        ;;
      Fn)
        CT_FB_NULL=1
        CT_FALLBACK=""
        ;;
      R)
        rest="${rest#*"$TAB"}"
        [ -z "$rest" ] || CT_REQUIRES="${rest// /$NL}$NL"
        ;;
      Y)
        rest="${rest#*"$TAB"}"
        [ -z "$rest" ] || CT_ANY="${rest// /$NL}$NL"
        ;;
    esac
  done <"$TMPD/meta"
  _flush_contract
}

# ---------------------------------------------------------------- main

PROJECT=""
HOST="claude"
NORMALIZE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project|-p)
      [ $# -ge 2 ] || usage
      PROJECT="$2"
      shift 2
      ;;
    --host)
      [ $# -ge 2 ] || usage
      HOST="$2"
      shift 2
      ;;
    --normalize)
      NORMALIZE=1
      shift
      ;;
    *) usage ;;
  esac
done

[ -n "$PROJECT" ] || usage
_abspath "$PROJECT"
PROJECT="$ABSPATH"
if [ ! -d "$PROJECT" ]; then
  printf 'detect-capabilities: not a directory: %s\n' "$PROJECT" >&2
  exit 1
fi

_pick_json_tool
TMPD=""
trap _cleanup EXIT
_mktmp

_load_meta >"$TMPD/meta" || {
  printf 'detect-capabilities: cannot read the v1 schemas under %s\n' "$SCHEMA" >&2
  exit 1
}

HOSTS=""
CAPLIST=""
PROVDEF="null"
while IFS= read -r _line; do
  case "$_line" in
    "H$TAB"*) HOSTS="$HOSTS${_line#*"$TAB"}$NL" ;;
    "C$TAB"*) CAPLIST="$CAPLIST${_line#*"$TAB"}$NL" ;;
    "P$TAB"*) PROVDEF="${_line#*"$TAB"}" ;;
  esac
done <"$TMPD/meta"

if ! _has_line "$HOSTS" "$HOST"; then
  printf 'unknown host: %s\n' "$HOST" >&2
  exit 1
fi

NS="$PROJECT/.nightshift"
WORK_MODE="repository"
if [ -f "$NS/work-mode" ]; then
  _strip_ws "$(<"$NS/work-mode")"
  [ -z "$STRIPPED" ] || WORK_MODE="$STRIPPED"
fi
TARGET="$PROJECT"
if [ -f "$NS/work-target" ]; then
  _strip_ws "$(<"$NS/work-target")"
  [ -z "$STRIPPED" ] || TARGET="$STRIPPED"
fi
ENV_PATH="${PATH:-}"

exec 3>"$TMPD/doc.rec"
emit n schemaVersion 1
[ "$NORMALIZE" -eq 1 ] || emit s host "$HOST"
emit s workMode "$WORK_MODE"
emit s workTarget "$TARGET"
if [ "$WORK_MODE" = "artifact" ]; then
  _artifact_caps "$TARGET" "$CAPLIST"
else
  _repo_caps "$TARGET" "$NS"
fi
_emit_contracts
emit j provisioningDefault "$PROVDEF"
exec 3>&-

_serialize "$TMPD/doc.rec"
