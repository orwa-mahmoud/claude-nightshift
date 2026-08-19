#!/usr/bin/env bash
# Workspace resolution and canonical path helpers shared by Nightshift hooks.

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
  local host target canonical tmp exclude git_dir
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

# ns_path_under_protected <path> <protectedDirs>
ns_path_under_protected() {
  local path="${1#./}" d
  path="${path#./}"
  IFS=' |' read -ra _ns_pd_dirs <<<"$2"
  for d in "${_ns_pd_dirs[@]}"; do
    [ -n "$d" ] || continue
    d="${d#./}"
    case "$path" in
      "$d" | "$d"/* | */"$d" | */"$d"/*) return 0 ;;
    esac
  done
  return 1
}

# ns_under_nightshift <workspace> <relative-path>
# Print the canonical path when it resolves to a real child of .nightshift/.
# Rejects symlinks, traversal, and anything that escapes the root.
ns_under_nightshift() {
  local ws="$1" rel="$2" ns root parent base canon
  case "$rel" in
    '' | /* | *..*) return 1 ;;
  esac
  ns="$ws/.nightshift"
  root="$(cd -P "$ns" 2>/dev/null && pwd)" || return 1
  [ ! -L "$ns/$rel" ] || return 1
  if [ -d "$ns/$rel" ]; then
    canon="$(cd -P "$ns/$rel" 2>/dev/null && pwd)" || return 1
  elif [ -f "$ns/$rel" ]; then
    base="${rel##*/}"
    if [ "$rel" = "$base" ]; then
      parent="$root"
    else
      parent="$(cd -P "$ns/${rel%/*}" 2>/dev/null && pwd)" || return 1
    fi
    [ -f "$parent/$base" ] || return 1
    [ ! -L "$parent/$base" ] || return 1
    canon="$parent/$base"
  else
    return 1
  fi
  case "$canon" in
    "$root"/*) ;;
    *) return 1 ;;
  esac
  printf '%s' "$canon"
}

# Qualify bare .nightshift/ mentions in owner-authored injection text (clock-out,
# revival, toolDeny) so a drifted cwd cannot send the agent to a nested copy.
# Expansion happens at injection time; the owner's rules file keeps the relative
# form so it stays editable without a skill variable.
ns_expand_injected_paths() {
  local ws="$1" text="$2"
  [ -n "$ws" ] || { printf '%s' "$text"; return 0; }
  text="${text//\$NIGHTSHIFT_WORKSPACE/$ws}"
  text="${text//\$NS/$ws/.nightshift}"
  printf '%s' "$text" | awk -v ws="$ws" '
    BEGIN { ORS="" }
    {
      s = $0
      while (match(s, /\.nightshift[\/\\]/)) {
        prefix = substr(s, 1, RSTART - 1)
        chunk = substr(s, RSTART, RLENGTH)
        sep = substr(chunk, length(chunk), 1)
        last = (length(prefix) ? substr(prefix, length(prefix), 1) : "")
        if (last == "/" || last == "\\") {
          printf "%s%s", prefix, chunk
        } else {
          printf "%s%s/.nightshift%s", prefix, ws, sep
        }
        s = substr(s, RSTART + RLENGTH)
      }
      printf "%s", s
    }
  '
}
