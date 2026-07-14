#!/usr/bin/env bash
# hardhat.sh — PreToolUse guard. Mechanical safety, zero-config core.
#
# no-push is punch-list-scoped: denied whenever a punch list EXISTS — even all ticked,
# even under a STOP marker. In a nightshift project the owner reviews and pushes, unless
# the owner grants NIGHTSHIFT_ALLOW_PUSH: env vars are fixed when the session starts, so
# only a human can flip it — never the agent mid-run.
#
# The remaining rules are shift-scoped and opt-in — each empty by default, so an unset
# one is skipped silently (a one-account developer configures nothing):
#   NIGHTSHIFT_ALLOW_PUSH            non-empty lets the agent git push (default: denied)
#   NIGHTSHIFT_PROTECTED_DIRS        space/pipe-separated dir names never to git add/commit/tag/remote
#   NIGHTSHIFT_EXPECTED_EMAIL        commits must be authored by this identity
#   NIGHTSHIFT_NEVER_COMMIT_PATTERNS staged diff (git diff --cached) must not match this grep -E pattern
#   NIGHTSHIFT_FORBIDDEN_COMMANDS    deny any command matching this grep -E pattern during a shift
set -u

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
STOP="$NS/STOP"

ALLOW_PUSH="${NIGHTSHIFT_ALLOW_PUSH:-}"
PROTECTED_DIRS="${NIGHTSHIFT_PROTECTED_DIRS:-}"
EXPECTED_EMAIL="${NIGHTSHIFT_EXPECTED_EMAIL:-}"
NEVER_COMMIT_PATTERNS="${NIGHTSHIFT_NEVER_COMMIT_PATTERNS:-}"
FORBIDDEN_COMMANDS="${NIGHTSHIFT_FORBIDDEN_COMMANDS:-}"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Extract tool + command. jq preferred; the raw payload is the fallback so a missing jq
# can never silently disable the guard.
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  # No jq: pull the fields out of the raw JSON with sed so the guard still works. Extract the
  # command value rather than falling back to the whole payload — the quote-scrub below would
  # otherwise strip the command string itself and a push would slip through.
  TOOL="$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
fi
[ -n "$CMD" ] || CMD="$INPUT"

# Park, don't ask — during an active shift, deny AskUserQuestion so a 2:40am question
# cannot kill the run. No active shift -> questions flow normally. (Raw grep backs up the
# jq path so the rule holds even without jq.)
if [ "$TOOL" = "AskUserQuestion" ] || printf '%s' "$INPUT" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"AskUserQuestion"'; then
  if [ -f "$PUNCH" ] && [ ! -f "$STOP" ] \
     && grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null; then
    deny "BLOCKED (park, don't ask): a shift is active and the owner is asleep. Choose the most sensible production-grade default yourself, record the decision and your reasoning in .nightshift/parking-lot.md, and KEEP WORKING. The owner reviews it in the morning."
  fi
  exit 0
fi

# Quoted spans hold commit messages and the like — a message containing "push" must not
# read as a push. Strip them before matching git subcommands.
SCRUBBED="$(printf '%s' "$CMD" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")"

# 1) No push — punch-list-scoped: the file merely existing is enough. Only the owner can
#    lift it (NIGHTSHIFT_ALLOW_PUSH), and only from outside the session.
if [ -z "$ALLOW_PUSH" ] && [ -f "$PUNCH" ] && printf '%s' "$SCRUBBED" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+[^;&|]*)?[[:space:]]+push([[:space:]]|$)'; then
  deny "BLOCKED: git push is forbidden in a nightshift project — commit locally; the owner reviews and pushes. Do not retry a rephrased form."
fi

# The remaining rules are shift-scoped: inert unless a shift is truly active.
if [ ! -f "$PUNCH" ] || [ -f "$STOP" ] \
   || ! grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$PUNCH" 2>/dev/null; then
  exit 0
fi

git_verb() { printf '%s' "$SCRUBBED" | grep -qE "(^|[^[:alnum:]_-])git([^[:alnum:]]|$)" \
  && printf '%s' "$SCRUBBED" | grep -qE "(^|[^[:alnum:]_-])$1([^[:alnum:]]|$)"; }
is_git_write() { git_verb add || git_verb commit || git_verb tag || git_verb remote; }
is_commit()    { git_verb commit; }

# 2) Protected dirs — never stage/commit/tag/remote inside them.
if [ -n "$PROTECTED_DIRS" ] && is_git_write; then
  IFS=' |' read -ra _dirs <<<"$PROTECTED_DIRS"
  for d in "${_dirs[@]}"; do
    [ -n "$d" ] || continue
    if printf '%s' "$CMD" | grep -qF "$d"; then
      deny "BLOCKED: never git add/commit/tag/remote inside '$d' (a protected directory). Do not retry a rephrased form."
    fi
  done
fi

# 3) Expected identity — commits must be authored by the configured email.
if [ -n "$EXPECTED_EMAIL" ] && is_commit; then
  email="$(git -C "$PROJECT_DIR" config user.email 2>/dev/null || true)"
  if [ "$email" != "$EXPECTED_EMAIL" ]; then
    deny "BLOCKED: committer identity ('$email') is not the expected '$EXPECTED_EMAIL'. Fix git config user.email, then retry."
  fi
fi

# 4) Never-commit patterns — the staged diff must be clean.
if [ -n "$NEVER_COMMIT_PATTERNS" ] && is_commit; then
  if git -C "$PROJECT_DIR" diff --cached 2>/dev/null | grep -qiE "$NEVER_COMMIT_PATTERNS"; then
    deny "BLOCKED: the staged diff matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list."
  fi
fi

# 5) Forbidden commands — the owner's own site rules for this run.
if [ -n "$FORBIDDEN_COMMANDS" ] && printf '%s' "$SCRUBBED" | grep -qE "$FORBIDDEN_COMMANDS"; then
  deny "BLOCKED: the command matches the owner's forbidden list for this shift. Find another way, or park the task with a note in .nightshift/parking-lot.md and keep working. Do not retry a rephrased form."
fi

exit 0
