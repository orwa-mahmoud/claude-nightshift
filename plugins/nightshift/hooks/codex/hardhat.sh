#!/usr/bin/env bash
# hardhat.sh — Codex PreToolUse guard. Same rules as Claude's hardhat; only the wire format
# differs, and that lives entirely in lib-io.sh.
#
# One zero-config rule: the host's ask-user tool is denied during an active shift — park,
# don't ask. Codex calls it request_user_input; AskUserQuestion remains a compatibility
# alias. Every other rule is shift-scoped and opt-in, read from the owner's rules file
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

HOST_DIR="$(codex_project_dir)"
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

# The emission (and its escaping) is the seam's; the guard only decides.
deny() {
  codex_emit_deny "$1"
  exit 0
}

[ -z "$LINK_ERROR" ] || deny "BLOCKED: .nightshift-link is invalid. Open the correct project task or repair the explicit link to an absolute workspace containing .nightshift/."

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
# default — ask-user tools parked so a 2:40am question cannot kill the run, every other
# tool allowed. Both Codex names use the shared AskUserQuestion rule, so the owner has one
# policy to configure across hosts. (sed backs up jq; the park rule holds without jq.)
TOOL_RULES="$(rule "$PROJECT_DIR" toolDeny "${NIGHTSHIFT_TOOL_RULES:-}")"
if ns_hardhat_tool_deny_broken; then
  deny "BLOCKED: the toolDeny rules are not a JSON object, so the tool rules cannot run. Fix .nightshift/rules.json or re-run /nightshift:setup."
fi
if [ "$TOOL" = "AskUserQuestion" ] || [ "$TOOL" = "request_user_input" ] \
  || codex_input_mentions_tool "AskUserQuestion" \
  || codex_input_mentions_tool "request_user_input"; then
  if m="$(ns_hardhat_park_reason)"; then deny "$m"; fi
  exit 0 # a permitted question is not a command; the command guards have no business with it
fi
if m="$(ns_hardhat_named_tool_reason "$TOOL")"; then deny "$m"; fi

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
if ns_hardhat_rules_targeted "$SCRUBBED"; then
  deny "BLOCKED: the rules file is the owner's — the night neither reads nor rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working."
fi

if reason="$(ns_hardhat_command_reason)"; then
  deny "$reason"
fi

exit 0
