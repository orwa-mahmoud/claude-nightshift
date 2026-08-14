#!/usr/bin/env bash
# hardhat.sh — PreToolUse guard. Mechanical safety, zero-config core.
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
. "$_here/../lib/lib.sh" # pure-bash path: no dirname, so a hostile PATH cannot unsource the helpers
# shellcheck source=plugins/nightshift/hooks/shared/hardhat-core.sh
. "$_here/shared/hardhat-core.sh"

INPUT="$(cat)"
HOST_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
LINK_ERROR=""
PROJECT_DIR="$(ns_workspace_root "$HOST_DIR" 2>/dev/null)" || LINK_ERROR=1
NS="$PROJECT_DIR/.nightshift"
PUNCH="$NS/punch-list.md"
ENDED="$NS/.ended"

# One copy: the rules file is the config; an env var of the matching name is a session-start
# override (the test suite's lever), never a second copy.
PROTECTED_DIRS="$(rule "$PROJECT_DIR" protectedDirs "${NIGHTSHIFT_PROTECTED_DIRS:-}")"
EXPECTED_EMAIL="$(rule "$PROJECT_DIR" expectedEmail "${NIGHTSHIFT_EXPECTED_EMAIL:-}")"
NEVER_COMMIT_PATTERNS="$(rule "$PROJECT_DIR" neverCommitPatterns "${NIGHTSHIFT_NEVER_COMMIT_PATTERNS:-}")"
FORBIDDEN_COMMANDS="$(rule "$PROJECT_DIR" forbiddenCommands "${NIGHTSHIFT_FORBIDDEN_COMMANDS:-}")"

# Reasons interpolate owner config and git output; escape them so a stray quote or
# backslash can never break the JSON and void the deny.
deny() {
  reason="$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

[ -z "$LINK_ERROR" ] || deny "BLOCKED: .nightshift-link is invalid. Open the correct project task or repair the explicit link to an absolute workspace containing .nightshift/."

# Extract tool + command. jq preferred; the raw payload is the fallback so a missing jq
# can never silently disable the guard.
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  TPATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
else
  # No jq: pull the fields out of the raw JSON with sed so the guard still works. Extract the
  # command value rather than falling back to the whole payload — the quote-scrub below would
  # otherwise strip the command string itself and a push would slip through.
  TOOL="$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
  CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  TPATH="$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[ -n "$CMD" ] || CMD="$INPUT"

# A commit message must not read as the command it mentions, so blank the message argument
# before matching. Only that argument: scrubbing every quoted span would also hide a genuinely
# forbidden command that happens to be quoted, such as sh -c "git push".
SCRUBBED="$(ns_hardhat_scrub "$CMD")"

# Every remaining rule is shift-scoped: inert unless a shift is truly active. A stop-work order
# is a request, not the ending — the agent keeps working until its next stop attempt, which is
# exactly when the site rules still matter. The gate writes ENDED when it actually releases, and
# that is what stands these rules down.
if ! ns_hardhat_active; then
  exit 0
fi

# The shift records its own identity: the first session to work under an active shift writes its
# session id, transcript path, and best-effort process identity — the claude ancestor's pid and
# start time, a pair no pid reuse can counterfeit. The watchman reads THIS session's transcript
# for the Esc tell, checks THIS process for life, and revives THIS conversation by id — never a
# guess at "the newest". The exclusive create makes first-writer-wins mechanical: two racing
# first sessions cannot interleave, one claim lands whole. Losing that race is the design.
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
  (set -C; printf '%s\n%s\n%s\n%s\nclaude\n' "$SID" "${TPATH:-}" "$pid" "$start" >"$NS/.shift-session") 2>/dev/null || true
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
# is the denial Claude reads; an empty message lifts the rule; an absent key means the
# default — AskUserQuestion parked so a 2:40am question cannot kill the run, every other
# tool allowed. (sed backs up the jq path; the park rule holds even without jq.)
TOOL_RULES="$(rule "$PROJECT_DIR" toolDeny "${NIGHTSHIFT_TOOL_RULES:-}")"
if ns_hardhat_tool_deny_broken; then
  deny "BLOCKED: the toolDeny rules are not a JSON object, so the tool rules cannot run. Fix .nightshift/rules.json or re-run /nightshift:setup."
fi
if [ "$TOOL" = "AskUserQuestion" ] || printf '%s' "$INPUT" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"AskUserQuestion"'; then
  if m="$(ns_hardhat_park_reason)"; then deny "$m"; fi
  exit 0 # a permitted question is not a command; the command guards have no business with it
fi
if m="$(ns_hardhat_named_tool_reason "$TOOL")"; then deny "$m"; fi

# The rules file is the owner's leash on the night, and the night never rewrites it: during a
# shift, deny any file tool aimed at the rules file and any Bash command that names it. An
# owner's mid-shift edit is the owner's hand — it reads from the very next tool call.
# Pattern-match honesty, like every guard here.
if command -v jq >/dev/null 2>&1; then
  FILEPATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
else
  FILEPATH="$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
case "$TOOL" in
  Edit | Write | MultiEdit | NotebookEdit)
    case "$FILEPATH" in
      */.nightshift/rules.json | *nightshift-rules.json) deny "BLOCKED: the rules file is the owner's — the night never rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working; the owner's edit applies from the next tool call." ;;
    esac
    exit 0 # a file tool is not a command; the command guards have no business with it
    ;;
esac
if ns_hardhat_rules_targeted "$SCRUBBED"; then
  deny "BLOCKED: the rules file is the owner's — the night neither reads nor rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working."
fi

if reason="$(ns_hardhat_command_reason)"; then
  deny "$reason"
fi

exit 0
