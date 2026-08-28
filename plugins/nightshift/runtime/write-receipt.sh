#!/usr/bin/env bash
# write-receipt.sh — record an artifact-mode completion receipt.
#
# Replaces a work-target git commit only while .nightshift/work-mode is artifact.
# Rejects missing or empty outputs. Paths are tokenized; secret lines are omitted.
#
#   write-receipt.sh --project DIR --item TEXT --verify TEXT \
#     [--decision TEXT] [--source TEXT]... --output PATH...
#
# Exit: 0 wrote the receipt path on stdout · 1 usage · 2 missing/empty output · 3 not artifact mode
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../lib/lib.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
ITEM=""
VERIFY=""
DECISION=""
SOURCES=""
OUTPUTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { printf 'write-receipt: --project needs a value\n' >&2; exit 1; }
      PROJECT="$2"
      shift 2
      ;;
    --item)
      [ $# -ge 2 ] || { printf 'write-receipt: --item needs a value\n' >&2; exit 1; }
      ITEM="$2"
      shift 2
      ;;
    --verify)
      [ $# -ge 2 ] || { printf 'write-receipt: --verify needs a value\n' >&2; exit 1; }
      VERIFY="$2"
      shift 2
      ;;
    --decision)
      [ $# -ge 2 ] || { printf 'write-receipt: --decision needs a value\n' >&2; exit 1; }
      DECISION="$2"
      shift 2
      ;;
    --source)
      [ $# -ge 2 ] || { printf 'write-receipt: --source needs a value\n' >&2; exit 1; }
      SOURCES="${SOURCES}${SOURCES:+
}$2"
      shift 2
      ;;
    --output)
      [ $# -ge 2 ] || { printf 'write-receipt: --output needs a value\n' >&2; exit 1; }
      OUTPUTS="${OUTPUTS}${OUTPUTS:+
}$2"
      shift 2
      ;;
    -h | --help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 1
      ;;
    *) printf 'write-receipt: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

HOST="$(cd -P "$PROJECT" 2>/dev/null && pwd)" || {
  printf 'write-receipt: cannot cd to %s\n' "$PROJECT" >&2
  exit 1
}
if ! WORKSPACE="$(ns_workspace_root "$HOST" 2>/dev/null)"; then
  printf 'write-receipt: invalid .nightshift-link\n' >&2
  exit 1
fi
NS="$WORKSPACE/.nightshift"
[ -d "$NS" ] || {
  printf 'write-receipt: no .nightshift/ at %s\n' "$WORKSPACE" >&2
  exit 1
}

mode="$(ns_work_mode "$WORKSPACE" 2>/dev/null)" || {
  printf 'write-receipt: work-mode is malformed\n' >&2
  exit 3
}
if [ "$mode" != artifact ]; then
  printf 'write-receipt: work-mode is %s; write a git commit in the work target instead\n' "$mode" >&2
  exit 3
fi

[ -n "$ITEM" ] || { printf 'write-receipt: --item is required\n' >&2; exit 1; }
[ -n "$VERIFY" ] || { printf 'write-receipt: --verify is required\n' >&2; exit 1; }
[ -n "$OUTPUTS" ] || { printf 'write-receipt: at least one --output is required\n' >&2; exit 2; }

TARGET="$(ns_work_target "$WORKSPACE" 2>/dev/null || true)"
HOME_ROOT="${HOME:-}"

sanitize() {
  ns_sanitize_line "$1" "$HOME_ROOT" "$WORKSPACE" "$TARGET" || printf '(redacted)'
}

# Validate outputs before creating the receipts directory.
ok_outputs=""
while IFS= read -r raw; do
  [ -n "$raw" ] || continue
  case "$raw" in /*) abs="$raw" ;; *) abs="$HOST/$raw" ;; esac
  if [ -L "$abs" ] || [ ! -f "$abs" ]; then
    printf 'write-receipt: missing output: %s\n' "$raw" >&2
    exit 2
  fi
  bytes="$(wc -c <"$abs" | tr -d ' ')"
  if [ "$bytes" -eq 0 ]; then
    printf 'write-receipt: empty output: %s\n' "$raw" >&2
    exit 2
  fi
  hash="$(ns_file_sha256 "$abs")" || {
    printf 'write-receipt: cannot hash %s\n' "$raw" >&2
    exit 1
  }
  mtime="$(ns_mtime "$abs")"
  shown="$(sanitize "$abs")"
  ok_outputs="${ok_outputs}${ok_outputs:+
}path: ${shown}
bytes: ${bytes}
sha256: ${hash}
mtime: ${mtime}"
done <<EOF
$OUTPUTS
EOF

[ -n "$ok_outputs" ] || {
  printf 'write-receipt: at least one --output is required\n' >&2
  exit 2
}

dir="$(ns_receipts_dir "$WORKSPACE")"
if [ -L "$dir" ]; then
  printf 'write-receipt: refuse to write through a symlink receipts path\n' >&2
  exit 2
fi
mkdir -p "$dir" || exit 1
if [ -L "$dir" ]; then
  printf 'write-receipt: refuse to write through a symlink receipts path\n' >&2
  exit 2
fi
stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
slug="$(ns_receipt_slug "$ITEM")"
dest="$dir/${stamp}-${slug}.md"
n=1
while [ -e "$dest" ]; do
  dest="$dir/${stamp}-${slug}-$n.md"
  n=$((n + 1))
done

recorded="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
item_line="$(sanitize "$ITEM")"
verify_line="$(sanitize "$VERIFY")"
{
  printf '%s\n' '# Nightshift artifact receipt'
  printf '\n'
  printf 'recorded: %s\n' "$recorded"
  printf 'item: %s\n' "$item_line"
  printf 'verification: %s\n' "$verify_line"
  if [ -n "$DECISION" ]; then
    printf 'decision: %s\n' "$(sanitize "$DECISION")"
  fi
  printf 'workspace: %s\n' "$(sanitize "$WORKSPACE")"
  if [ -n "$TARGET" ]; then
    printf 'work_target: %s\n' "$(sanitize "$TARGET")"
  fi
  printf 'mode: artifact\n'
  if [ -n "$SOURCES" ]; then
    printf '\n## Sources\n\n'
    while IFS= read -r src; do
      [ -n "$src" ] || continue
      printf -- '- %s\n' "$(sanitize "$src")"
    done <<EOF
$SOURCES
EOF
  fi
  printf '\n## Outputs\n\n'
  printf '%s\n' "$ok_outputs"
} >"$dest" || exit 1

printf '%s\n' "$dest"
exit 0
