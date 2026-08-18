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

# ns_git_verb_tail <command> <add|commit>
# Print the words after that git verb. Return 1 when the verb is absent.
ns_git_verb_tail() {
  local cmd="$1" verb="$2" seen=0 word
  # shellcheck disable=SC2086
  set -- $cmd
  for word in "$@"; do
    if [ "$seen" -eq 1 ]; then
      printf '%s\n' "$word"
      continue
    fi
    [ "$word" = "$verb" ] && seen=1
  done
  [ "$seen" -eq 1 ]
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

# Replay add/commit against a copied index so guards can ask Git what would be written
# without mutating the real index. 0 = prepared ($NS_GIT_PROSP_DIR, GIT_INDEX_FILE),
# 1 = no-op / empty, 2 = cannot model this command (fail closed).
ns_git_prospective_prepare() { # <repo> <command> <add|commit>
  local repo="$1" cmd="$2" verb="$3" tmp src word rest=0 skip=0 form=index
  local -a paths=()
  NS_GIT_PROSP_DIR=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ns-git.XXXXXX")" || return 2
  src="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)" || { rm -rf "$tmp"; return 2; }
  src="$src/index"
  if [ -f "$src" ]; then
    cp "$src" "$tmp/index" || { rm -rf "$tmp"; return 2; }
  fi
  export GIT_INDEX_FILE="$tmp/index"
  NS_GIT_PROSP_DIR="$tmp"
  git -C "$repo" ls-files --stage -z >"$tmp/before" 2>/dev/null || :

  while IFS= read -r word; do
    [ -n "$word" ] || continue
    if [ "$skip" -eq 1 ]; then
      skip=0
      continue
    fi
    if [ "$rest" -eq 1 ]; then
      [ "$word" = MSG ] || paths+=("$word")
      continue
    fi
    case "$word" in
      --) rest=1 ;;
      --all | -A)
        if [ "$verb" = add ]; then form=all
        else form=tracked
        fi
        ;;
      --update | -u) form=tracked ;;
      --include | -i) [ "$verb" = commit ] && form=include ;;
      --only | -o) [ "$verb" = commit ] && form=only ;;
      -m | --message | --file | --author | --date | --cleanup)
        skip=1
        ;;
      --message=* | --file=* | --author=* | --date=* | MSG) ;;
      --allow-empty | --allow-empty-message | --no-verify | --no-edit | --quiet | --signoff | -q | -s | -n | --no-gpg-sign | --porcelain | --verbose | -v | --force | -f | --ignore-missing | --refresh)
        ;;
      --amend | --patch | -p | --interactive | --chmod=* | --edit | -e | --fixup | --squash | --reuse-message | --reedit-message)
        ns_git_prospective_cleanup
        return 2
        ;;
      -*)
        if [ "$verb" = commit ] && printf '%s' "$word" | grep -qE '^-[[:alpha:]]*a[[:alpha:]]*$'; then
          form=tracked
        elif [ "$verb" = commit ] && printf '%s' "$word" | grep -qE '^-[[:alpha:]]*i[[:alpha:]]*$'; then
          form=include
        elif [ "$verb" = commit ] && printf '%s' "$word" | grep -qE '^-[[:alpha:]]*o[[:alpha:]]*$'; then
          form=only
        elif [ "$verb" = add ] && printf '%s' "$word" | grep -qE '^-[[:alpha:]]*A[[:alpha:]]*$'; then
          form=all
        elif [ "$verb" = add ] && printf '%s' "$word" | grep -qE '^-[[:alpha:]]*u[[:alpha:]]*$'; then
          form=tracked
        else
          ns_git_prospective_cleanup
          return 2
        fi
        ;;
      *) [ "$word" = MSG ] || paths+=("$word") ;;
    esac
  done < <(ns_git_verb_tail "$cmd" "$verb")

  if [ "$verb" = commit ] && [ "${#paths[@]}" -gt 0 ] && [ "$form" = index ]; then
    form=only
  fi

  case "$verb-$form" in
    add-index)
      if [ "${#paths[@]}" -eq 0 ]; then
        :
      else
        git -C "$repo" add -- "${paths[@]}" >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; }
      fi
      ;;
    add-all) git -C "$repo" add -A >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; } ;;
    add-tracked) git -C "$repo" add -u >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; } ;;
    commit-index) ;;
    commit-tracked) git -C "$repo" add -u >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; } ;;
    commit-include)
      if [ "${#paths[@]}" -gt 0 ]; then
        git -C "$repo" add -- "${paths[@]}" >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; }
      fi
      ;;
    commit-only)
      git -C "$repo" read-tree HEAD >/dev/null 2>&1 || git -C "$repo" read-tree --empty >/dev/null 2>&1 || {
        ns_git_prospective_cleanup
        return 2
      }
      if [ "${#paths[@]}" -gt 0 ]; then
        git -C "$repo" add -- "${paths[@]}" >/dev/null 2>&1 || { ns_git_prospective_cleanup; return 2; }
      fi
      ;;
    *) ns_git_prospective_cleanup; return 2 ;;
  esac
  return 0
}

ns_git_prospective_cleanup() {
  [ -n "${NS_GIT_PROSP_DIR:-}" ] && rm -rf "$NS_GIT_PROSP_DIR"
  unset GIT_INDEX_FILE NS_GIT_PROSP_DIR
}

# Print NUL-delimited paths this add/commit would write. 2 = cannot model.
ns_git_prospective_paths() { # <repo> <command> <add|commit>
  local repo="$1" cmd="$2" verb="$3" rc line
  ns_git_prospective_prepare "$repo" "$cmd" "$verb"
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  if [ "$verb" = add ]; then
    tr '\0' '\n' <"$NS_GIT_PROSP_DIR/before" >"$NS_GIT_PROSP_DIR/before.nl" 2>/dev/null || :
    git -C "$repo" ls-files --stage -z 2>/dev/null | tr '\0' '\n' | while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -F -x -- "$line" "$NS_GIT_PROSP_DIR/before.nl" >/dev/null 2>&1 && continue
      printf '%s\0' "${line#*	}"
    done
  else
    git -C "$repo" diff --cached --name-only -z --no-ext-diff HEAD 2>/dev/null \
      || git -C "$repo" diff --cached --name-only -z --no-ext-diff 2>/dev/null \
      || true
  fi
  ns_git_prospective_cleanup
  return 0
}

