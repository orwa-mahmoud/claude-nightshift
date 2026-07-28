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
# Hidden entries are skipped, which keeps .nightshift's receipts repo out of the search.
# Two distinct repositories below the project dir are undecidable: callers that guard a commit
# must treat that as a denial rather than pick one.
repo_root() {
  local project="$1"
  shift
  local d top found="" child

  for d in "$@" "$project"; do
    [ -n "$d" ] || continue
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || continue
    printf '%s' "$top"
    return 0
  done

  for child in "$project"/*/; do
    case "$child" in */.*/) continue ;; esac
    top="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || continue
    if [ -n "$found" ] && [ "$found" != "$top" ]; then
      return 1
    fi
    found="$top"
  done

  [ -n "$found" ] || return 1
  printf '%s' "$found"
}
