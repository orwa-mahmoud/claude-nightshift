#!/usr/bin/env bash
# clock-out-gate.sh — Stop hook.
#
# The punch list is the only truth. Release order on every stop attempt:
#   1. stop-work order — .nightshift/STOP exists              -> release (open boxes stay open)
#   2. done            — zero open "- [ ]" (or no punch list) -> release
#   3. quitting time   — now past .nightshift/deadline        -> write STOP, log, release
#   4. otherwise       — block, re-injecting the contract
#
# Stall guard: consecutive stop attempts with no progress are counted (progress = a tick or a
# commit). By default a stalled shift is HELD — every 3 stuck attempts a stall warning lands
# in the shift log and the gate keeps blocking; only STOP, done, or the deadline release.
# Owner opt-in: stallMax N in the rules file auto-ends the shift (write STOP, log, release)
# after N stuck attempts — the file is guarded during a shift, so only a human chooses that.
#
# Quitting time and the stall opt-in are a whistle, not an axe: a Stop hook can only run at
# a stop attempt, so neither can ever interrupt work mid-item.
#
# Morning whistle: if the rules file sets notifyCommand, any shift-ending release fires it
# exactly once with a one-line summary (both $NIGHTSHIFT_SUMMARY and $1). Empty -> silent.
#
# Receipts: any shift-ending release also snapshots .nightshift/ into its local receipts repo
# (the one /nightshift:setup created). No receipts repo -> no-op; a failed commit never blocks
# the release.
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugin/hooks/lib.sh
. "$_here/lib.sh" # pure-bash path: no dirname, so a hostile PATH cannot unsource the helpers

# The Stop payload carries the session's identity; a tty guard keeps manual runs from hanging.
if [ -t 0 ]; then INPUT=""; else INPUT="$(cat)"; fi
if command -v jq >/dev/null 2>&1; then
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  TPATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
else
  SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  TPATH="$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"
DEADLINE="$NS/deadline"
STALL="$NS/.stall"
NOTIFIED="$NS/.notified"
ENDED="$NS/.ended" # written when the shift actually ends; hardhat keeps the site rules armed until then
LOG="$NS/shift-log.md"
# One copy: the rules file is the config; env vars are session-start overrides only. The
# shipped values live visibly in the file setup copies — no fallbacks hide here. A gate whose
# knobs are unreadable still gates (fail closed): the stall bookkeeping stands down loudly and
# the block carries the repair.
STALL_MAX="$(rule "$PROJECT_DIR" stallMax "${NIGHTSHIFT_STALL_MAX:-}")"
STALL_WARN="$(rule "$PROJECT_DIR" stallWarnEvery "${NIGHTSHIFT_STALL_WARN:-}")"
STALL_OK=1
case "$STALL_MAX" in '' | *[!0-9]*) STALL_OK=0 ;; esac
case "$STALL_WARN" in '' | *[!0-9]* | 0) STALL_OK=0 ;; esac
NOTIFY="$(rule "$PROJECT_DIR" notifyCommand "${NIGHTSHIFT_NOTIFY_CMD:-}")"
GATE_MESSAGE="$(rule "$PROJECT_DIR" clockOutMessage "${NIGHTSHIFT_GATE_MESSAGE:-}")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_line() { [ -d "$NS" ] && printf '%s · %s\n' "$(ts)" "$1" >>"$LOG"; }

# Only the Items list is the shift. A checkbox above it is prose — an owner's note, an example in
# the contract — and counting it would hold a session over something nobody queued. The heading
# must stand alone on its line, so the contract's inline `## Items` references never match.
items_section() { sed -n '/^## Items[[:space:]]*$/,$p' "$PUNCH" 2>/dev/null; }

# grep -c prints the count AND exits 1 on zero matches; keep only the number.
count() {
  local n
  n="$(items_section | grep -cE "$1" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}
open_boxes()   { count '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]'; }
ticked_boxes() { count '^[[:space:]]*-[[:space:]]*\[[xX]\]'; }

# The code repo is what makes a commit visible as progress, and the recommended layout puts it
# one level below the project dir rather than at it. Where several repos sit there, no single
# HEAD describes the shift — so fingerprint all of them, and a commit in any one still counts.
project_head() {
  local r child base heads=""
  if r="$(repo_root "$PROJECT_DIR")"; then
    git -C "$r" rev-parse HEAD 2>/dev/null || printf 'nohead'
    return 0
  fi
  for child in "$PROJECT_DIR"/*/; do
    base="${child%/}"
    base="${base##*/}"
    case "$base" in .*) continue ;; esac
    r="$(git -C "$child" rev-parse HEAD 2>/dev/null)" || continue
    heads="$heads$r"
  done
  printf '%s' "${heads:-nohead}"
}

