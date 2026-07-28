#!/usr/bin/env bash
# lib.sh — shared hook helpers.

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
