#!/usr/bin/env bash
# lib.sh — shared hook helpers.

# ns_workspace_root <host-root>
#
# Resolve the one workspace that owns Nightshift state. Normally that is the task root itself.
# A task opened elsewhere may opt in explicitly with a local .nightshift-link containing one
# absolute path to a directory that already owns .nightshift/. We never search parent or sibling
# directories: an absent link means local state; a malformed link returns 2 so callers can fail
# closed instead of silently running without the owner's contract.
ns_workspace_root() {
  local host="$1" link="$1/.nightshift-link" target="" lines="" canonical=""
  canonical="$(cd -P "$host" 2>/dev/null && pwd)" || {
    return 2
  }
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    printf '%s' "$canonical"
    return 0
  fi
  if [ ! -f "$link" ] || [ -L "$link" ]; then
    return 2
  fi
  IFS= read -r target <"$link" || true
  lines="$(awk 'END { print NR + 0 }' "$link" 2>/dev/null)"
  if [ -z "$target" ] || [ "$lines" -ne 1 ]; then
    return 2
  fi
  case "$target" in /*) ;; *)
    return 2
  esac
  canonical="$(cd -P "$target" 2>/dev/null && pwd)" || {
    return 2
  }
  [ -d "$canonical/.nightshift" ] || {
    return 2
  }
  printf '%s' "$canonical"
}

# ns_record_workspace_link <host-root> <workspace>
# Validate and atomically record a cross-workspace link. The pointer is machine-local, so when
# the host is a Git repository it goes in .git/info/exclude rather than changing tracked files.
ns_record_workspace_link() {
  local host target canonical tmp exclude
  host="$(cd -P "$1" 2>/dev/null && pwd)" || return 1
  target="$2"
  case "$target" in /*) ;; *) return 1 ;; esac
  canonical="$(cd -P "$target" 2>/dev/null && pwd)" || return 1
  [ -d "$canonical/.nightshift" ] || return 1
  tmp="$host/.nightshift-link.$$"
  printf '%s\n' "$canonical" >"$tmp" || return 1
  mv "$tmp" "$host/.nightshift-link" || return 1
  if git_dir="$(git -C "$host" rev-parse --git-dir 2>/dev/null)"; then
    case "$git_dir" in /*) ;; *) git_dir="$host/$git_dir" ;; esac
    exclude="$git_dir/info/exclude"
    mkdir -p "${exclude%/*}" || return 1
    grep -qxF '.nightshift-link' "$exclude" 2>/dev/null || printf '%s\n' '.nightshift-link' >>"$exclude"
  fi
}

# repo_root <project-dir> [candidate-dir ...]
#
# Echo the top level of the git repository the hooks should inspect, or return 1 when that
# cannot be decided. The recommended layout opens Claude Code in a plain workspace folder that
# holds the repo one level down, so the project dir is frequently not a repository itself:
#
#   my-project/        <- project dir, not a repo
#   ├── repo/          <- what the guards must inspect
#   └── .nightshift/   <- run state, with its own receipts repo
#
# Candidates are tried in order — the tool's own working directory first, since a commit runs
# from inside the repo it lands in — then the project dir, then a single level below it.
# Children whose own name is hidden are skipped, which keeps .nightshift's receipts repo out of
# the search; a hidden component anywhere else in the path is none of our business.
# Two distinct repositories below the project dir are undecidable: callers that guard a commit
# must treat that as a denial rather than pick one.
repo_root() {
  local project="$1"
  shift
  local d top found="" child base

  for d in "$@" "$project"; do
    [ -n "$d" ] || continue
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || continue
    printf '%s' "$top"
    return 0
  done

  for child in "$project"/*/; do
    base="${child%/}"
    base="${base##*/}"
    case "$base" in .*) continue ;; esac
    top="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || continue
    if [ -n "$found" ] && [ "$found" != "$top" ]; then
      return 1
    fi
    found="$top"
  done

  [ -n "$found" ] || return 1
  printf '%s' "$found"
}

# ns_work_target <workspace>
#
# Resolve the repository Nightshift works on while keeping run state in <workspace>/.nightshift.
# Setup persists the choice in .nightshift/work-target; readers prefer that record so resumed,
# scheduled, and revived sessions do not rediscover a different repository. The record may be an
# absolute path or a path relative to the workspace. Return 2 when several child repositories make
# an unstored choice ambiguous, 1 when no repository can be resolved.
ns_work_target() {
  local project="$1" record="$1/.nightshift/work-target" target="" child base top found=""
  if [ -s "$record" ]; then
    IFS= read -r target <"$record" || true
    case "$target" in /*) ;; *) target="$project/$target" ;; esac
    top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || return 1
    printf '%s' "$top"
    return 0
  fi

  if top="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s' "$top"
    return 0
  fi

  for child in "$project"/*/; do
    base="${child%/}"; base="${base##*/}"
    case "$base" in .*) continue ;; esac
    top="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || continue
    if [ -n "$found" ] && [ "$found" != "$top" ]; then return 2; fi
    found="$top"
  done
  [ -n "$found" ] || return 1
  printf '%s' "$found"
}

# ns_record_work_target <workspace> <repository>
# Persist an absolute canonical repository path atomically.
ns_record_work_target() {
  local project="$1" target top tmp
  target="$2"
  top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || return 1
  mkdir -p "$project/.nightshift" || return 1
  tmp="$project/.nightshift/.work-target.$$"
  printf '%s\n' "$top" >"$tmp" || return 1
  mv "$tmp" "$project/.nightshift/work-target"
}