# Print the diff this commit would write. 2 = cannot model.
ns_git_prospective_diff() { # <repo> <command>
  local repo="$1" cmd="$2" rc
  ns_git_prospective_prepare "$repo" "$cmd" commit
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  git -C "$repo" diff --cached --no-ext-diff HEAD 2>/dev/null \
    || git -C "$repo" diff --cached --no-ext-diff 2>/dev/null \
    || true
  ns_git_prospective_cleanup
  return 0
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

# toolDeny requires exact JSON key matching. Normalize it with jq or Python; never approximate
# owner policy with grep. The sentinel makes malformed input and parserless hosts fail closed.
ns_tool_map_ok() { # stdin = a JSON object of string values
  if command -v jq >/dev/null 2>&1; then
    jq -ce 'if type == "object" and all(.[]; type == "string") then . else error("invalid tool map") end' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
d=json.load(sys.stdin)
assert isinstance(d,dict) and all(isinstance(v,str) for v in d.values())
print(json.dumps(d,separators=(",",":")))' 2>/dev/null
  else
    return 2
  fi
}

ns_tool_rules() { # $1 = project dir, $2 = session override
  local f="$1/.nightshift/rules.json" raw out rc
  if [ -n "$2" ]; then
    raw="$2"
  else
    [ -f "$f" ] || return 0
    if command -v jq >/dev/null 2>&1; then
      raw="$(jq -ce '.toolDeny // {}' "$f" 2>/dev/null)" || {
        printf '%s' '__nightshift_invalid_tool_rules__'
        return
      }
    elif command -v python3 >/dev/null 2>&1; then
      raw="$(python3 -c 'import json,sys
print(json.dumps(json.load(open(sys.argv[1])).get("toolDeny",{}),separators=(",",":")))' "$f" 2>/dev/null)" || {
        printf '%s' '__nightshift_invalid_tool_rules__'
        return
      }
    else
      printf '%s' '__nightshift_tool_rules_parser_missing__'
      return
    fi
  fi
  out="$(printf '%s' "$raw" | ns_tool_map_ok)"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    printf '%s' '__nightshift_tool_rules_parser_missing__'
    return
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%s' '__nightshift_invalid_tool_rules__'
    return
  fi
  printf '%s' "$out"
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

# One active shift may keep one conversation identity across several host processes. The
# conversation record preserves continuity; this lease fences the process that currently owns
# that conversation after a watchman revival. Its six lines are:
#   original session scope · host · generation · revival token · process pid · process start time
# The token is empty for the original interactive process. A watchman writes a new token and
# generation before every spawn, so an older process carrying the same session id is fenced.
ns_lease_lock() { # $1 = the .nightshift dir; bounded ~2s wait
  local dir="$1/.lease-lock.d" holder _
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
ns_lease_unlock() { rm -rf "$1/.lease-lock.d" 2>/dev/null; }

ns_lease_safe_line() {
  case "$1" in
    *$'\n'* | *$'\r'*) return 1 ;;
  esac
  return 0
}

ns_session_write() { # <ns> <sid> <transcript> <pid> <start> <host> <tmp>; validates and writes tmp
  local ns="$1" sid="$2" transcript="$3" pid="$4" start="$5" host="$6" tmp="$7"
  [ -d "$ns" ] && [ -n "$sid" ] || return 1
  ns_lease_safe_line "$sid" && ns_lease_safe_line "$transcript" \
    && ns_lease_safe_line "$pid" && ns_lease_safe_line "$start" || return 1
  case "$pid" in *[!0-9]*) return 1 ;; esac
  case "$host" in claude | codex) ;; *) return 1 ;; esac
  (umask 077; printf '%s\n%s\n%s\n%s\n%s\n' \
    "$sid" "$transcript" "$pid" "$start" "$host" >"$tmp") || {
    rm -f "$tmp"
    return 1
  }
}

ns_session_claim() { # <ns> <sid> <transcript> <pid> <start> <host>; complete file appears atomically
  local ns="$1" tmp rc
  tmp="$ns/.shift-session.tmp.$$.$RANDOM"
  ns_session_write "$ns" "$2" "$3" "$4" "$5" "$6" "$tmp" || return 1
  ln "$tmp" "$ns/.shift-session" 2>/dev/null
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# Replace an existing conversation record. Claim creates; this updates the bound session
# after a revival or interactive reclaim without losing the race to a second first-writer.
ns_session_replace() { # <ns> <sid> <transcript> <pid> <start> <host>
  local ns="$1" tmp
  tmp="$ns/.shift-session.tmp.$$.$RANDOM"
  ns_session_write "$ns" "$2" "$3" "$4" "$5" "$6" "$tmp" || return 1
  mv -f "$tmp" "$ns/.shift-session"
}

# Prefer the recorded host pid when it is still the same process; otherwise walk ancestry.
# Sets NS_CURRENT_PID and NS_CURRENT_START for the caller.
# shellcheck disable=SC2034
ns_host_process() { # <host> <ns> <fallback-pid>
  local rec_pid rec_start live
  NS_CURRENT_PID=""
  NS_CURRENT_START=""
  if [ -f "$2/.shift-session" ]; then
    rec_pid="$(sed -n 3p "$2/.shift-session" 2>/dev/null | tr -d '[:space:]')"
    rec_start="$(sed -n 4p "$2/.shift-session" 2>/dev/null)"
    case "$rec_pid" in
      '' | *[!0-9]*) ;;
      *)
        if [ "$rec_pid" -gt 1 ] && kill -0 "$rec_pid" 2>/dev/null; then
          live="$(ns_process_start "$rec_pid" 2>/dev/null || true)"
          if [ -n "$live" ] && [ "$live" = "$rec_start" ]; then
            NS_CURRENT_PID="$rec_pid"
            NS_CURRENT_START="$rec_start"
            return 0
          fi
        fi
        ;;
    esac
  fi
  NS_CURRENT_PID="$(ns_ancestor_pid "$1" "$3" 2>/dev/null || true)"
  [ -z "$NS_CURRENT_PID" ] || NS_CURRENT_START="$(ns_process_start "$NS_CURRENT_PID" 2>/dev/null || true)"
}

