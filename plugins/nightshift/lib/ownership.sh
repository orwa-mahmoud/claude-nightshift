#!/usr/bin/env bash
# Session, lease, and shift-ownership fencing shared by Nightshift hooks.

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
#   original session scope · host · generation · revival nonce · process pid · process start time
# The nonce is empty for the original interactive process. A watchman writes a new nonce and
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
  case "$host" in claude | codex | cursor) ;; *) return 1 ;; esac
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
  NS_LEASE_NONCE=""
  NS_LEASE_PID=""
  NS_LEASE_START=""
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  {
    IFS= read -r NS_LEASE_SID &&
      IFS= read -r NS_LEASE_HOST &&
      IFS= read -r NS_LEASE_GENERATION &&
      IFS= read -r NS_LEASE_NONCE &&
      IFS= read -r NS_LEASE_PID &&
      IFS= read -r NS_LEASE_START || return 1
    if IFS= read -r _; then return 1; fi
  } <"$f"
  ns_lease_safe_line "$NS_LEASE_SID" && ns_lease_safe_line "$NS_LEASE_HOST" \
    && ns_lease_safe_line "$NS_LEASE_GENERATION" && ns_lease_safe_line "$NS_LEASE_NONCE" \
    && ns_lease_safe_line "$NS_LEASE_PID" && ns_lease_safe_line "$NS_LEASE_START" || return 1
  case "$NS_LEASE_HOST" in claude | codex) ;; *) return 1 ;; esac
  case "$NS_LEASE_GENERATION" in '' | *[!0-9]*) return 1 ;; esac
  [ "$NS_LEASE_GENERATION" -gt 0 ] 2>/dev/null || return 1
  case "$NS_LEASE_NONCE" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$NS_LEASE_PID" in *[!0-9]*) return 1 ;; esac
  [ -n "$NS_LEASE_PID" ] || [ -z "$NS_LEASE_START" ] || return 1
  [ -n "$NS_LEASE_SID" ] || [ -n "$NS_LEASE_NONCE" ] || return 1
  return 0
}
ns_lease_valid() { ns_lease_load "$1"; }

