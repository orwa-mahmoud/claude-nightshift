#!/usr/bin/env bash
# hardhat.sh — Codex PreToolUse guard. Same rules as Claude's hardhat; only the wire format
# differs, and that lives entirely in lib-io.sh.
#
# One zero-config rule: AskUserQuestion is denied during an active shift — park, don't
# ask. Every other rule is shift-scoped and opt-in, read from the owner's rules file
# (.nightshift/rules.json) — each empty by default, so an unset one is skipped silently:
#   protectedDirs        space/pipe-separated dir names never to git add/commit/tag/remote
#   expectedEmail        commits must be authored by this identity
#   neverCommitPatterns  staged diff (git diff --cached) must not match this grep -E pattern
#   forbiddenCommands    deny any command matching this grep -E pattern during a shift
#                        (the no-push recipe: set it to 'git .*push')
# An env var of the matching NIGHTSHIFT_ name overrides the file for the session; the file
# itself is guarded during a shift, so only the owner sets or lifts a rule.
#
# The two commit guards read git, so they resolve the repository the commit lands in (see
# repo_root in lib.sh) rather than assuming it is the project dir. When that repository cannot
# be identified they deny: a guard that cannot look is never a guard that approves.
set -u

_here="${BASH_SOURCE[0]%/*}"; [ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.
# shellcheck source=plugins/nightshift/lib/lib.sh
. "$_here/../../lib/lib.sh" # pure-bash path: no dirname, so a hostile PATH cannot unsource the helpers
# shellcheck source=plugins/nightshift/hooks/shared/hardhat-core.sh
. "$_here/../shared/hardhat-core.sh"
# shellcheck source=plugins/nightshift/hooks/codex/lib-io.sh
. "$_here/lib-io.sh"

codex_read_input
TOOL="$CODEX_TOOL_NAME"
CMD="$CODEX_TOOL_CMD"
CWD="$CODEX_CWD"
SID="$CODEX_SESSION_ID"
TPATH="$CODEX_TRANSCRIPT_PATH"

PROJECT_DIR="$(codex_project_dir)"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
ENDED="$NS/.ended"

# One copy: the rules file is the config; an env var of the matching name is a session-start
# override (the test suite's lever), never a second copy.
PROTECTED_DIRS="$(rule "$PROJECT_DIR" protectedDirs "${NIGHTSHIFT_PROTECTED_DIRS:-}")"
EXPECTED_EMAIL="$(rule "$PROJECT_DIR" expectedEmail "${NIGHTSHIFT_EXPECTED_EMAIL:-}")"
NEVER_COMMIT_PATTERNS="$(rule "$PROJECT_DIR" neverCommitPatterns "${NIGHTSHIFT_NEVER_COMMIT_PATTERNS:-}")"
FORBIDDEN_COMMANDS="$(rule "$PROJECT_DIR" forbiddenCommands "${NIGHTSHIFT_FORBIDDEN_COMMANDS:-}")"

# The emission (and its escaping) is the seam's; the guard only decides.
deny() {
  codex_emit_deny "$1"
  exit 0
}

# A commit message must not read as the command it mentions, so blank the message argument
# before matching. Only that argument: scrubbing every quoted span would also hide a genuinely
# forbidden command that happens to be quoted, such as sh -c "git push".
SCRUBBED="$(printf '%s' "$CMD" | sed -E "s/(-m|--message)([[:space:]]*|=)'[^']*'/\1 MSG/g; s/(-m|--message)([[:space:]]*|=)\"[^\"]*\"/\1 MSG/g")"

# Every remaining rule is shift-scoped: inert unless a shift is truly active. A stop-work order
# is a request, not the ending — the agent keeps working until its next stop attempt, which is
# exactly when the site rules still matter. The gate writes ENDED when it actually releases, and
# that is what stands these rules down.
if ! ns_hardhat_active; then
  exit 0
fi

# The shift records its own identity: the first session to work under an active shift writes its
# session id and transcript path, claimed with an exclusive create so two racing first sessions
# cannot interleave — one claim lands whole, and losing the race is the design. Codex offers no
# process ancestry this hook can vouch for, so the pid and start-time lines stay honestly empty.
# Line 5 names the host: a watchman only ever revives its own kind, and a record without it
# reads as Claude's — another agent's watchman would adopt this shift.
record_shift_session() {
  (set -C; printf '%s\n%s\n\n\ncodex\n' "$SID" "${TPATH:-}" >"$NS/.shift-session") 2>/dev/null || true
}
# The guards are the shift's, so they arrive with the shift. `/nightshift:start` writes
# .shift-armed; before it exists this is an ordinary session in an ordinary project and nothing
# here applies to it.
if [ ! -f "$NS/.shift-session" ] && [ -n "${SID:-}" ]; then
  record_shift_session