ns_lease_load() { # $1 = the .nightshift dir; one descriptor gives one coherent snapshot
  local f="$1/.shift-lease" _
  NS_LEASE_SID=""
  NS_LEASE_HOST=""
  NS_LEASE_GENERATION=""
  NS_LEASE_TOKEN=""
  NS_LEASE_PID=""
  NS_LEASE_START=""
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  {
    IFS= read -r NS_LEASE_SID &&
      IFS= read -r NS_LEASE_HOST &&
      IFS= read -r NS_LEASE_GENERATION &&
      IFS= read -r NS_LEASE_TOKEN &&
      IFS= read -r NS_LEASE_PID &&
      IFS= read -r NS_LEASE_START || return 1
    if IFS= read -r _; then return 1; fi
  } <"$f"
  ns_lease_safe_line "$NS_LEASE_SID" && ns_lease_safe_line "$NS_LEASE_HOST" \
    && ns_lease_safe_line "$NS_LEASE_GENERATION" && ns_lease_safe_line "$NS_LEASE_TOKEN" \
    && ns_lease_safe_line "$NS_LEASE_PID" && ns_lease_safe_line "$NS_LEASE_START" || return 1
  case "$NS_LEASE_HOST" in claude | codex) ;; *) return 1 ;; esac
  case "$NS_LEASE_GENERATION" in '' | *[!0-9]*) return 1 ;; esac
  [ "$NS_LEASE_GENERATION" -gt 0 ] 2>/dev/null || return 1
  case "$NS_LEASE_TOKEN" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$NS_LEASE_PID" in *[!0-9]*) return 1 ;; esac
  [ -n "$NS_LEASE_PID" ] || [ -z "$NS_LEASE_START" ] || return 1
  [ -n "$NS_LEASE_SID" ] || [ -n "$NS_LEASE_TOKEN" ] || return 1
  return 0
}
ns_lease_valid() { ns_lease_load "$1"; }

ns_lease_write_unlocked() { # <ns> <sid> <host> <generation> <token> <pid> <start>
  local ns="$1" sid="$2" host="$3" generation="$4" token="$5" pid="$6" start="$7" tmp
  ns_lease_safe_line "$sid" && ns_lease_safe_line "$start" || return 1
  case "$host" in claude | codex) ;; *) return 1 ;; esac
  case "$generation" in '' | *[!0-9]*) return 1 ;; esac
  [ "$generation" -gt 0 ] 2>/dev/null || return 1
  case "$token" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$pid" in *[!0-9]*) return 1 ;; esac
  [ -n "$sid" ] || [ -n "$token" ] || return 1
  [ -n "$pid" ] || [ -z "$start" ] || return 1
  tmp="$ns/.shift-lease.tmp.$$.$RANDOM"
  (umask 077; printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$sid" "$host" "$generation" "$token" "$pid" "$start" >"$tmp") || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$ns/.shift-lease" || {
    rm -f "$tmp"
    return 1
  }
}

