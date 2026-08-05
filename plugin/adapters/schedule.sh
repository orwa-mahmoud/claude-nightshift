#!/usr/bin/env bash
# schedule.sh — print the config your OS needs to start a shift at a fixed time.
#
# nightshift does not wait for a clock, and never will: a process that sleeps for hours dies to a
# closed lid, a logout, or a reboot, which is exactly the problem launchd and cron already solve.
# This generates their config, filled in for one project, and prints the single command that
# installs it. It registers nothing itself.
#
#   schedule.sh [--project DIR] [--at HH:MM] [--list] [--remove]
#
#   --at HH:MM   24-hour local time. Required unless --list or --remove.
#   --list       what is already registered for this project, and nothing else
#   --remove     print the command that unregisters it
#
# It runs offline and spends no model tokens — a session that has exhausted its credit can still
# register the run that starts when the credit returns.
#
# Exit: 0 printed · 1 usage or a missing project · 3 already registered (nothing printed to install)
set -u

PROJECT="$PWD"
AT=""
MODE="generate"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit 1
}
need_value() { [ "$2" -ge 2 ] || { printf 'schedule: %s needs a value\n' "$1" >&2; usage; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project) need_value "$1" $#; PROJECT="$2"; shift 2 ;;
    --at) need_value "$1" $#; AT="$2"; shift 2 ;;
    --list) MODE="list"; shift ;;
    --remove) MODE="remove"; shift ;;
    -h | --help) usage ;;
    *) printf 'schedule: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

cd "$PROJECT" 2>/dev/null || { printf 'schedule: cannot cd to %s\n' "$PROJECT" >&2; exit 1; }
PROJECT="$PWD"
[ -d "$PROJECT/.nightshift" ] || {
  printf 'schedule: no .nightshift at %s — run /nightshift:setup first\n' "$PROJECT" >&2
  exit 1
}

# One id per project PATH, not per folder name: two checkouts called "api" must not collide, and
# the same project must always produce the same id so a second run recognises its own entry.
slug="$(basename "$PROJECT" | tr -c 'A-Za-z0-9' '-' | sed 's/-*$//')"
hash="$(printf '%s' "$PROJECT" | cksum | cut -d' ' -f1)"
ID="${slug}-${hash}"
LABEL="com.nightshift.${ID}"
MARKER="# nightshift:${ID}"
LOG="$PROJECT/.nightshift/scheduled.log"
RUN="cd $PROJECT && claude -p '/nightshift:start' >> $LOG 2>&1"

case "$(uname -s)" in
  Darwin) OS="macos"; PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist" ;;
  *) OS="cron" ;;
esac

# Registered already? Two entries for one project means two agents on one punch list — the
# failure the shift's own one-session rule exists to prevent, arriving from outside it.
registered() {
  if [ "$OS" = "macos" ]; then
    [ -f "$PLIST" ] && return 0
    launchctl list 2>/dev/null | grep -qF "$LABEL"
  else
    crontab -l 2>/dev/null | grep -qF "$MARKER"
  fi
}

show_registered() {
  if [ "$OS" = "macos" ]; then
    [ ! -f "$PLIST" ] || printf '  plist:    %s\n' "$PLIST"
    launchctl list 2>/dev/null | grep -F "$LABEL" | sed 's/^/  launchd:  /'
  else
    crontab -l 2>/dev/null | grep -F "$MARKER" | sed 's/^/  crontab:  /'
  fi
}

if [ "$MODE" = "list" ]; then
  if registered; then
    printf 'Registered for %s:\n' "$PROJECT"
    show_registered
  else
    printf 'Nothing registered for %s\n' "$PROJECT"
  fi
  exit 0
fi

if [ "$MODE" = "remove" ]; then
  if ! registered; then
    printf 'Nothing registered for %s\n' "$PROJECT"
    exit 0
  fi
  printf 'To unregister:\n\n'
  if [ "$OS" = "macos" ]; then
    printf '  launchctl unload -w %s && rm %s\n\n' "$PLIST" "$PLIST"
  else
    printf '  crontab -l | grep -vF %s | crontab -\n\n' "'$MARKER'"
  fi
  exit 0
fi

case "$AT" in
  [0-2][0-9]:[0-5][0-9]) ;;
  *) printf 'schedule: --at needs a 24-hour HH:MM, got %s\n' "${AT:-nothing}" >&2; exit 1 ;;
esac
HH="${AT%%:*}"; MM="${AT##*:}"
[ "$HH" -le 23 ] || { printf 'schedule: %s is not a real hour\n' "$HH" >&2; exit 1; }

if registered; then
  printf 'Already registered for this project — nothing to install.\n\n'
  show_registered
  printf '\nTwo entries would put two agents on one punch list. Use --remove first to replace it.\n'
  exit 3
fi

# The punch list is the shift: a scheduled start works what it finds and promotes nothing, so an
# empty list at %s means the run does nothing at all.
if ! grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PROJECT/.nightshift/punch-list.md" 2>/dev/null; then
  printf 'Note: the punch list has no open items. A scheduled start works the list it finds and\n'
  printf 'promotes nothing, so queue the work before %s or the run will find nothing to do.\n\n' "$AT"
fi

printf 'Scheduled start for %s at %s\n\n' "$PROJECT" "$AT"

if [ "$OS" = "macos" ]; then
  cat <<PLIST_EOF
Write this to $PLIST:

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>${RUN}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>${HH#0}</integer>
    <key>Minute</key><integer>${MM#0}</integer>
  </dict>
  <key>RunAtLoad</key><false/>
</dict>
</plist>

Then install it:

  launchctl load -w ${PLIST}

PLIST_EOF
  printf 'A Mac that is asleep at %s runs nothing — launchd defers the job to the next wake.\n' "$AT"
  printf 'To have the machine wake for it: sudo pmset repeat wakeorpoweron MTWRFSU %s:00\n' "$AT"
else
  cat <<CRON_EOF
Add this line to your crontab (\`crontab -e\`):

  ${MM#0} ${HH#0} * * * ${RUN}  ${MARKER}

Or install it in one command:

  ( crontab -l 2>/dev/null; echo "${MM#0} ${HH#0} * * * ${RUN}  ${MARKER}" ) | crontab -

CRON_EOF
  printf 'A machine that is asleep or off at %s runs nothing — cron does not defer missed jobs.\n' "$AT"
fi

printf '\nCheck what is registered: %s --project %s --list\n' "$0" "$PROJECT"
printf 'Output of each run lands in %s\n' "$LOG"