fi

# The site rules govern the shift's own session; another conversation in the same project works
# untouched — its questions, commits, and commands are the owner's business, not the night's. A
# marked revival stays bound whatever id the fallback chain gave it.
REC="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
if [ -n "$REC" ] && [ -n "${SID:-}" ] && [ "$SID" != "$REC" ] \
  && [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ]; then
  exit 0
fi

# Tool rules — the rules file's toolDeny map: tool name -> denial message. A key's message
# is the denial the model reads; an empty message lifts the rule; an absent key means the
# default — AskUserQuestion parked so a 2:40am question cannot kill the run, every other
# tool allowed. (sed backs up the jq path; the park rule holds even without jq.)
TOOL_RULES="$(rule "$PROJECT_DIR" toolDeny "${NIGHTSHIFT_TOOL_RULES:-}")"
rules_has() {
  [ -n "$TOOL_RULES" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -e --arg t "$1" 'has($t)' >/dev/null 2>&1
  else
    printf '%s' "$TOOL_RULES" | grep -q "\"$1\"[[:space:]]*:"
  fi
}
rules_msg() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -r --arg t "$1" '.[$t] // empty' 2>/dev/null
  else
    printf '%s' "$TOOL_RULES" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}
if [ -n "$TOOL_RULES" ] && command -v jq >/dev/null 2>&1 \
  && ! printf '%s' "$TOOL_RULES" | jq -e 'type == "object"' >/dev/null 2>&1; then
  deny "BLOCKED: the toolDeny rules are not a JSON object, so the tool rules cannot run. Fix .nightshift/rules.json or re-run /nightshift:setup."
fi
if [ "$TOOL" = "AskUserQuestion" ] || codex_input_mentions_tool "AskUserQuestion"; then
  # The park message is the map's AskUserQuestion entry — the one copy, shipped in the
  # template setup copies. No readable entry still parks the question (fail closed), with the
  # repair named.
  if rules_has "AskUserQuestion"; then
    m="$(rules_msg AskUserQuestion)"
    [ -z "$m" ] || deny "$m"
  else
    deny "BLOCKED (park, don't ask): a shift is active — record the decision and a sensible default in .nightshift/parking-lot.md and keep working. (nightshift: the owner's park message lives in .nightshift/rules.json toolDeny — unreadable here; re-run /nightshift:setup.)"
  fi
  exit 0 # a permitted question is not a command; the command guards have no business with it
fi
if [ -n "$TOOL" ] && [ "$TOOL" != "Bash" ] && rules_has "$TOOL"; then
  m="$(rules_msg "$TOOL")"
  [ -z "$m" ] || deny "$m"
fi

# The rules file is the owner's leash on the night, and the night never rewrites it: during a
# shift, deny any file edit aimed at the rules file and any command that names it. An owner's
# mid-shift edit is the owner's hand — it reads from the very next tool call. Recognizing an
# edit and its targets is the seam's job: Codex delivers file edits as apply_patch with the
# patch text where a command would ride.
if codex_is_file_edit; then
  if codex_edit_touches '\.nightshift/rules\.json|nightshift-rules\.json'; then
    deny "BLOCKED: the rules file is the owner's — the night never rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working; the owner's edit applies from the next tool call."
  fi
  exit 0 # a file edit is not a command; the command guards have no business with it
fi
if printf '%s' "$SCRUBBED" | grep -qE '\.nightshift/rules\.json|nightshift-rules\.json'; then
  deny "BLOCKED: the rules file is the owner's — the night neither reads nor rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working."
fi

# An unparseable owner pattern makes grep exit 2, which a plain `if` reads as "no match" — the
# guard would wave everything through. Say so instead.
for _p in "FORBIDDEN_COMMANDS:$FORBIDDEN_COMMANDS" "NEVER_COMMIT_PATTERNS:$NEVER_COMMIT_PATTERNS"; do
  _name="${_p%%:*}"
  _pat="${_p#*:}"
  [ -n "$_pat" ] || continue
  valid_ere "$_pat" || deny "BLOCKED: NIGHTSHIFT_$_name is not a valid extended regular expression, so the guard it configures cannot run. Fix the pattern in your session settings."
done

git_verb() { printf '%s' "$SCRUBBED" | grep -qE "(^|[^[:alnum:]_-])git([^[:alnum:]]|$)" \
  && printf '%s' "$SCRUBBED" | grep -qE "(^|[^[:alnum:]_-])$1([^[:alnum:]]|$)"; }
is_git_write() { git_verb add || git_verb commit || git_verb tag || git_verb remote; }
is_commit()    { git_verb commit; }