ns_lease_claim_initial() { # <ns> <sid> <host> <pid> <start>
  local ns="$1" sid="$2" host="$3" pid="$4" start="$5" rc
  [ -n "$sid" ] || return 1
  ns_lease_lock "$ns" || return 2
  if [ -e "$ns/.shift-lease" ] || [ -L "$ns/.shift-lease" ]; then
    ns_lease_valid "$ns"
    rc=$?
    ns_lease_unlock "$ns"
    return "$rc"
  fi
  ns_lease_write_unlocked "$ns" "$sid" "$host" 1 "" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_takeover() { # <ns> <possibly-empty-sid> <host>; prints: generation token
  local ns="$1" sid="$2" host="$3" generation=0 token rc existing_sid
  ns_lease_lock "$ns" || return 2
  if [ -e "$ns/.shift-lease" ] || [ -L "$ns/.shift-lease" ]; then
    if ! ns_lease_valid "$ns"; then
      ns_lease_unlock "$ns"
      return 1
    fi
    existing_sid="$NS_LEASE_SID"
    [ -z "$existing_sid" ] || sid="$existing_sid"
    generation="$NS_LEASE_GENERATION"
  fi
  generation=$((generation + 1))
  token="$host.$generation.$$.$RANDOM.$RANDOM"
  ns_lease_write_unlocked "$ns" "$sid" "$host" "$generation" "$token" "" ""
  rc=$?
  ns_lease_unlock "$ns"
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s %s' "$generation" "$token"
}

ns_lease_token_matches() { # <ns> <host> <token> <generation>; ignores sid for fresh fallback
  local ns="$1" host="$2" token="$3" generation="$4"
  [ -n "$token" ] && [ -n "$generation" ] || return 1
  ns_lease_load "$ns" || return 1
  [ "$NS_LEASE_HOST" = "$host" ] || return 1
  [ "$NS_LEASE_GENERATION" = "$generation" ] || return 1
  [ "$NS_LEASE_TOKEN" = "$token" ]
}

ns_lease_rebind_session() { # <ns> <sid> <host> <token> <generation>; fills an empty scope
  local ns="$1" sid="$2" host="$3" token="$4" generation="$5" scope pid start rc
  [ -n "$sid" ] || return 1
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_token_matches "$ns" "$host" "$token" "$generation"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  scope="$NS_LEASE_SID"
  [ -n "$scope" ] || scope="$sid"
  pid="$NS_LEASE_PID"
  start="$NS_LEASE_START"
  ns_lease_write_unlocked "$ns" "$scope" "$host" "$generation" "$token" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_attach_process() { # <ns> <host> <token> <generation> <pid> <start>
  local ns="$1" host="$2" token="$3" generation="$4" pid="$5" start="$6" sid rc
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_token_matches "$ns" "$host" "$token" "$generation"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  sid="$NS_LEASE_SID"
  ns_lease_write_unlocked "$ns" "$sid" "$host" "$generation" "$token" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_reclaim_interactive() { # <ns> <sid> <host> <old-generation> <pid> <start>
  local ns="$1" sid="$2" host="$3" old_generation="$4" pid="$5" start="$6"
  local lease_sid lease_host generation token old_pid old_start rc
  [ -n "$pid" ] || return 1
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_valid "$ns"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  lease_sid="$NS_LEASE_SID"
  lease_host="$NS_LEASE_HOST"
  generation="$NS_LEASE_GENERATION"
  token="$NS_LEASE_TOKEN"
  old_pid="$NS_LEASE_PID"
  old_start="$NS_LEASE_START"
  if [ "$lease_sid" != "$sid" ] || [ "$lease_host" != "$host" ] \
    || [ "$generation" != "$old_generation" ] || [ -n "$token" ]; then
    ns_lease_unlock "$ns"
    return 1
  fi
  ns_recorded_process "$old_pid" "$old_start"
  rc=$?
  if [ "$rc" -ne 1 ]; then
    ns_lease_unlock "$ns"
    return 1
  fi
  generation=$((generation + 1))
  ns_lease_write_unlocked "$ns" "$sid" "$host" "$generation" "" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_allows() { # <ns> <sid> <host> <pid> <start> <token> <generation>
  local ns="$1" sid="$2" host="$3" pid="$4" start="$5" token="$6" generation="$7"
  local lease_sid lease_host lease_generation lease_token lease_pid lease_start rc
  ns_lease_load "$ns" || return 2
  lease_sid="$NS_LEASE_SID"
  lease_host="$NS_LEASE_HOST"
  lease_generation="$NS_LEASE_GENERATION"
  lease_token="$NS_LEASE_TOKEN"
  lease_pid="$NS_LEASE_PID"
  lease_start="$NS_LEASE_START"
  [ "$lease_host" = "$host" ] || return 1
  if [ -n "$lease_token" ]; then
    [ "$token" = "$lease_token" ] && [ "$generation" = "$lease_generation" ]
    return
  fi
  [ "$lease_sid" = "$sid" ] || return 1
  [ -z "$token" ] && [ -z "$generation" ] || return 1
  [ -n "$lease_pid" ] || return 0 # Codex cannot vouch for an interactive process pid.
  if [ -n "$pid" ] && [ "$pid" = "$lease_pid" ]; then
    ns_recorded_process "$lease_pid" "$lease_start"
    return
  fi
  [ -n "$pid" ] || return 1
  ns_recorded_process "$lease_pid" "$lease_start"
  rc=$?
  [ "$rc" -eq 1 ] || return 1
  ns_lease_reclaim_interactive "$ns" "$sid" "$host" "$lease_generation" "$pid" "$start"
}

ns_lease_release() { # $1 = the .nightshift dir
  local ns="$1" rc
  ns_lease_lock "$ns" || return 1
  rm -f "$ns/.shift-lease"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_release_retry() { # $1 = the .nightshift dir
  ns_lease_release "$1" && return 0
  sleep 0.2
  ns_lease_release "$1"
}

# One ownership protocol for every host hook. Wrappers claim the first session and emit
# the host-specific deny/pass. Unbound runs before that claim; rebind runs after it;
# authorize runs after Start's binding probe so a losing Start cannot pass as a helper.
# Uses NS, SID, TPATH, LEASE_TOKEN, LEASE_GENERATION, NIGHTSHIFT_REVIVAL.
# Sets NS_SHIFT_REC and NS_SHIFT_FAIL.
# Returns 0 = continue as owner, 1 = pass through, 2 = fail closed.
# shellcheck disable=SC2034
ns_shift_unbound() { # <host> <mode:hardhat|gate>
  local host="$1" mode="$2" bound
  : "${LEASE_TOKEN:=}" "${LEASE_GENERATION:=}"
  NS_SHIFT_FAIL=""
  bound="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
  if [ -z "$bound" ] && ns_lease_load "$NS" && [ -n "$NS_LEASE_TOKEN" ]; then
    if [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ] \
      || ! ns_lease_token_matches "$NS" "$host" "$LEASE_TOKEN" "$LEASE_GENERATION"; then
      if [ "$mode" = hardhat ]; then
        NS_SHIFT_FAIL="BLOCKED: this shift is being recovered before its new conversation is bound. Reopen the recorded conversation and retry after recovery."
        return 2
      fi
      return 1
    fi
  fi
  return 0
}

# shellcheck disable=SC2034
ns_shift_rebind() { # <host> <pid> <start> <mode:hardhat|gate>
  local host="$1" pid="$2" start="$3" mode="$4"
  local rec session_pid transcript
  : "${LEASE_TOKEN:=}" "${LEASE_GENERATION:=}"
  NS_SHIFT_REC=""
  NS_SHIFT_FAIL=""

  rec="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
  if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
    if ! ns_lease_token_matches "$NS" "$host" "$LEASE_TOKEN" "$LEASE_GENERATION"; then
      if [ "$mode" = hardhat ]; then
        NS_SHIFT_FAIL="BLOCKED: this recovered worker no longer owns the shift. Reopen the recorded conversation instead of continuing an older process."
        return 2
      fi
      return 1
    fi
    if [ -n "${SID:-}" ]; then
      if [ -z "$NS_LEASE_SID" ]; then
        if ! ns_lease_rebind_session "$NS" "$SID" "$host" "$LEASE_TOKEN" "$LEASE_GENERATION"; then
          if [ "$mode" = hardhat ]; then
            NS_SHIFT_FAIL="BLOCKED: the shift process lease could not bind the recovered conversation. Issue STOP from another session, then run Start again."
            return 2
          fi
          return 1
        fi
      fi
      session_pid="$(sed -n 3p "$NS/.shift-session" 2>/dev/null | tr -d '[:space:]')"
      if [ "$rec" != "$SID" ] || { [ -n "$pid" ] && [ "$session_pid" != "$pid" ]; }; then
        transcript="${TPATH:-$(sed -n 2p "$NS/.shift-session" 2>/dev/null)}"
        if ! ns_session_replace "$NS" "$SID" "$transcript" "$pid" "$start" "$host"; then
          if [ "$mode" = hardhat ]; then
            NS_SHIFT_FAIL="BLOCKED: the recovered conversation could not update .shift-session. Issue STOP from another session, then run Start again."
            return 2
          fi
          return 1
        fi
      fi
      if [ -n "$pid" ]; then
        if ! ns_lease_load "$NS"; then
          if [ "$mode" = hardhat ]; then
            NS_SHIFT_FAIL="BLOCKED: the recovered process lease became unreadable. Issue STOP from another session, then run Start again."
            return 2
          fi
          return 1
        fi
        if [ "$NS_LEASE_PID" != "$pid" ]; then
          if ! ns_lease_attach_process "$NS" "$host" "$LEASE_TOKEN" "$LEASE_GENERATION" "$pid" "$start"; then
            if [ "$mode" = hardhat ]; then
              NS_SHIFT_FAIL="BLOCKED: the recovered process could not refresh its shift lease. Reopen the recorded conversation."
              return 2
            fi
            return 1
          fi
        fi
      fi
      rec="$SID"
    fi
  fi

  NS_SHIFT_REC="$rec"
  return 0
}

# shellcheck disable=SC2034
ns_shift_authorize() { # <host> <pid> <start> <mode:hardhat|gate>
  local host="$1" pid="$2" start="$3" mode="$4"
  local rec session_pid lease_scope check_sid lease_rc transcript
  : "${LEASE_TOKEN:=}" "${LEASE_GENERATION:=}"
  NS_SHIFT_FAIL=""
  rec="${NS_SHIFT_REC:-$(sed -n 1p "$NS/.shift-session" 2>/dev/null)}"

  lease_scope=""
  if ns_lease_valid "$NS"; then lease_scope="$NS_LEASE_SID"; fi
  if [ -n "$rec" ] && [ -n "${SID:-}" ] && [ "$SID" != "$rec" ] \
    && [ "$SID" != "$lease_scope" ] && [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ]; then
    return 1
  fi

  if [ -z "$rec" ]; then
    return 0
  fi

  check_sid="${SID:-$rec}"
  if [ ! -e "$NS/.shift-lease" ] && [ ! -L "$NS/.shift-lease" ]; then
    if ! ns_lease_claim_initial "$NS" "$rec" "$host" "$pid" "$start"; then
      if [ "$mode" = hardhat ]; then
        NS_SHIFT_FAIL="BLOCKED: the shift process lease could not be created. Issue STOP from another session, then run Start again."
      else
        NS_SHIFT_FAIL="DO NOT STOP — the shift process lease is unreadable. Issue STOP from another session, then run Start again."
      fi
      return 2
    fi
  fi

  ns_lease_allows "$NS" "$check_sid" "$host" "$pid" "$start" \
    "$LEASE_TOKEN" "$LEASE_GENERATION"
  lease_rc=$?
  if [ "$lease_rc" -eq 1 ]; then
    if [ "$mode" = hardhat ]; then
      NS_SHIFT_FAIL="BLOCKED: this shift continued in a recovered process. Reopen the recorded conversation before using tools here."
      return 2
    fi
    return 1
  fi
  if [ "$lease_rc" -ne 0 ]; then
    if [ "$mode" = hardhat ]; then
      NS_SHIFT_FAIL="BLOCKED: this shift continued in a recovered process. Reopen the recorded conversation before using tools here."
    else
      NS_SHIFT_FAIL="DO NOT STOP — the shift process lease is unreadable. Issue STOP from another session, then run Start again."
    fi
    return 2
  fi

  if [ -n "${SID:-}" ] && [ -n "$pid" ] && [ -z "$LEASE_TOKEN" ]; then
    if ! ns_lease_load "$NS"; then
      if [ "$mode" = hardhat ]; then
        NS_SHIFT_FAIL="BLOCKED: the shift process lease became unreadable. Issue STOP from another session, then run Start again."
      else
        NS_SHIFT_FAIL="DO NOT STOP — the shift process lease became unreadable. Issue STOP from another session, then run Start again."
      fi
      return 2
    fi
    session_pid="$(sed -n 3p "$NS/.shift-session" 2>/dev/null | tr -d '[:space:]')"
    if [ "$NS_LEASE_PID" = "$pid" ] && [ "$session_pid" != "$pid" ]; then
      transcript="${TPATH:-$(sed -n 2p "$NS/.shift-session" 2>/dev/null)}"
      if ! ns_session_replace "$NS" "$SID" "$transcript" "$pid" "$start" "$host"; then
        if [ "$mode" = hardhat ]; then
          NS_SHIFT_FAIL="BLOCKED: the reclaimed interactive process could not refresh .shift-session. Issue STOP from another session, then run Start again."
        else
          NS_SHIFT_FAIL="DO NOT STOP — the reclaimed process could not refresh .shift-session. Issue STOP from another session, then run Start again."
        fi
        return 2
      fi
    fi
  fi

  NS_SHIFT_REC="$rec"
  return 0
}

# Gate wrappers have no Start probe between rebind and authorize.
ns_shift_ownership() { # <host> <pid> <start> <mode:hardhat|gate>
  ns_shift_rebind "$1" "$2" "$3" "$4" || return "$?"
  ns_shift_authorize "$1" "$2" "$3" "$4"
}

# Fence a recovery child: take the lease, export the capability, attach the pid, wait.
# Remaining arguments are the command line. Returns 3 when takeover fails.
ns_watchman_run_child() { # <ns> <host> <sid> <work_target> <project_env> <project> <cmd...>
  local ns="$1" host="$2" sid="$3" work="$4" env_name="$5" project="$6"
  local lease generation token child start rc
  shift 6
  lease="$(ns_lease_takeover "$ns" "$sid" "$host")" || return 3
  generation="${lease%% *}"
  token="${lease#* }"
  (
    cd "$work" || exit 1
    env "${env_name}=${project}" \
      NIGHTSHIFT_REVIVAL=1 \
      NIGHTSHIFT_LEASE_GENERATION="$generation" \
      NIGHTSHIFT_LEASE_TOKEN="$token" \
      "$@" >/dev/null 2>&1
  ) &
  child=$!
  start="$(ns_process_start "$child" 2>/dev/null || true)"
  ns_lease_attach_process "$ns" "$host" "$token" "$generation" "$child" "$start" || true
  wait "$child"
  rc=$?
  return "$rc"
}

# After a clock-out spawn: 0 = the shift ended, 1 = still open (sentinel refreshed),
# 2 = still open and the wake cap is reached (caller exits 7 after logging).
ns_watchman_clockout_pending() { # <ns> <sentinel> <max_wakes> <wake>
  if [ -f "$1/.ended" ]; then
    return 0
  fi
  : >"$2" 2>/dev/null || true
  if [ "$3" -gt 0 ] && [ "$4" -ge "$3" ]; then
    return 2
  fi
  return 1
}

ns_lease_reset_stale() { # $1 = .nightshift; caller has proved no process or watchman owns it
  local ns="$1" rc
  rm -rf "$ns/.lease-lock.d" 2>/dev/null
  ns_lease_lock "$ns" || return 1
  rm -f "$ns/.shift-lease" "$ns"/.shift-lease.tmp.*
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

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

# Watchman reason codes — one token, no transcript. Written to .nightshift/.watch-reason
# (line 1 = code, line 2 = optional non-sensitive detail). Status and Doctor render the same
# labels. Adding a code here is the contract; callers must not invent ad-hoc strings.
ns_reason_label() {
  case "$1" in
    completed) printf 'shift completed' ;;
    owner-stop) printf 'owner stop-work order' ;;
    stale-pid) printf 'recorded process is stale' ;;
    invalid-session) printf 'session identity is missing or unreadable' ;;
    exhausted-retry) printf 'revival retries exhausted this wake' ;;
    unknown-wedge) printf 'session looks wedged without a verified error signature' ;;
    revived) printf 'session revived into its own conversation' ;;
    stand-down) printf 'watchman stood down' ;;
    wrong-host) printf 'watchman stood down — shift belongs to another host' ;;
    deadline) printf 'quitting time passed' ;;
    clean-session-end) printf 'owner closed the session' ;;
    esc-standby) printf 'standing by — owner interrupt in the transcript' ;;
    silent-standby) printf 'standing by — session alive and quiet' ;;
    non-resumable-session) printf 'recorded Codex identity cannot be resumed' ;;
    unreadable-rules) printf 'rules file missing or incomplete' ;;
    fresh-fallback) printf 'fresh session — punch list is the handover' ;;
    unsupported-state) printf 'workspace state-version is unsupported' ;;
    process-evidence-unavailable) printf 'process evidence is unavailable' ;;
    *) printf 'unknown watchman outcome' ;;
  esac
}

