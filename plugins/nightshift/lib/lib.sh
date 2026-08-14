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
    *) printf 'unknown watchman outcome' ;;
  esac
}

ns_record_reason() { # <nightshift-dir> <code> [detail]
  local dir="$1" code="$2" detail="${3:-}"
  [ -d "$dir" ] || return 1
  case "$code" in
    completed|owner-stop|stale-pid|invalid-session|exhausted-retry|unknown-wedge|revived|stand-down|wrong-host|deadline|clean-session-end|esc-standby|silent-standby|non-resumable-session|unreadable-rules|fresh-fallback|unsupported-state) ;;
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
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
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
    [ -f "$f" ] && [ ! -L "$f" ] || continue
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
