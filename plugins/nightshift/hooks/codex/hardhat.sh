#!/usr/bin/env bash
# hardhat.sh — Codex PreToolUse guard. Same rules as Claude's hardhat; only the wire format
# differs, and that lives entirely in lib-io.sh.
#
# Every rule is shift-scoped and read from the owner's .nightshift/rules.json. toolDeny
# uses exact Codex tool names: a non-empty message denies, an empty message allows, and
# an unlisted optional tool is allowed. request_user_input and its AskUserQuestion
# compatibility alias are explicit entries so neither gets a hidden fallback:
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
STATE_KIND="$(ns_state_kind "$PROJECT_DIR")"
case "$STATE_KIND" in
  malformed | future)
    deny "BLOCKED: $(ns_state_refuse_message "$STATE_KIND")"
    ;;
esac

# A commit message must not read as the command it mentions, so blank the message argument
# before matching. Only that argument: scrubbing every quoted span would also hide a genuinely
# forbidden command that happens to be quoted, such as sh -c "git push".
SCRUBBED="$(ns_hardhat_scrub "$CMD")"
LEASE_COMMAND="$CMD"
case "$TOOL" in Bash | PowerShell) LEASE_COMMAND="$SCRUBBED" ;; esac
LEASE_TOKEN="${NIGHTSHIFT_LEASE_TOKEN:-}"
LEASE_GENERATION="${NIGHTSHIFT_LEASE_GENERATION:-}"

# Every remaining rule is shift-scoped: inert unless a shift is truly active. A stop-work order
# is a request, not the ending — the agent keeps working until its next stop attempt, which is
# exactly when the site rules still matter. The gate writes ENDED when it actually releases, and
# that is what stands these rules down.
if ! ns_hardhat_active; then
  if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
    if [ ! -f "$NS/.shift-armed" ] || [ ! -f "$PUNCH" ] || [ -f "$ENDED" ] \
      || ! ns_lease_token_matches "$NS" codex "$LEASE_TOKEN" "$LEASE_GENERATION"; then
      deny "BLOCKED: this recovered worker no longer owns an active shift. Do not continue after clock-out."
    fi
  fi
  exit 0
fi

# Process ownership is runtime state for the whole site, not agent-editable state. This narrow
# protection applies even to helper conversations; all of their ordinary project work stays free.
if ns_hardhat_payload_targets_lease "$TOOL" "$CODEX_RAW" "$LEASE_COMMAND"; then
  deny "BLOCKED: the process lease is runtime-owned, as is its mutex identity. Do not read, delete, or rewrite either file; issue STOP from another session if ownership must be reset."
fi

# A recovery can be forced to start fresh before any session id exists. During that short unbound
# window, only the child carrying the watchman's capability may make the first observed call.
BOUND_BEFORE="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
if [ -z "$BOUND_BEFORE" ] && ns_lease_load "$NS" && [ -n "$NS_LEASE_TOKEN" ]; then
  if [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ] \
    || ! ns_lease_token_matches "$NS" codex "$LEASE_TOKEN" "$LEASE_GENERATION"; then
    deny "BLOCKED: this shift is being recovered before its new conversation is bound. Reopen the recorded conversation and retry after recovery."
  fi
fi

# The conversation record preserves continuity; the lease names the process generation allowed
# to act on it. Codex offers no interactive process ancestry this hook can vouch for, so the
# initial pid and start-time lines stay empty. Watchman children carry a unique lease token and
# generation, which fences an older Desktop or terminal process using the same conversation id.
record_shift_session() {
  ns_session_claim "$NS" "$SID" "${TPATH:-}" "" "" codex || true
}
replace_shift_session() {
  local transcript tmp
  transcript="${TPATH:-$(sed -n 2p "$NS/.shift-session" 2>/dev/null)}"
  tmp="$NS/.shift-session.tmp.$$.$RANDOM"
  (umask 077; printf '%s\n%s\n\n\ncodex\n' "$SID" "$transcript" >"$tmp") \
    && mv -f "$tmp" "$NS/.shift-session"
}
# The guards are the shift's, so they arrive with the shift. Nightshift Start writes
# .shift-armed; before it exists this is an ordinary session in an ordinary project and nothing
# here applies to it. Only the original binding-tool set may make the first claim; the catch-all
# matcher must not let a passive helper read or MCP call steal the shift.
if [ ! -f "$NS/.shift-session" ] && [ -n "${SID:-}" ]; then
  case "$TOOL" in
    Bash | AskUserQuestion | request_user_input | apply_patch | Edit | Write) record_shift_session ;;
  esac
fi