ns_record_reason() { # <nightshift-dir> <code> [detail]
  local dir="$1" code="$2" detail="${3:-}"
  [ -d "$dir" ] || return 1
  case "$code" in
    completed|owner-stop|stale-pid|invalid-session|exhausted-retry|unknown-wedge|revived|stand-down|wrong-host|deadline|clean-session-end|esc-standby|silent-standby|non-resumable-session|unreadable-rules|fresh-fallback|unsupported-state|process-evidence-unavailable) ;;
    *) code="stand-down" ;;
  esac
  detail="$(printf '%s' "$detail" | tr -d '\000-\037' | sed 's/[[:space:]]*$//')"
  printf '%s\n%s\n' "$code" "$detail" >"$dir/.watch-reason"
}

ns_reason_code() { sed -n 1p "$1/.watch-reason" 2>/dev/null | tr -d '[:space:]'; }
ns_reason_detail() { sed -n 2p "$1/.watch-reason" 2>/dev/null; }

# Codex `exec resume` accepts a session/thread id, not a rollout path or ChatGPT scratch handle.
# Fail closed on anything that is not a known resumable shape so recovery never claims it
# resumed a thread it did not.
# Prints: missing | resumable | malformed | unsupported
# Return 0 only for resumable.
ns_codex_identity_kind() {
  local id="$1"
  if [ -z "$id" ]; then
    printf 'missing'
    return 1
  fi
  if printf '%s' "$id" | grep -qE '[[:space:]/\\\$`;|&<>*]'; then
    printf 'malformed'
    return 1
  fi
  case "$id" in
    thread_*|conv_*|chatgpt-*|rollout-*|task_*|scratch_*|local|unknown)
      printf 'unsupported'
      return 1
      ;;
  esac
  if printf '%s' "$id" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
    printf 'resumable'
    return 0
  fi
  if printf '%s' "$id" | grep -Eq '^[0-9a-fA-F]{32,}$'; then
    printf 'resumable'
    return 0
  fi
  printf 'unsupported'
  return 1
}