deadline_passed() {
  local now dl target
  now="$(date +%s)"
  dl="$(tr -d '[:space:]' <"$DEADLINE" 2>/dev/null || true)"
  [ -n "$dl" ] || return 1
  if printf '%s' "$dl" | grep -qE '^[0-9]+$'; then
    target="$dl"                                    # epoch seconds (what `start` writes)
  else                                              # best-effort ISO parse, GNU then BSD
    target="$(date -d "$dl" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S' "$dl" +%s 2>/dev/null || true)"
  fi
  [ -n "$target" ] || return 1
  [ "$now" -ge "$target" ]
}

# Morning whistle — fires at most once per shift; $1 is the summary line.
whistle() {
  [ -n "$NOTIFY" ] || return 0
  # Exclusive create: of two sessions releasing at once, exactly one owns the whistle.
  (set -C; : >"$NOTIFIED") 2>/dev/null || return 0
  NIGHTSHIFT_SUMMARY="$1" sh -c "$NOTIFY" nightshift "$1" >/dev/null 2>&1 || true
}

# Receipts snapshot — $1 is the commit subject. Transient markers stay out via the receipts
# repo's own .gitignore; the pinned identity keeps this working headless. Signing is turned off
# explicitly: an owner with commit.gpgsign=true globally would otherwise lose every receipt to a
# key prompt that nothing is there to answer at 3am.
receipts_commit() {
  local err
  [ -d "$NS/.git" ] || return 0
  git -C "$NS" add -A >/dev/null 2>&1 || true
  err="$(git -C "$NS" -c user.name=nightshift -c user.email=nightshift@localhost \
    -c commit.gpgsign=false commit -q -m "$1" 2>&1)" && return 0
  case "$err" in
    *"nothing to commit"* | *"nothing added"*) : ;;
    *) log_line "receipts commit failed: $(printf '%s' "$err" | head -n1)" ;;
  esac
}

# Every shift-ending release runs through here. ENDED is what stands the site rules down —
# hardhat keeps them armed while a stop-work order is merely pending, because the agent goes on
# working until its next stop attempt.
end_shift() {
  [ -d "$NS" ] && : >"$ENDED"
  # The shift is over, so the site stops being on shift: without this the guards would still apply
  # to whatever ordinary session opens this project next.
  rm -f "$NS/.shift-armed"
  receipts_commit "$1"
  whistle "$1"
}

if [ -f "$PUNCH" ]; then OPEN="$(open_boxes)"; TICKED="$(ticked_boxes)"; else OPEN=0; TICKED=0; fi
TOTAL=$((OPEN + TICKED))

# Record the shift's own session, once — same contract as hardhat's record: id, transcript, and
# the claude ancestor's pid + start time, claimed with an exclusive create so two racing first
# sessions cannot interleave. Losing the race is the design.
record_shift_session() {
  local p="$$" _ comm pid="" start=""
  for _ in 1 2 3 4 5 6; do
    case "$p" in '' | *[!0-9]*) break ;; esac
    [ "$p" -gt 1 ] || break
    comm="$(ps -o comm= -p "$p" 2>/dev/null)" || break
    case "${comm##*/}" in claude) pid="$p"; break ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')"
  done
  [ -z "$pid" ] || start="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  (set -C; printf '%s\n%s\n%s\n%s\n' "$SID" "${TPATH:-}" "$pid" "$start" >"$NS/.shift-session") 2>/dev/null || true
}
# A shift exists because the owner started one, never because a list exists. `/nightshift:start`
# writes .shift-armed; without it the punch list is a to-do file and every session stops freely —
# including the one that just wrote the list while planning.
[ -f "$NS/.shift-armed" ] || exit 0

if [ ! -f "$NS/.shift-session" ] && [ -n "${SID:-}" ]; then
  record_shift_session
fi

# The shift binds ONE session — the recorded one. Any other conversation in this project stops
# freely: the night is not its business unless the owner brings it. A watchman revival carries
# NIGHTSHIFT_REVIVAL=1 and inherits the binding even when the fresh-session fallback gave it a
# new id — it re-claims the record so the watchman and the clean-end tell follow the living
# thread. No parseable id keeps the conservative reading: held.
REC="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
if [ -n "$REC" ] && [ -n "${SID:-}" ] && [ "$SID" != "$REC" ]; then
  if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
    rm -f "$NS/.shift-session"
    record_shift_session
  else
    exit 0
  fi
