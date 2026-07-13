#!/usr/bin/env bash
# spot-check.sh — PostToolUse (Edit|Write). The inspector checks each piece of work as it
# lands: instant syntax/lint feedback on the file just written. Silent when clean; exit 2
# with a note when not. Linters that aren't installed are skipped silently (zero-config).
set -u

INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  file="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
else
  file="$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[ -n "$file" ] && [ -f "$file" ] || exit 0

fail() { printf 'spot-check: %s\n%s\n' "$1" "$2" >&2; exit 2; }

case "$file" in
  *.sh)
    err="$(bash -n "$file" 2>&1)"  || fail "bash -n failed for $file" "$err"
    if command -v shellcheck >/dev/null 2>&1; then
      out="$(shellcheck "$file" 2>&1)" || fail "shellcheck findings for $file" "$out"
    fi
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      err="$(jq . "$file" 2>&1 >/dev/null)" || fail "invalid JSON in $file" "$err"
    fi
    ;;
  *.yaml | *.yml)
    if command -v yamllint >/dev/null 2>&1; then
      out="$(yamllint "$file" 2>&1)" || fail "yamllint findings for $file" "$out"
    fi
    ;;
esac
exit 0