# target_repo <command> <base-dir>
#
# A command can name the repository it acts on — `git -C <dir> commit`, or `cd <dir> && git
# commit` — and that repository, not the session's working directory, is where the commit
# lands. Resolve it so the guards inspect what is actually being written to.
#
#   0 + path  the command names a directory and it resolves to a repository
#   1         it names one that is NOT a repository — nothing can be verified about it
#   2         it names none; the caller should fall back to repo_root
target_repo() {
  local cmd="$1" base="$2" d=""

  d="$(printf '%s' "$cmd" |
    sed -n "s/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}['\"]\{0,1\}\([^'\"[:space:];&|]\{1,\}\).*/\1/p" |
    head -n1)"
  if [ -z "$d" ]; then
    d="$(printf '%s' "$cmd" |
      sed -n "s/^[[:space:]]*cd[[:space:]]\{1,\}['\"]\{0,1\}\([^'\"[:space:];&|]\{1,\}\)['\"]\{0,1\}[[:space:]]*&&.*/\1/p" |
      head -n1)"
  fi
  [ -n "$d" ] || return 2

  case "$d" in /*) ;; *) d="$base/$d" ;; esac
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
  printf '%s' "$top"
  return 0
}

# commit_stages_implicitly <command>
#
# True when a `git commit` will pick up changes the index does not hold yet: `-a`/`--all` (and
# clustered short forms such as `-am`), or an explicit pathspec after `--`. Those commits are
# not described by `git diff --cached`, so a guard reading only the index would inspect the
# wrong content.
commit_stages_implicitly() {
  printf '%s' "$1" | grep -qE '(^|[[:space:]])--all([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -qE '(^|[[:space:]])-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -qE '(^|[[:space:]])--([[:space:]]|$)' && return 0
  return 1
}

# valid_ere <pattern> — true when grep -E accepts the pattern.
# An invalid pattern makes grep exit 2, which reads exactly like "no match" to a plain `if`,
# so a typo in an owner's guard pattern would silently disable the guard.
valid_ere() {
  printf '' | grep -qE "$1" 2>/dev/null
  [ "$?" -le 1 ]
}

# The owner's rules file is the one copy of every knob: .nightshift/rules.json — nightshift's
# whole life lives in nightshift's folder, and deleting the folder deletes all of it. Hooks
# read the file directly — a change applies from the next tool call. An env var of the
# matching name, when set, overrides the file for the session: the test suite's lever and the
# power user's per-session exception, never a second copy the owner maintains.
# rule <project-dir> <file-key> <env-value> — prints the effective value ('' = default).
rule() {
  if [ -n "$3" ]; then printf '%s' "$3"; return; fi
  local f="$1/.nightshift/rules.json"
  [ -f "$f" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" '.[$k] // empty | if type == "object" or type == "array" then tojson else tostring end' "$f" 2>/dev/null
  else
    sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | sed -n 1p
  fi
}

# Cross-session mutex over one .nightshift/ — mkdir is the one atomic primitive every platform
# here ships (macOS has no flock). The holder writes its pid inside; a lock whose holder is
# provably dead is broken on sight, a mid-claim lock (no pid yet) is waited on, never stolen.
# The wait is bounded because a Stop hook must never hang a session over bookkeeping: on
# timeout the caller proceeds without the lock, and the race window is merely what it was
# before locks existed.
ns_lock() { # $1 = the .nightshift dir; bounded ~2s wait
  local dir="$1/.lock.d" holder _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "$dir" 2>/dev/null; then
      printf '%s' "$$" >"$dir/pid" 2>/dev/null || true
      return 0
    fi
    holder="$(cat "$dir/pid" 2>/dev/null)"
    case "$holder" in
      '' | *[!0-9]*) ;;
      *) kill -0 "$holder" 2>/dev/null || { rm -rf "$dir" 2>/dev/null; continue; } ;;
    esac
    sleep 0.2
  done
  return 1
}
ns_unlock() { rm -rf "$1/.lock.d" 2>/dev/null; }

# The punch list's `## Items` heading is the boundary between the owner's contract and the work.
# A checkbox above it is prose — an example, a note — and holds nobody. Both the gate and the
# watchman must agree on that boundary: a watchman counting a different range would keep reviving
# a shift the gate considers finished. One implementation is how they cannot disagree.
ns_items_section() { sed -n '/^## Items[[:space:]]*$/,$p' "$1" 2>/dev/null; }

# grep -c prints the count AND exits 1 on zero matches; keep the number, drop the status.
ns_count_boxes() { # $1 = punch list, $2 = ERE for the box state
  local n
  n="$(ns_items_section "$1" | grep -cE "$2" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

ns_open_boxes()   { ns_count_boxes "$1" '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]'; }
ns_ticked_boxes() { ns_count_boxes "$1" '^[[:space:]]*-[[:space:]]*\[[xX]\]'; }

# Which host owns this shift. Absent means a record written before hosts were distinguished,
# and every such record is Claude's — nothing else could have written one.
ns_session_host() {
  local h
  h="$(sed -n 5p "$1/.shift-session" 2>/dev/null | tr -d '[:space:]')"
  printf '%s' "${h:-claude}"
}