# The site rules govern the shift's own session; another conversation in the same project works
# untouched — its questions, commits, and commands are the owner's business, not the night's.
# A marked revival must present the exact capability that its watchman wrote before spawning.
REC="$(sed -n 1p "$NS/.shift-session" 2>/dev/null)"
if [ "${NIGHTSHIFT_REVIVAL:-}" = "1" ]; then
  if ! ns_lease_token_matches "$NS" codex "$LEASE_TOKEN" "$LEASE_GENERATION"; then
    deny "BLOCKED: this recovered worker no longer owns the shift. Reopen the recorded conversation instead of continuing an older process."
  fi
  if [ -n "${SID:-}" ]; then
    if [ -z "$NS_LEASE_SID" ]; then
      ns_lease_rebind_session "$NS" "$SID" codex "$LEASE_TOKEN" "$LEASE_GENERATION" \
        || deny "BLOCKED: the shift process lease could not bind the recovered conversation. Issue STOP from another session, then run Start again."
    fi
    if [ "$REC" != "$SID" ]; then
      replace_shift_session \
        || deny "BLOCKED: the recovered conversation could not update .shift-session. Issue STOP from another session, then run Start again."
    fi
    REC="$SID"
  fi
fi

# Start's distinctive probe is also its compare-and-set result. A losing concurrent Start is
# denied here instead of silently becoming an unrestricted helper after another session won.
if ns_hardhat_binding_probe "$TOOL" "$CMD"; then
  if [ -z "${SID:-}" ] || [ -z "$REC" ]; then
    deny "BLOCKED: Start could not bind this session atomically. Issue STOP, inspect with Doctor, and retry Start."
  fi
  if [ "$SID" != "$REC" ]; then
    deny "BLOCKED: another session already owns this shift. Reopen that conversation or issue STOP before running Start again."
  fi
fi

LEASE_SCOPE=""
if ns_lease_valid "$NS"; then LEASE_SCOPE="$NS_LEASE_SID"; fi
if [ -n "$REC" ] && [ -n "${SID:-}" ] && [ "$SID" != "$REC" ] \
  && [ "$SID" != "$LEASE_SCOPE" ] && [ "${NIGHTSHIFT_REVIVAL:-}" != "1" ]; then
  exit 0
fi

if [ -n "$REC" ]; then
  CHECK_SID="${SID:-$REC}"
  if [ ! -e "$NS/.shift-lease" ] && [ ! -L "$NS/.shift-lease" ]; then
    ns_lease_claim_initial "$NS" "$REC" codex "" "" \
      || deny "BLOCKED: the shift process lease could not be created. Issue STOP from another session, then run Start again."
  fi
  if ! ns_lease_allows "$NS" "$CHECK_SID" codex "" "" "$LEASE_TOKEN" "$LEASE_GENERATION"; then
    deny "BLOCKED: this shift continued in a recovered process. Reopen the recorded conversation before using tools here."
  fi
fi

# Tool rules use the canonical tool_name from this host. The catch-all manifest sends every
# observable PreToolUse call here; hosted tools that Codex does not expose remain outside it.
TOOL_RULES="$(ns_tool_rules "$PROJECT_DIR" "${NIGHTSHIFT_TOOL_RULES:-}")"
if ns_hardhat_tool_deny_broken; then
  if [ "$TOOL_RULES" = "__nightshift_tool_rules_parser_missing__" ]; then
    deny "BLOCKED: toolDeny cannot be read exactly because neither jq nor python3 is available. Install one parser before running an armed shift."
  fi
  deny "BLOCKED: the toolDeny rules are not a JSON object, so the tool rules cannot run. Fix .nightshift/rules.json or run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex)."
fi

# The active agent never inspects or changes the owner's rules through any observable tool.
# Inspect target-bearing arguments and patch headers, not unrelated prose in a payload.
if ns_hardhat_payload_targets_rules "$TOOL" "$CODEX_RAW" "$CMD"; then
  deny "BLOCKED: the rules file is the owner's — the night neither reads nor rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working."
fi

if [ "$TOOL" = "request_user_input" ] \
  || { [ -z "$TOOL" ] && codex_input_mentions_tool "request_user_input"; }; then
  if m="$(ns_hardhat_required_tool_deny_reason request_user_input)"; then deny "$m"; fi
  exit 0 # a permitted question is not a command; the command guards have no business with it
fi
if [ "$TOOL" = "AskUserQuestion" ] \
  || { [ -z "$TOOL" ] && codex_input_mentions_tool "AskUserQuestion"; }; then
  if m="$(ns_hardhat_required_tool_deny_reason AskUserQuestion)"; then deny "$m"; fi
  exit 0 # a permitted question is not a command; the command guards have no business with it
fi
if m="$(ns_hardhat_tool_deny_reason "$TOOL")"; then deny "$m"; fi

if [ "$TOOL" = "Bash" ]; then
  if reason="$(ns_hardhat_command_reason)"; then
    deny "$reason"
  fi
fi

exit 0