# Workspace schema. One integer in .nightshift/state-version is the authority. This plugin
# supports version 1. A missing marker is legacy version 0 — existing files stay compatible,
# and only an explicit setup/Doctor repair writes the marker. Newer integers fail closed.
# Never rewrite or downgrade a future marker; never migrate from hooks, start, status,
# archive, or recovery.
NS_STATE_VERSION=1

# ns_state_kind <workspace>
# Prints: absent | legacy | current | malformed | future
# Return: 0 operable (legacy or current) · 1 malformed · 2 future · 3 absent
ns_state_kind() {
  local ws="$1" ns marker raw lines
  ns="$ws/.nightshift"
  if [ ! -d "$ns" ]; then
    printf 'absent'
    return 3
  fi
  marker="$ns/state-version"
  if [ ! -e "$marker" ] && [ ! -L "$marker" ]; then
    printf 'legacy'
    return 0
  fi
  if [ -L "$marker" ] || [ ! -f "$marker" ]; then
    printf 'malformed'
    return 1
  fi
  IFS= read -r raw <"$marker" || true
  raw="$(printf '%s' "$raw" | tr -d '\r')"
  lines="$(awk 'END { print NR + 0 }' "$marker" 2>/dev/null)"
  case "$raw" in
    '' | *[!0-9]*)
      printf 'malformed'
      return 1
      ;;
    0) ;;
    0*)
      printf 'malformed'
      return 1
      ;;
  esac
  if [ "${#raw}" -gt 8 ] || [ "$lines" -gt 1 ]; then
    printf 'malformed'
    return 1
  fi
  if [ "$raw" -gt "$NS_STATE_VERSION" ]; then
    printf 'future'
    return 2
  fi
  if [ "$raw" -eq "$NS_STATE_VERSION" ]; then
    printf 'current'
    return 0
  fi
  printf 'legacy'
  return 0
}

