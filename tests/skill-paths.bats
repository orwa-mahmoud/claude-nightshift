SKILLS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills"
SETUP="$SKILLS/setup/SKILL.md"
START="$SKILLS/start/SKILL.md"
STOP="$SKILLS/stop/SKILL.md"

# Shared skills are loaded unchanged by both hosts. Pin the path carriers and reject the unsafe
# host-only fallbacks; wording and line wrapping remain free to change.
@test "every skill resolves both host task roots into one workspace name" {
  for s in "$SKILLS"/*/SKILL.md; do
    grep -qF '.nightshift-link' "$s" || { echo "no linked-workspace rule: $s"; return 1; }
    grep -qF '${CLAUDE_PROJECT_DIR}' "$s" || { echo "no Claude project root: $s"; return 1; }
    grep -qF 'CODEX_PROJECT_DIR' "$s" || { echo "no Codex recovery override: $s"; return 1; }
    grep -qF 'pwd -P' "$s" || { echo "no canonical Codex launch cwd: $s"; return 1; }
    grep -qF '$TASK_ROOT' "$s" || { echo "no task-root name: $s"; return 1; }
    grep -qF '$NIGHTSHIFT_WORKSPACE' "$s" \
      || { echo "no workspace name: $s"; return 1; }
    ! grep -qF '${CLAUDE_PROJECT_DIR:-$PWD}' "$s" \
      || { echo "Claude-only cwd fallback: $s"; return 1; }
    ! grep -qF '${CODEX_PROJECT_DIR:-$PWD}' "$s" \
      || { echo "uncaptured Codex cwd fallback: $s"; return 1; }
    ! grep -qF -- '--project "$CLAUDE_PROJECT_DIR"' "$s" \
      || { echo "Claude-only runtime project: $s"; return 1; }
  done
}

# The permission mode is what a headless revival inherits. A copy written into a nested code repo
# grants the project nothing, and the shift discovers it at the first prompt of the night.
@test "setup writes the permission settings to an absolute path" {
  grep -qF '$TASK_ROOT/.claude/settings.local.json' "$SETUP"
}

@test "setup writes the rules file to the resolved workspace" {
  grep -qF '$NIGHTSHIFT_WORKSPACE/.nightshift/rules.json' "$SETUP"
}

@test "setup writes state-version on a new workspace and migrates only on confirmation" {
  grep -qF '$NIGHTSHIFT_WORKSPACE/.nightshift/state-version' "$SETUP"
  grep -qF 'runtime/migrate-state.sh' "$SETUP"
  grep -qF 'only after an explicit yes' "$SETUP"
}

@test "setup scaffolds every template to an absolute path" {
  for f in punch-list drafting-table parking-lot snag-log product-research opportunity-map; do
    grep -qF "\$NIGHTSHIFT_WORKSPACE/.nightshift/$f.md" "$SETUP" \
      || { echo "scaffold target not absolute: $f"; return 1; }
  done
}

@test "shared plugin paths resolve once through both host conventions" {
  for s in "$SKILLS"/*/SKILL.md; do
    ! grep -qF '${CLAUDE_PLUGIN_ROOT}/' "$s" \
      || { echo "Claude-only bundled path: $s"; return 1; }
    ! grep -qF '${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}' "$s" \
      || { echo "Claude-first plugin fallback: $s"; return 1; }
    ! grep -qF '${PLUGIN_ROOT:-' "$s" \
      || { echo "unresolved shell fallback in shared skill: $s"; return 1; }
  done

  for s in setup start hunt quality doctor import-issues schedule archive; do
    f="$SKILLS/$s/SKILL.md"
    grep -qF '$NIGHTSHIFT_PLUGIN_ROOT' "$f" || { echo "no neutral plugin root: $s"; return 1; }
    grep -qF '${CLAUDE_PLUGIN_ROOT}' "$f" || { echo "no Claude plugin source: $s"; return 1; }
    grep -qF '$PLUGIN_ROOT' "$f" || { echo "no Codex plugin source: $s"; return 1; }
    grep -qF "skills/$s/SKILL.md" "$f" || { echo "no attached skill path: $s"; return 1; }
  done
}

@test "runtime helpers are qualified and target the resolved workspace" {
  for s in doctor import-issues schedule archive; do
    grep -qF -- '--project "$NIGHTSHIFT_WORKSPACE"' "$SKILLS/$s/SKILL.md" \
      || { echo "runtime helper bypasses resolved workspace: $s"; return 1; }
  done

  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT/runtime/import-issues.sh' \
    "$SKILLS/hunt/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT/runtime/import-issues.sh' \
    "$SKILLS/nightshift/references/shifts/github-issue-hunt.md"
}