fi

# One writer per site from here down: the stall fingerprint, the stop/ended markers, and the
# receipts commit are read-modify-write against shared files, and two sessions can attempt to
# stop at once. An unlockable site is decided unlocked — the gate must answer, never queue.
if [ -d "$NS" ] && ns_lock "$NS"; then
  trap 'ns_unlock "$NS"' EXIT
fi

# 1. Stop-work order — honor at once; open boxes are left open on purpose (an honest snapshot).
if [ -f "$STOP" ]; then
  if [ -f "$PUNCH" ]; then
    reason="$(head -n1 "$STOP" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    summary="shift ended${reason:+ ($reason)}: $TICKED/$TOTAL done"
    end_shift "$summary"
  fi
  # A stop-work order ends the shift whether or not a list survived to summarise, so the site is
  # disarmed either way — otherwise the guards would outlive the night that armed them.
  rm -f "$NS/.shift-armed"
  exit 0
fi

# 2. Done — no punch list at all, or every box ticked.
[ -f "$PUNCH" ] || exit 0
if [ "$OPEN" -eq 0 ]; then
  end_shift "shift done: $TICKED/$TOTAL"
  exit 0
fi

# 3. Quitting time — mechanical deadline.
if [ -f "$DEADLINE" ] && deadline_passed; then
  log_line "quitting time — shift ended, $TICKED/$TOTAL done, items left open"
  printf 'deadline\n' >"$STOP"
  end_shift "quitting time: $TICKED/$TOTAL done, items left open"
  exit 0
fi

# Stall guard — consecutive stop attempts with no progress. Progress = a box ticked OR a
# commit landed, captured in the fingerprint; either resets the counter. Held by default:
# warn in the shift log every STALL_WARN stuck attempts and keep blocking. Auto-end only on
# the owner's NIGHTSHIFT_STALL_MAX=N opt-in.
if [ "$STALL_OK" -eq 1 ]; then
  FP="$TICKED:$(project_head)"
  prev_fp=""
  prev_n=0
  if [ -f "$STALL" ]; then
    prev_fp="$(sed -n '1p' "$STALL")"
    prev_n="$(sed -n '2p' "$STALL")"
    prev_n="${prev_n:-0}"
  fi
  if [ "$prev_fp" = "$FP" ]; then
    attempts=$((prev_n + 1))
  else
    attempts=1
  fi
  if [ "$STALL_MAX" -gt 0 ] 2>/dev/null; then
    if [ "$attempts" -ge "$STALL_MAX" ]; then
      log_line "stalled — auto-ended, $attempts attempts no progress, $TICKED/$TOTAL done, items left open"
      printf 'stalled\n' >"$STOP"
      end_shift "stalled: $TICKED/$TOTAL done, $attempts attempts no progress"
      exit 0
    fi
  elif [ "$attempts" -ge "$STALL_WARN" ]; then
    log_line "stall warning — $attempts attempts no progress, $TICKED/$TOTAL done; keeping shift open"
    attempts=0
  fi
  printf '%s\n%s\n' "$FP" "$attempts" >"$STALL"
else
  log_line "stall guard down — stallMax/stallWarnEvery unreadable (.nightshift/rules.json absent or incomplete); re-run /nightshift:setup"
fi

# 4. Block, and re-inject the contract so the next turn resumes the shift. The reinjection
# text lives in the rules file (clockOutMessage) — the one copy, shipped in the template setup
# copies; jq builds the JSON so the owner's text cannot break the decision. The block itself
# never depends on config: an unreadable message (or no jq to embed it safely) still blocks,
# fail closed, with the repair named.
if [ -n "$GATE_MESSAGE" ] && command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$GATE_MESSAGE" '{decision:"block",reason:$r}'
  exit 0
fi
cat <<'JSON'
{"decision":"block","reason":"DO NOT STOP — the punch list (.nightshift/punch-list.md) still has open items. Work them one at a time per its contract, run each item's gate, and tick honestly; park owner decisions in .nightshift/parking-lot.md and keep working. (nightshift: the full contract reinjection lives in .nightshift/rules.json clockOutMessage — unreadable here, or jq is absent; re-run /nightshift:setup.)"}
JSON
exit 0