# ns_state_version <workspace>
# Prints the integer when it can be read (0 if the marker is missing). Empty on
# absent or malformed. Return matches ns_state_kind.
ns_state_version() {
  local ws="$1" kind raw
  kind="$(ns_state_kind "$ws")"
  case "$kind" in
    absent)
      return 3
      ;;
    legacy)
      printf '0'
      return 0
      ;;
    current)
      printf '%s' "$NS_STATE_VERSION"
      return 0
      ;;
    future)
      IFS= read -r raw <"$ws/.nightshift/state-version" || true
      raw="$(printf '%s' "$raw" | tr -d '\r')"
      printf '%s' "$raw"
      return 2
      ;;
    *)
      return 1
      ;;
  esac
}

# ns_state_refuse_message <kind> — hook and skill diagnostic; no paths, no guesses.
ns_state_refuse_message() {
  case "$1" in
    future)
      printf 'Nightshift state-version is newer than this plugin supports (supported: %s). Upgrade Nightshift; never rewrite or downgrade the marker.' "$NS_STATE_VERSION"
      ;;
    malformed)
      printf 'Nightshift state-version is malformed. Inspect it only while unarmed; never guess a version.'
      ;;
    *)
      printf 'Nightshift state-version is unsupported.'
      ;;
  esac
}

# ns_write_state_version <workspace> <integer>
# Atomic replace of the marker. Refuses a symlink destination. Touches no other file.
ns_write_state_version() {
  local ws="$1" n="$2" ns marker tmp
  ns="$ws/.nightshift"
  marker="$ns/state-version"
  case "$n" in
    '' | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ -d "$ns" ] || return 1
  if [ -L "$marker" ]; then
    return 1
  fi
  tmp="$ns/.state-version.$$"
  printf '%s\n' "$n" >"$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}

# ns_migrate_state <workspace>
# Legacy 0 → 1: write only the marker. Idempotent when already current.
# Return: 0 migrated or already current · 1 armed · 2 unsupported · 3 write failed
# Callers: setup and an explicit Doctor repair only. Never hooks, start, status, archive, recovery.
ns_migrate_state() {
  local ws="$1" kind
  kind="$(ns_state_kind "$ws")"
  case "$kind" in
    current)
      return 0
      ;;
    legacy)
      if [ -f "$ws/.nightshift/.shift-armed" ]; then
        return 1
      fi
      ns_write_state_version "$ws" "$NS_STATE_VERSION" || return 3
      return 0
      ;;
    *)
      return 2
      ;;
  esac
}

# Retention — archive-only, preview-first. 0 means keep forever. Unreadable rules
# also mean 0: a broken file must never become a delete. Hooks, start, status,
# Doctor, and recovery must not call these apply helpers.
ns_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null ;;
    *) stat -c %Y "$1" 2>/dev/null ;;
  esac
}

ns_age_days() {
  local m now
  m="$(ns_mtime "$1")" || return 1
  case "$m" in '' | *[!0-9]*) return 1 ;; esac
  now="$(date +%s)"
  printf '%s' "$(((now - m) / 86400))"
}

# ns_retention_days <workspace> <runtimeLogDays|archiveDays>
# Prints a non-negative integer. Missing, nested, or unreadable → 0.
ns_retention_days() {
  local ws="$1" key="$2" f="$1/.nightshift/rules.json" raw=""
  case "$key" in
    runtimeLogDays)
      [ -z "${NIGHTSHIFT_RETENTION_RUNTIME_LOG_DAYS:-}" ] || { printf '%s' "$NIGHTSHIFT_RETENTION_RUNTIME_LOG_DAYS"; return 0; }
      ;;
    archiveDays)
      [ -z "${NIGHTSHIFT_RETENTION_ARCHIVE_DAYS:-}" ] || { printf '%s' "$NIGHTSHIFT_RETENTION_ARCHIVE_DAYS"; return 0; }
      ;;
    *)
      printf '0'
      return 0
      ;;
  esac
  if [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" '.retention[$k] // 0' "$f" 2>/dev/null)" || raw=0
  elif [ -f "$f" ]; then
    raw="$(sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | sed -n 1p)"
  fi
  case "$raw" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%s' "$raw" ;;
  esac
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

# True when a dated archive still holds open punch-list work or an armed marker.
ns_archive_has_open_work() {
  local dir="$1" f
  [ -d "$dir" ] || return 1
  [ ! -e "$dir/.shift-armed" ] || return 0
  [ ! -L "$dir/.shift-armed" ] || return 0
  for f in "$dir"/*; do
    if [ ! -f "$f" ] || [ -L "$f" ]; then
      continue
    fi
    case "${f##*/}" in
      punch-list.md | shipped.md)
        [ "$(ns_open_boxes "$f")" -eq 0 ] || return 0
        ;;
    esac
  done
  return 1
}