@test "shared references are host-neutral and skill redirects name both hosts" {
  for ref in "$SKILLS/nightshift/references"/*.md "$SKILLS/nightshift/references/shifts"/*.md; do
    ! grep -qF '/nightshift:' "$ref" \
      || { echo "host-specific command in shared reference: $ref"; return 1; }
  done

  python3 - "$SKILLS" <<'PY'
import pathlib
import re
import sys

for path in pathlib.Path(sys.argv[1]).glob("*/SKILL.md"):
    for paragraph in re.split(r"\n\s*\n", path.read_text()):
        if "/nightshift:" in paragraph and not (
            "Claude Code" in paragraph and "Codex" in paragraph
        ):
            raise SystemExit(f"unpaired host invocation: {path}")
PY
}

# git resolves its repo from the working directory, so the receipts repo is the one place a stray
# cd would init a repo inside the code tree instead of the site.
@test "setup inits the receipts repo without relying on the working directory" {
  grep -qF 'git -C "$NIGHTSHIFT_WORKSPACE/.nightshift" init' "$SETUP"
  grep -qF '`.shift-lease`' "$SETUP"
  grep -qF '`.mutex-scope`' "$SETUP"
  grep -qF '`.lease-lock.d/`' "$SETUP"
}

@test "setup refuses disposable ChatGPT scratch before writing" {
  grep -qF '/workspace/scratch/' "$SETUP"
  grep -qF 'Before creating or changing any file' "$SETUP"
  grep -qF 'create no `.nightshift/` directory' "$SETUP"
  grep -qF 'Open your project in Codex' "$SETUP"
  grep -qF 'Do not mention Claude Code' "$SETUP"
}

@test "scratch detection does not reject legitimate non-git projects" {
  grep -qF 'Do not infer “temporary” merely because the' "$SETUP"
  grep -qF 'project is not a git repository' "$SETUP"
  grep -qF 'A non-git project outside that explicit scratch path remains valid' "$SKILLS/nightshift/SKILL.md"
}

# Structural instruction contracts, not runtime E2E: pin the lifecycle words and shipped paths
# whose accidental removal would leave a scheduled or headless shift unarmed or unstoppable.
@test "start explicitly arms the shift and both host watchmen" {
  grep -qF '.nightshift/.shift-armed' "$START"
  grep -qF 'runtime/claude/watchman.sh' "$START"
  grep -qF 'runtime/codex/watchman.sh' "$START"
  grep -qF '### Bind this session' "$START"
  grep -qF '.nightshift/.shift-lease' "$START"
  grep -qF 'ns_lease_reset_stale' "$START"
  grep -qF ': nightshift-binding-probe' "$START"
  grep -qF 'jq` or `python3' "$START"
}

@test "start validates the captured Codex identity before its watchman or item work" {
  checkpoint="$(grep -n '^### Codex identity checkpoint' "$START" | cut -d: -f1)"
  watchman="$(grep -n '^## 5\. Arm the night watchman' "$START" | cut -d: -f1)"
  work="$(grep -n '^## 6\. Work' "$START" | cut -d: -f1)"
  [ -n "$checkpoint" ]
  [ "$checkpoint" -lt "$watchman" ]
  [ "$checkpoint" -lt "$work" ]
  grep -qF 'ns_codex_identity_kind' "$START"
  grep -qF ': nightshift-binding-probe' "$START"
  grep -qF 'Remove only the markers created by' "$START"
  grep -qF '.shift-armed' "$START"
  grep -qF '.shift-session' "$START"
  grep -qF 'before the watchman or item work' "$START"
}

@test "start refuses an active watchman before clearing stale lease state" {
  active="$(grep -n 'A live `.nightshift/.watchman` beside an armed list' "$START" | cut -d: -f1)"
  stale="$(grep -n 'Stand down a stale watchman before clearing its state' "$START" | cut -d: -f1)"
  clear="$(grep -n 'Clear every stale run-control marker first' "$START" | cut -d: -f1)"
  [ -n "$active" ]
  [ "$active" -lt "$stale" ]
  [ "$stale" -lt "$clear" ]
  grep -qF 'Refuse the second Start' "$START"
  grep -qF '.nightshift/.shift-lease' "$START"
}

@test "stop writes the stop-work order and disarms the watchman" {
  grep -qF '.nightshift/STOP' "$STOP"
  grep -qF '.nightshift/.watchman' "$STOP"
  grep -qi 'kill' "$STOP"
}
