#!/usr/bin/env bash
# Process evidence helpers shared by Nightshift hooks and recovery.

# Process evidence. kill -0 is the POSIX primary. ps, pgrep, and lsof are
# optional enhancers: missing tools never mean the session is dead.

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