# ns_retention_eligible <workspace>
# Print "kind<TAB>rel<TAB>age<TAB>days" for allowlisted, old-enough, unprotected targets.
ns_retention_eligible() {
  local ws="$1" ns log_days arch_days age path rel
  ns="$ws/.nightshift"
  [ -d "$ns" ] || return 0
  log_days="$(ns_retention_days "$ws" runtimeLogDays)"
  arch_days="$(ns_retention_days "$ws" archiveDays)"

  if [ "$log_days" -gt 0 ] && [ -e "$ns/scheduled.log" ]; then
    path="$(ns_under_nightshift "$ws" scheduled.log)" && {
      age="$(ns_age_days "$path")" || age=""
      if [ -n "$age" ] && [ "$age" -ge "$log_days" ]; then
        printf '%s\t%s\t%s\t%s\n' runtime-log scheduled.log "$age" "$log_days"
      fi
    }
  fi

  [ "$arch_days" -gt 0 ] || return 0
  [ -d "$ns/archive" ] && [ ! -L "$ns/archive" ] || return 0
  for rel in "$ns/archive"/*; do
    [ -e "$rel" ] || continue
    rel="${rel#"$ns/"}"
    case "$rel" in
      archive/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      archive/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) rel="${rel%/}" ;;
      *) continue ;;
    esac
    [ -d "$ns/$rel" ] || continue
    path="$(ns_under_nightshift "$ws" "$rel")" || continue
    ns_archive_has_open_work "$path" && continue
    age="$(ns_age_days "$path")" || continue
    [ "$age" -ge "$arch_days" ] || continue
    printf '%s\t%s\t%s\t%s\n' archive "$rel" "$age" "$arch_days"
  done
}

# ns_retention_apply <workspace> — delete currently eligible allowlisted targets.
# Return: 0 deleted or nothing eligible · 1 armed · 2 refused/failed
ns_retention_apply() {
  local ws="$1" ns kind rel path
  ns="$ws/.nightshift"
  [ -d "$ns" ] || return 2
  if [ -f "$ns/.shift-armed" ]; then
    return 1
  fi
  while IFS="$(printf '\t')" read -r kind rel _ _; do
    [ -n "$rel" ] || continue
    path="$(ns_under_nightshift "$ws" "$rel")" || return 2
    case "$kind" in
      runtime-log)
        [ -f "$path" ] && [ ! -L "$path" ] || return 2
        rm -f "$path" || return 2
        ;;
      archive)
        [ -d "$path" ] && [ ! -L "$path" ] || return 2
        ns_archive_has_open_work "$path" && return 2
        rm -rf "$path" || return 2
        ;;
      *)
        return 2
        ;;
    esac
  done <<EOF
$(ns_retention_eligible "$ws")
EOF
}

# Process evidence. kill -0 is the POSIX primary. ps, pgrep, and lsof are
# optional enhancers: missing tools never mean the session is dead.
ns_have_cmd() { command -v "$1" >/dev/null 2>&1; }

ns_ancestor_pid() { # <executable-name> [starting-pid]
  local wanted="$1" p="${2:-$$}" _ comm
  ns_have_cmd ps || return 1
  for _ in 1 2 3 4 5 6; do
    case "$p" in '' | *[!0-9]*) return 1 ;; esac
    [ "$p" -gt 1 ] || return 1
    comm="$(ps -o comm= -p "$p" 2>/dev/null)" || return 1
    case "${comm##*/}" in "$wanted") printf '%s' "$p"; return 0 ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')"
  done
  return 1
}

ns_process_start() { # <pid>
  local start
  case "$1" in '' | *[!0-9]*) return 1 ;; esac
  ns_have_cmd ps || return 1
  start="$(ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$start" ] || return 1
  printf '%s' "$start"
}

# ns_pid_alive <pid>
# 0 alive · 1 dead · 2 malformed · 3 evidence unavailable (EPERM or unknown)
ns_pid_alive() {
  local pid="$1" err
  case "$pid" in
    '' | *[!0-9]*) return 2 ;;
  esac
  err="$(kill -0 "$pid" 2>&1)" && return 0
  case "$err" in
    *[Nn]'o such process'*) return 1 ;;
  esac
  return 3
}

# ns_recorded_process <pid> <optional-start>
# Start-time check runs only when ps is available. Missing ps does not kill the pid.
ns_recorded_process() {
  local pid="$1" start="${2:-}" now rc
  ns_pid_alive "$pid"
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  [ -n "$start" ] || return 0
  ns_have_cmd ps || return 0
  now="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$now" ] || return 0
  [ "$now" = "$start" ] || return 1
  return 0
}

# ns_proc_cwd <pid> — /proc first, then lsof. Return 1 when neither can answer.
ns_proc_cwd() {
  local pid="$1" cwd
  case "$pid" in
    '' | *[!0-9]*) return 1 ;;
  esac
  if [ -r "/proc/$pid/cwd" ]; then
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || return 1
    printf '%s' "$cwd"
    return 0
  fi
  ns_have_cmd lsof || return 1
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sed -n 1p)"
  [ -n "$cwd" ] || return 1
  printf '%s' "$cwd"
}

# Support-bundle redaction. If a line still looks secret or contains an
# unresolved absolute path, omit it — never guess.
ns_secret_line() {
  printf '%s' "$1" | grep -qiE \
    '(password|passwd|secret|token|api[_-]?key|authorization|bearer|credential)[[:space:]]*[=:]' && return 0
  printf '%s' "$1" | grep -qE '://[^/@[:space:]]+:[^/@[:space:]]+@' && return 0
  printf '%s' "$1" | grep -qiE '[?&](token|key|secret|password|auth|access_token)=' && return 0
  return 1
}

ns_sed_escape() {
  printf '%s' "$1" | sed 's/[][\\.*^$]/\\&/g'
}

# ns_tokenize_text <text> <home> <workspace> <work-target>
# Longest prefix wins. Remaining absolute paths make the function return 1 (omit).
ns_tokenize_text() {
  local text="$1" home="$2" workspace="$3" target="$4" out
  out="$text"
  if [ -n "$target" ]; then
    out="$(printf '%s' "$out" | sed "s#$(ns_sed_escape "$target")#\$WORK_TARGET#g")"
  fi
  if [ -n "$workspace" ]; then
    out="$(printf '%s' "$out" | sed "s#$(ns_sed_escape "$workspace")#\$WORKSPACE#g")"
  fi
  if [ -n "$home" ]; then
    out="$(printf '%s' "$out" | sed "s#$(ns_sed_escape "$home")#\$HOME#g")"
  fi
  if printf '%s' "$out" | grep -qE '(^|[[:space:]=])(/|file://)'; then
    return 1
  fi
  printf '%s' "$out"
}

# ns_sanitize_line <text> <home> <workspace> <work-target>
# Prints the tokenized line, or returns 1 to omit.
ns_sanitize_line() {
  local text="$1"
  ns_secret_line "$text" && return 1
  ns_tokenize_text "$text" "$2" "$3" "$4"
}
