#!/usr/bin/env bash
# hardhat.sh — PreToolUse guard. Mechanical safety, zero-config core.
#
# One zero-config rule: AskUserQuestion is denied during an active shift — park, don't
# ask. Every other rule is shift-scoped and opt-in — each empty by default, so an unset
# one is skipped silently (a one-account developer configures nothing). Env vars are
# fixed when the session starts, so only a human can set them — never the agent mid-run:
#   NIGHTSHIFT_PROTECTED_DIRS        space/pipe-separated dir names never to git add/commit/tag/remote
#   NIGHTSHIFT_EXPECTED_EMAIL        commits must be authored by this identity
#   NIGHTSHIFT_NEVER_COMMIT_PATTERNS staged diff (git diff --cached) must not match this grep -E pattern
#   NIGHTSHIFT_FORBIDDEN_COMMANDS    deny any command matching this grep -E pattern during a shift
#                                    (the no-push recipe: set it to 'git push')
#
# The two commit guards read git, so they resolve the repository the commit lands in (see
# repo_root in lib.sh) rather than assuming it is the project dir. When that repository cannot
# be identified they deny: a guard that cannot look is never a guard that approves.
set -u

# shellcheck source=hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
ENDED="$NS/.ended"

PROTECTED_DIRS="${NIGHTSHIFT_PROTECTED_DIRS:-}"
EXPECTED_EMAIL="${NIGHTSHIFT_EXPECTED_EMAIL:-}"
NEVER_COMMIT_PATTERNS="${NIGHTSHIFT_NEVER_COMMIT_PATTERNS:-}"
FORBIDDEN_COMMANDS="${NIGHTSHIFT_FORBIDDEN_COMMANDS:-}"

# Reasons interpolate owner config and git output; escape them so a stray quote or
# backslash can never break the JSON and void the deny.
deny() {
  reason="$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# Extract tool + command. jq preferred; the raw payload is the fallback so a missing jq
# can never silently disable the guard.
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
else
  # No jq: pull the fields out of the raw JSON with sed so the guard still works. Extract the
  # command value rather than falling back to the whole payload — the quote-scrub below would
  # otherwise strip the command string itself and a push would slip through.
  TOOL="$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
  CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[ -n "$CMD" ] || CMD="$INPUT"

# Park, don't ask — during an active shift, deny AskUserQuestion so a 2:40am question
# cannot kill the run. No active shift -> questions flow normally. (Raw grep backs up the
# jq path so the rule holds even without jq.)
if [ "$TOOL" = "AskUserQuestion" ] || printf '%s' "$INPUT" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"AskUserQuestion"'; then
  if [ -f "$PUNCH" ] && [ ! -f "$ENDED" ] \
     && grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null; then
    deny "BLOCKED (park, don't ask): a shift is active and the owner is asleep. Choose the most sensible production-grade default yourself, record the decision and your reasoning in .nightshift/parking-lot.md, and KEEP WORKING. The owner reviews it in the morning."
  fi
  exit 0
fi

# A commit message must not read as the command it mentions, so blank the message argument
# before matching. Only that argument: scrubbing every quoted span would also hide a genuinely
# forbidden command that happens to be quoted, such as sh -c "git push".
SCRUBBED="$(printf '%s' "$CMD" | sed -E "s/(-m|--message)([[:space:]]*|=)'[^']*'/\1 MSG/g; s/(-m|--message)([[:space:]]*|=)\"[^\"]*\"/\1 MSG/g")"

# Every remaining rule is shift-scoped: inert unless a shift is truly active. A stop-work order
# is a request, not the ending — the agent keeps working until its next stop attempt, which is
# exactly when the site rules still matter. The gate writes ENDED when it actually releases, and
# that is what stands these rules down.
if [ ! -f "$PUNCH" ] || [ -f "$ENDED" ] \
   || ! grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null; then
  exit 0
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
  # A command can name its own repository — `git -C <dir> commit`, `cd <dir> && git commit` —
  # and that is where the commit lands, whatever the session's working directory says.
  REPO="$(target_repo "$CMD" "${CWD:-$PROJECT_DIR}")"
  case "$?" in
    1) deny "BLOCKED: this commit names a directory that is not a git repository, so the configured commit guards cannot inspect it. Do not retry a rephrased form." ;;
    2) REPO="$(repo_root "$PROJECT_DIR" "$CWD")" || deny "BLOCKED: cannot tell which git repository this commit targets, so the configured commit guards cannot run. Run the commit from inside the repository." ;;
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
