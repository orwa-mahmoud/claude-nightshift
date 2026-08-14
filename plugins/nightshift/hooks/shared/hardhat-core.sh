#!/usr/bin/env bash
# Shared hardhat decisions. Host wrappers own payload parsing and deny response emission.

ns_hardhat_active() {
  [ -f "$NS/.shift-armed" ] && [ -f "$PUNCH" ] && [ ! -f "$ENDED" ] \
    && [ "$(ns_open_boxes "$PUNCH")" -gt 0 ]
}

ns_hardhat_rules_targeted() {
  printf '%s' "$1" | grep -qE '\.nightshift/rules\.json|nightshift-rules\.json'
}

ns_hardhat_scrub() {
  printf '%s' "$1" | sed -E "s/(-m|--message)([[:space:]]*|=)'[^']*'/\1 MSG/g; s/(-m|--message)([[:space:]]*|=)\"[^\"]*\"/\1 MSG/g"
}

ns_hardhat_rules_has() {
  [ -n "${TOOL_RULES:-}" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -e --arg t "$1" 'has($t)' >/dev/null 2>&1
  else
    printf '%s' "$TOOL_RULES" | grep -q "\"$1\"[[:space:]]*:"
  fi
}

ns_hardhat_rules_msg() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -r --arg t "$1" '.[$t] // empty' 2>/dev/null
  else
    printf '%s' "$TOOL_RULES" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

ns_hardhat_tool_deny_broken() {
  [ -n "${TOOL_RULES:-}" ] && command -v jq >/dev/null 2>&1 \
    && ! printf '%s' "$TOOL_RULES" | jq -e 'type == "object"' >/dev/null 2>&1
}

ns_hardhat_park_reason() {
  if ns_hardhat_rules_has "AskUserQuestion"; then
    m="$(ns_hardhat_rules_msg AskUserQuestion)"
    [ -n "$m" ] || return 1
    printf '%s' "$m"
    return 0
  fi
  printf '%s' "BLOCKED (park, don't ask): a shift is active — record the decision and a sensible default in .nightshift/parking-lot.md and keep working. (nightshift: the owner's park message lives in .nightshift/rules.json toolDeny — unreadable here; re-run /nightshift:setup.)"
}

ns_hardhat_named_tool_reason() {
  [ -n "$1" ] && [ "$1" != "Bash" ] && ns_hardhat_rules_has "$1" || return 1
  m="$(ns_hardhat_rules_msg "$1")"
  [ -n "$m" ] || return 1
  printf '%s' "$m"
}

ns_hardhat_git_verb() {
  printf '%s' "$1" | grep -qE "(^|[^[:alnum:]_-])git([^[:alnum:]]|$)" \
    && printf '%s' "$1" | grep -qE "(^|[^[:alnum:]_-])$2([^[:alnum:]]|$)"
}

ns_hardhat_is_git_write() {
  ns_hardhat_git_verb "$1" add || ns_hardhat_git_verb "$1" commit \
    || ns_hardhat_git_verb "$1" tag || ns_hardhat_git_verb "$1" remote
}

ns_hardhat_is_commit() {
  ns_hardhat_git_verb "$1" commit
}

# Print a deny reason for a Bash-like command, or return 1 to allow.
# Uses globals: SCRUBBED CMD CWD PROJECT_DIR PROTECTED_DIRS EXPECTED_EMAIL
# NEVER_COMMIT_PATTERNS FORBIDDEN_COMMANDS
ns_hardhat_command_reason() {
  local _p _name _pat d _tok _dirs _toks REPO email _scope _diff
  for _p in "FORBIDDEN_COMMANDS:$FORBIDDEN_COMMANDS" "NEVER_COMMIT_PATTERNS:$NEVER_COMMIT_PATTERNS"; do
    _name="${_p%%:*}"
    _pat="${_p#*:}"
    [ -n "$_pat" ] || continue
    valid_ere "$_pat" || {
      printf '%s' "BLOCKED: NIGHTSHIFT_$_name is not a valid extended regular expression, so the guard it configures cannot run. Fix the pattern in your session settings."
      return 0
    }
  done

  if [ -n "$PROTECTED_DIRS" ] && ns_hardhat_is_git_write "$SCRUBBED"; then
    IFS=' |' read -ra _dirs <<<"$PROTECTED_DIRS"
    read -ra _toks <<<"$SCRUBBED"
    for d in "${_dirs[@]}"; do
      [ -n "$d" ] || continue
      for _tok in "${_toks[@]}"; do
        case "$_tok" in
          "$d" | "$d"/* | */"$d" | */"$d"/* | *="$d" | *="$d"/*)
            printf '%s' "BLOCKED: never git add/commit/tag/remote inside '$d' (a protected directory). Do not retry a rephrased form."
            return 0
            ;;
        esac
      done
    done
  fi

  if ns_hardhat_is_commit "$SCRUBBED" && { [ -n "$EXPECTED_EMAIL" ] || [ -n "$NEVER_COMMIT_PATTERNS" ]; }; then
    if printf '%s' "$SCRUBBED" | grep -qE -- '--git-dir|--work-tree'; then
      printf '%s' "BLOCKED: --git-dir/--work-tree point this commit somewhere the configured commit guards cannot verify. Run the commit from inside the repository instead."
      return 0
    fi
    if [ -n "$EXPECTED_EMAIL" ] && printf '%s' "$SCRUBBED" |
      grep -qE -- '-c[[:space:]]*user\.email=|--author|GIT_(AUTHOR|COMMITTER)_EMAIL='; then
      printf '%s' "BLOCKED: this commit overrides the author identity on the command line, which the expected-identity guard cannot verify. Commit with the repository's configured identity."
      return 0
    fi
    REPO="$(target_repo "$CMD" "${CWD:-$PROJECT_DIR}")"
    case "$?" in
      1) printf '%s' "BLOCKED: this commit names a directory that is not a git repository, so the configured commit guards cannot inspect it. Do not retry a rephrased form."
         return 0 ;;
      2) REPO="$(repo_root "$PROJECT_DIR" "$CWD")" || REPO="$(ns_work_target "$PROJECT_DIR")" || {
           printf '%s' "BLOCKED: cannot tell which git repository this commit targets, so the configured commit guards cannot run. Run the commit from inside the repository."
           return 0
         } ;;
    esac
    if [ -n "$EXPECTED_EMAIL" ]; then
      email="$(git -C "$REPO" config user.email 2>/dev/null || true)"
      if [ "$email" != "$EXPECTED_EMAIL" ]; then
        printf '%s' "BLOCKED: committer identity ('$email') is not the expected '$EXPECTED_EMAIL'. Fix git config user.email, then retry."
        return 0
      fi
    fi
    if [ -n "$NEVER_COMMIT_PATTERNS" ]; then
      if commit_stages_implicitly "$CMD"; then
        _scope="the diff this commit would write"
        _diff="$(git -C "$REPO" diff HEAD 2>/dev/null)"
      else
        _scope="the staged diff"
        _diff="$(git -C "$REPO" diff --cached 2>/dev/null)"
      fi
      if printf '%s' "$_diff" | grep -qiE "$NEVER_COMMIT_PATTERNS"; then
        printf '%s' "BLOCKED: $_scope matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list."
        return 0
      fi
    fi
  fi

  if [ -n "$FORBIDDEN_COMMANDS" ] && printf '%s' "$SCRUBBED" | grep -qE "$FORBIDDEN_COMMANDS"; then
    printf '%s' "BLOCKED: the command matches the owner's forbidden list for this shift. Find another way, or park the task with a note in .nightshift/parking-lot.md and keep working. Do not retry a rephrased form."
    return 0
  fi
  return 1
}