ns_lease_write_unlocked() { # <ns> <sid> <host> <generation> <nonce> <pid> <start>
  local ns="$1" sid="$2" host="$3" generation="$4" nonce="$5" pid="$6" start="$7" tmp
  ns_lease_safe_line "$sid" && ns_lease_safe_line "$start" || return 1
  case "$host" in claude | codex | cursor) ;; *) return 1 ;; esac
  case "$generation" in '' | *[!0-9]*) return 1 ;; esac
  [ "$generation" -gt 0 ] 2>/dev/null || return 1
  case "$nonce" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$pid" in *[!0-9]*) return 1 ;; esac
  [ -n "$sid" ] || [ -n "$nonce" ] || return 1
  [ -n "$pid" ] || [ -z "$start" ] || return 1
  tmp="$ns/.shift-lease.tmp.$$.$RANDOM"
  (umask 077; printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$sid" "$host" "$generation" "$nonce" "$pid" "$start" >"$tmp") || {
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

ns_lease_takeover() { # <ns> <possibly-empty-sid> <host>; prints: generation nonce
  local ns="$1" sid="$2" host="$3" generation=0 nonce rc existing_sid
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
  nonce="$host.$generation.$$.$RANDOM.$RANDOM"
  ns_lease_write_unlocked "$ns" "$sid" "$host" "$generation" "$nonce" "" ""
  rc=$?
  ns_lease_unlock "$ns"
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s %s' "$generation" "$nonce"
}

ns_lease_nonce_matches() { # <ns> <host> <nonce> <generation>; ignores sid for fresh fallback
  local ns="$1" host="$2" nonce="$3" generation="$4"
  [ -n "$nonce" ] && [ -n "$generation" ] || return 1
  ns_lease_load "$ns" || return 1
  [ "$NS_LEASE_HOST" = "$host" ] || return 1
  [ "$NS_LEASE_GENERATION" = "$generation" ] || return 1
  [ "$NS_LEASE_NONCE" = "$nonce" ]
}

ns_lease_rebind_session() { # <ns> <sid> <host> <nonce> <generation>; fills an empty scope
  local ns="$1" sid="$2" host="$3" nonce="$4" generation="$5" scope pid start rc
  [ -n "$sid" ] || return 1
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_nonce_matches "$ns" "$host" "$nonce" "$generation"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  scope="$NS_LEASE_SID"
  [ -n "$scope" ] || scope="$sid"
  pid="$NS_LEASE_PID"
  start="$NS_LEASE_START"
  ns_lease_write_unlocked "$ns" "$scope" "$host" "$generation" "$nonce" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_attach_process() { # <ns> <host> <nonce> <generation> <pid> <start>
  local ns="$1" host="$2" nonce="$3" generation="$4" pid="$5" start="$6" sid rc
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_nonce_matches "$ns" "$host" "$nonce" "$generation"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  sid="$NS_LEASE_SID"
  ns_lease_write_unlocked "$ns" "$sid" "$host" "$generation" "$nonce" "$pid" "$start"
  rc=$?
  ns_lease_unlock "$ns"
  return "$rc"
}

ns_lease_reclaim_interactive() { # <ns> <sid> <host> <old-generation> <pid> <start>
  local ns="$1" sid="$2" host="$3" old_generation="$4" pid="$5" start="$6"
  local lease_sid lease_host generation nonce old_pid old_start rc
  [ -n "$pid" ] || return 1
  ns_lease_lock "$ns" || return 2
  if ! ns_lease_valid "$ns"; then
    ns_lease_unlock "$ns"
    return 1
  fi
  lease_sid="$NS_LEASE_SID"
  lease_host="$NS_LEASE_HOST"
  generation="$NS_LEASE_GENERATION"
  nonce="$NS_LEASE_NONCE"
  old_pid="$NS_LEASE_PID"
  old_start="$NS_LEASE_START"
  if [ "$lease_sid" != "$sid" ] || [ "$lease_host" != "$host" ] \
    || [ "$generation" != "$old_generation" ] || [ -n "$nonce" ]; then
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

ns_lease_allows() { # <ns> <sid> <host> <pid> <start> <nonce> <generation>
  local ns="$1" sid="$2" host="$3" pid="$4" start="$5" nonce="$6" generation="$7"
  local lease_sid lease_host lease_generation lease_nonce lease_pid lease_start rc
  ns_lease_load "$ns" || return 2
  lease_sid="$NS_LEASE_SID"
  lease_host="$NS_LEASE_HOST"
  lease_generation="$NS_LEASE_GENERATION"
  lease_nonce="$NS_LEASE_NONCE"
  lease_pid="$NS_LEASE_PID"
  lease_start="$NS_LEASE_START"
  [ "$lease_host" = "$host" ] || return 1
  if [ -n "$lease_nonce" ]; then
    [ "$nonce" = "$lease_nonce" ] && [ "$generation" = "$lease_generation" ]
    return
  fi
  [ "$lease_sid" = "$sid" ] || return 1
  [ -z "$nonce" ] && [ -z "$generation" ] || return 1
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
# Uses NS, SID, TPATH, LEASE_NONCE, LEASE_GENERATION, NIGHTSHIFT_REVIVAL.
# Sets NS_SHIFT_REC and NS_SHIFT_FAIL.
# Returns 0 = continue as owner, 1 = pass through, 2 = fail closed.
# shellcheck disable=SC2034
ns_shift_unbound() { # <host> <mode:hardhat|gate>
  local host="$1" mode="$2" bound
  : "${LEASE_NONCE:=}" "${LEASE_GENERATION:=}"
  NS_SHIFT_FAIL=""
  bound="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
  if [ -z "$bound" ] && ns_lease_load "$NS" && [ -n "$NS_LEASE_NONCE" ]; then
    if [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ] \
      || ! ns_lease_nonce_matches "$NS" "$host" "$LEASE_NONCE" "$LEASE_GENERATION"; then
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
  : "${LEASE_NONCE:=}" "${LEASE_GENERATION:=}"
  NS_SHIFT_REC=""
  NS_SHIFT_FAIL=""

  rec="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
  if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
    if ! ns_lease_nonce_matches "$NS" "$host" "$LEASE_NONCE" "$LEASE_GENERATION"; then
      if [ "$mode" = hardhat ]; then
        NS_SHIFT_FAIL="BLOCKED: this recovered worker no longer owns the shift. Reopen the recorded conversation instead of continuing an older process."
        return 2
      fi
      return 1
    fi
    if [ -n "${SID:-}" ]; then
      if [ -z "$NS_LEASE_SID" ]; then
        if ! ns_lease_rebind_session "$NS" "$SID" "$host" "$LEASE_NONCE" "$LEASE_GENERATION"; then
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
          if ! ns_lease_attach_process "$NS" "$host" "$LEASE_NONCE" "$LEASE_GENERATION" "$pid" "$start"; then
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
  : "${LEASE_NONCE:=}" "${LEASE_GENERATION:=}"
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
    "$LEASE_NONCE" "$LEASE_GENERATION"
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

  if [ -n "${SID:-}" ] && [ -n "$pid" ] && [ -z "$LEASE_NONCE" ]; then
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
  local lease generation nonce child start rc
  shift 6
  lease="$(ns_lease_takeover "$ns" "$sid" "$host")" || return 3
  generation="${lease%% *}"
  nonce="${lease#* }"
  (
    cd "$work" || exit 1
    env "${env_name}=${project}" \
      NIGHTSHIFT_REVIVAL=1 \
      NIGHTSHIFT_LEASE_GENERATION="$generation" \
      NIGHTSHIFT_LEASE_NONCE="$nonce" \
      "$@" >/dev/null 2>&1
  ) &
  child=$!
  start="$(ns_process_start "$child" 2>/dev/null || true)"
  ns_lease_attach_process "$ns" "$host" "$nonce" "$generation" "$child" "$start" || true
  wait "$child"
  rc=$?
  return "$rc"
}

# After a clock-out spawn: 0 = the shift ended, 1 = still open (sentinel refreshed),
# 2 = still open and the wake cap is reached (caller exits 7 after logging).
ns_watchman_clockout_pending() { # <ns> <sentinel> <max_wakes> <wake>
  if [ -f "$1/.ended" ] && [ ! -L "$1/.ended" ]; then
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

# Every tool that speaks Claude Code's plugin interface executes these same hooks, so a hook
# cannot assume Claude is the host it runs in. The transcript path names the writer: Cursor
# keeps its conversations under ~/.cursor, and a record claimed from one belongs to Cursor —
# Claude's watchman must stand down from it rather than fire `claude --resume` at a
# conversation it can never reach. Paths without a known foreign marker stay claude.
ns_claude_session_host() { # <transcript-path>
  case "$1" in
    */.cursor/*) printf 'cursor' ;;
    *) printf 'claude' ;;
  esac
}

# Which host owns this shift. Absent means a record written before hosts were distinguished,
# and every such record is Claude's — nothing else could have written one.
ns_session_host() {
  local rec="$1/.shift-session" h
  if [ -L "$rec" ]; then
    printf 'claude'
    return
  fi
  h="$(sed -n 5p "$rec" 2>/dev/null | tr -d '[:space:]')"
  printf '%s' "${h:-claude}"
}

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
