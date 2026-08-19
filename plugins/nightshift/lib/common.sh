#!/usr/bin/env bash
# Generic shell helpers shared by Nightshift hooks and runtime.

# valid_ere <pattern> — true when grep -E accepts the pattern.
# An invalid pattern makes grep exit 2, which reads exactly like "no match" to a plain `if`,
# so a typo in an owner's guard pattern would silently disable the guard.
valid_ere() {
  printf '' | grep -qE "$1" 2>/dev/null
  [ "$?" -le 1 ]
}

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

ns_have_cmd() { command -v "$1" >/dev/null 2>&1; }

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