# 1) Protected dirs — never stage/commit/tag/remote inside them. Match the scrubbed command so a
# commit message naming the directory is not mistaken for a path, and require a path boundary so
# 'ai_docs' does not also condemn 'ai_docs_public'.
if [ -n "$PROTECTED_DIRS" ] && is_git_write; then
  IFS=' |' read -ra _dirs <<<"$PROTECTED_DIRS"
  read -ra _toks <<<"$SCRUBBED"
  for d in "${_dirs[@]}"; do
    [ -n "$d" ] || continue
    for _tok in "${_toks[@]}"; do
      case "$_tok" in
        "$d" | "$d"/* | */"$d" | */"$d"/* | *="$d" | *="$d"/*)
          deny "BLOCKED: never git add/commit/tag/remote inside '$d' (a protected directory). Do not retry a rephrased form."
          ;;
      esac
    done
  done
fi

# 2) and 3) — the commit guards read git, so they need the repository the commit lands in,
# which the recommended layout puts one level below the project dir. Resolve it once, and fail
# closed: a guard that cannot see the repo denies rather than waving the commit through.
if is_commit && { [ -n "$EXPECTED_EMAIL" ] || [ -n "$NEVER_COMMIT_PATTERNS" ]; }; then
  # `--git-dir`/`--work-tree` relocate the commit somewhere the resolution below does not follow,
  # so the guards would inspect one repository while the commit lands in another. Unverifiable —
  # deny, exactly like the ambiguous-repo case: a guard that cannot look never approves.
  if printf '%s' "$SCRUBBED" | grep -qE -- '--git-dir|--work-tree'; then
    deny "BLOCKED: --git-dir/--work-tree point this commit somewhere the configured commit guards cannot verify. Run the commit from inside the repository instead."
  fi

  # The identity guard reads the repository's configuration, and a command can override identity
  # past that read — `-c user.email=`, `--author`, or a GIT_*_EMAIL prefix. With an override
  # present the config describes nothing, so it is denied rather than misread.
  if [ -n "$EXPECTED_EMAIL" ] && printf '%s' "$SCRUBBED" |
    grep -qE -- '-c[[:space:]]*user\.email=|--author|GIT_(AUTHOR|COMMITTER)_EMAIL='; then
    deny "BLOCKED: this commit overrides the author identity on the command line, which the expected-identity guard cannot verify. Commit with the repository's configured identity."
  fi

  # A command can name its own repository — `git -C <dir> commit`, `cd <dir> && git commit` —
  # and that is where the commit lands, whatever the session's working directory says.
  REPO="$(target_repo "$CMD" "${CWD:-$PROJECT_DIR}")"
  case "$?" in
    1) deny "BLOCKED: this commit names a directory that is not a git repository, so the configured commit guards cannot inspect it. Do not retry a rephrased form." ;;
    2) REPO="$(repo_root "$PROJECT_DIR" "$CWD")" || REPO="$(ns_work_target "$PROJECT_DIR")" || deny "BLOCKED: cannot tell which git repository this commit targets, so the configured commit guards cannot run. Run the commit from inside the repository." ;;
  esac

  # 2) Expected identity — commits must be authored by the configured email.
  if [ -n "$EXPECTED_EMAIL" ]; then
    email="$(git -C "$REPO" config user.email 2>/dev/null || true)"
    if [ "$email" != "$EXPECTED_EMAIL" ]; then
      deny "BLOCKED: committer identity ('$email') is not the expected '$EXPECTED_EMAIL'. Fix git config user.email, then retry."
    fi
  fi

  # 3) Never-commit patterns — everything this commit would write must be clean. `git commit -a`
  # and a pathspec commit stage as they run, so the index alone does not describe them; widen to
  # the working tree against HEAD whenever the command stages implicitly.
  if [ -n "$NEVER_COMMIT_PATTERNS" ]; then
    if commit_stages_implicitly "$CMD"; then
      _scope="the diff this commit would write"
      _diff="$(git -C "$REPO" diff HEAD 2>/dev/null)"
    else
      _scope="the staged diff"
      _diff="$(git -C "$REPO" diff --cached 2>/dev/null)"
    fi
    if printf '%s' "$_diff" | grep -qiE "$NEVER_COMMIT_PATTERNS"; then
      deny "BLOCKED: $_scope matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list."
    fi
  fi
fi

# 4) Forbidden commands — the owner's own site rules for this run.
if [ -n "$FORBIDDEN_COMMANDS" ] && printf '%s' "$SCRUBBED" | grep -qE "$FORBIDDEN_COMMANDS"; then
  deny "BLOCKED: the command matches the owner's forbidden list for this shift. Find another way, or park the task with a note in .nightshift/parking-lot.md and keep working. Do not retry a rephrased form."
fi

exit 0
