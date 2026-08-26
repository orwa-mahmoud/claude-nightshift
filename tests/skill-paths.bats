SKILLS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills"
SETUP="$SKILLS/setup/SKILL.md"
START="$SKILLS/start/SKILL.md"
STOP="$SKILLS/stop/SKILL.md"
HUNT="$SKILLS/hunt/SKILL.md"
QUALITY="$SKILLS/quality/SKILL.md"
SCHEDULE="$SKILLS/schedule/SKILL.md"
DOCTOR_SH="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"

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

@test "every skill binds the Nightshift directory once after resolving the workspace" {
  for s in "$SKILLS"/*/SKILL.md; do
    grep -qF 'NS="$NIGHTSHIFT_WORKSPACE/.nightshift"' "$s" \
      || { echo "no POSIX NS bind: $s"; return 1; }
    grep -qF "Join-Path \$NIGHTSHIFT_WORKSPACE '.nightshift'" "$s" \
      || { echo "no Windows NS bind: $s"; return 1; }
  done
}

@test "setup writes the rules file to the bound Nightshift directory" {
  grep -qF '$NS/rules.json' "$SETUP"
}

@test "setup writes state-version on a new workspace and migrates only on confirmation" {
  grep -qF '$NS/state-version' "$SETUP"
  grep -qF 'runtime/migrate-state.sh' "$SETUP"
  grep -qF 'only after an explicit yes' "$SETUP"
}

@test "setup scaffolds every template into the bound Nightshift directory" {
  for f in punch-list drafting-table parking-lot snag-log product-research opportunity-map; do
    grep -qF "\$NS/$f.md" "$SETUP" \
      || { echo "scaffold target not bound: $f"; return 1; }
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
  grep -qF 'git -C "$NS" init' "$SETUP"
  grep -qF '`.shift-lease`' "$SETUP"
  grep -qF '`.mutex-scope`' "$SETUP"
  grep -qF '`.lease-lock.d/`' "$SETUP"
}

@test "setup refuses disposable ChatGPT scratch before writing" {
  grep -qF '/workspace/scratch/' "$SETUP"
  grep -qF 'Before creating or changing any file' "$SETUP"
  grep -qF 'create no `$NS/` directory' "$SETUP"
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
  grep -qF '$NS/.shift-armed' "$START"
  grep -qF 'runtime/claude/watchman.sh' "$START"
  grep -qF 'runtime/codex/watchman.sh' "$START"
  grep -qF '### Bind this session' "$START"
  grep -qF '$NS/.shift-lease' "$START"
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
  active="$(grep -n 'A live `$NS/.watchman` beside an armed list' "$START" | cut -d: -f1)"
  stale="$(grep -n 'Stand down a stale watchman before clearing its state' "$START" | cut -d: -f1)"
  clear="$(grep -n 'Clear every stale run-control marker first' "$START" | cut -d: -f1)"
  [ -n "$active" ]
  [ "$active" -lt "$stale" ]
  [ "$stale" -lt "$clear" ]
  grep -qF 'Refuse the second Start' "$START"
  grep -qF '$NS/.shift-lease' "$START"
}

@test "stop writes the stop-work order and disarms the watchman" {
  grep -qF '$NS/STOP' "$STOP"
  grep -qF '$NS/.watchman' "$STOP"
  grep -qi 'kill' "$STOP"
}

@test "stop panic commands use the bound Nightshift directory, not the working directory" {
  grep -qF 'touch "$NS/STOP"' "$STOP"
  grep -qF 'New-Item -ItemType File -Force "$NS\STOP"' "$STOP"
  ! grep -qF 'New-Item -ItemType File -Force .nightshift\STOP' "$STOP"
  ! grep -qF 'touch .nightshift/STOP' "$STOP"
}

@test "no skill uses a cwd-relative Windows STOP path" {
  if grep -R --include='SKILL.md' -F 'New-Item -ItemType File -Force .nightshift\STOP' "$SKILLS"; then
    echo "cwd-relative Windows STOP path in a skill" >&2
    return 1
  fi
}

@test "start STOP lever uses the bound Nightshift directory on both platforms" {
  grep -qF 'touch "$NS/STOP"' "$START"
  grep -qF 'New-Item -ItemType File -Force "$NS\STOP"' "$START"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT/lib/lib.sh' "$START"
}

@test "hunt and quality arm with the same bound pair as start" {
  for f in "$START" "$HUNT" "$QUALITY"; do
    grep -qF 'touch "$NS/.shift-armed"' "$f" \
      || { echo "missing POSIX arm: $f"; return 1; }
    grep -qF 'New-Item -ItemType File -Force "$NS\.shift-armed"' "$f" \
      || { echo "missing Windows arm: $f"; return 1; }
  done
}

@test "start and schedule inspect Claude settings at the task root" {
  grep -qF '$TASK_ROOT/.claude/settings.local.json' "$START"
  grep -qF '$TASK_ROOT/.claude/settings.json' "$START"
  grep -qF '$TASK_ROOT/.claude/settings.local.json' "$SCHEDULE"
  grep -qF '$TASK_ROOT/.claude/settings.json' "$SCHEDULE"
}

@test "setup writes gitignore and lists profiles on resolved roots" {
  grep -qF '$NIGHTSHIFT_WORKSPACE/.gitignore' "$SETUP"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT/skills/nightshift/references/profiles/' "$SETUP"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT/skills/nightshift/references/nightshift-rules.schema.json' "$SETUP"
  grep -qF 'docs/knobs.md' "$SETUP"
}

@test "schedule names the Windows generator from the plugin root" {
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\schedule.ps1' "$SCHEDULE"
  ! grep -qF '`runtime\windows\schedule.ps1`' "$SCHEDULE"
  grep -qF 'parked Hunt work order' \
    "$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/schedule.ps1"
  grep -qF 'drafting-table item' \
    "$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/schedule.ps1"
}

@test "Windows schedule generate names parked work on an empty list" {
  ps1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/schedule.ps1"
  grep -qF 'Note: the punch list has no open items' "$ps1"
  grep -qF 'Parked Hunt work orders:' "$ps1"
  grep -qF 'Drafting-table items:' "$ps1"
  awk '
    /if \(\$Preflight\)/ { pre=NR }
    /Note: the punch list has no open items/ { note=NR }
    /"Scheduled start for/ { start=NR }
    END { exit !(pre && note && start && pre < note && note < start) }
  ' "$ps1"
}

@test "no skill executable uses a cwd-relative marker or plugin helper" {
  if grep -R --include='SKILL.md' -E '`touch \.nightshift/' "$SKILLS"; then
    echo "cwd-relative POSIX nightshift command in a skill" >&2
    return 1
  fi
  if grep -R --include='SKILL.md' -F 'New-Item -ItemType File -Force .nightshift' "$SKILLS"; then
    echo "cwd-relative Windows nightshift command in a skill" >&2
    return 1
  fi
  if grep -R --include='SKILL.md' -F '`runtime\windows' "$SKILLS"; then
    echo "cwd-relative Windows runtime helper in a skill" >&2
    return 1
  fi
}

@test "doctor actions name helpers beside the inspector, not from cwd" {
  ! grep -qF 'using runtime/' "$DOCTOR_SH"
  ! grep -qF 'with runtime/' "$DOCTOR_SH"
  grep -qF '$_here/link-workspace.sh' "$DOCTOR_SH"
  grep -qF '$_here/migrate-state.sh' "$DOCTOR_SH"
  grep -qF '$_here/export-support.sh' "$DOCTOR_SH"
}

@test "punch-list template STOP commands use the bound Nightshift directory" {
  tpl="$SKILLS/nightshift/references/punch-list-template.md"
  grep -qF 'touch "$NS/STOP"' "$tpl"
  grep -qF 'New-Item -ItemType File -Force "$NS\STOP"' "$tpl"
  ! grep -qF 'touch .nightshift/STOP' "$tpl"
  ! grep -qF 'New-Item -ItemType File -Force .nightshift\STOP' "$tpl"
}

@test "native Windows skills pair runtime helpers instead of calling .sh" {
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\doctor.ps1' "$SKILLS/doctor/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\doctor.ps1' "$SKILLS/status/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\import-issues.ps1' "$SKILLS/import-issues/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\import-issues.ps1' "$HUNT"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\retain-history.ps1' "$SKILLS/archive/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\migrate-state.ps1' "$SETUP"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\migrate-state.ps1' "$START"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\migrate-state.ps1' "$SKILLS/doctor/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\apply-profile.ps1' "$SETUP"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\apply-profile.ps1' "$SKILLS/doctor/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\export-support.ps1' "$SKILLS/doctor/SKILL.md"
  grep -qF '$NIGHTSHIFT_PLUGIN_ROOT\runtime\windows\import-issues.ps1' \
    "$SKILLS/nightshift/references/shifts/github-issue-hunt.md"
}

@test "doctor Windows actions name helpers beside the inspector" {
  DOCTOR_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/doctor.ps1"
  grep -qF "Join-Path \$here 'migrate-state.ps1'" "$DOCTOR_PS1"
  grep -qF "Join-Path \$here 'export-support.ps1'" "$DOCTOR_PS1"
  grep -qF "Join-Path \$here 'link-workspace.ps1'" "$DOCTOR_PS1"
  grep -qF 'leftover Shift contract and Gates' "$DOCTOR_PS1"
  grep -qF 'pending Hunt work orders=' "$DOCTOR_PS1"
  grep -qF 'staged drafting-table items=' "$DOCTOR_PS1"
}

@test "setup substitutes workspace and NS tokens when copying owner files" {
  grep -qF 'substitute the resolved absolute workspace path for `$NIGHTSHIFT_WORKSPACE`' "$SETUP"
  grep -qF 'bound Nightshift directory for `$NS`' "$SETUP"
  grep -qF 'Never write those tokens into `rules.json`' "$SETUP"
}

@test "catalog prose uses Nightshift filenames, not a workspace prefix" {
  for f in "$SKILLS/nightshift/references"/catalog-recipe.md \
           "$SKILLS/nightshift/references"/execution-modes.md \
           "$SKILLS/nightshift/references"/gates-catalog.md \
           "$SKILLS/nightshift/references"/shift-catalog.md \
           "$SKILLS/nightshift/references/shifts"/*.md; do
    ! grep -qF '$NIGHTSHIFT_WORKSPACE/.nightshift/' "$f" \
      || { echo "catalog still prefixes workspace: $f"; return 1; }
  done
}

@test "skills do not repeat the workspace prefix after the NS bind" {
  python3 - "$SKILLS" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
bind = 'NS="$NIGHTSHIFT_WORKSPACE/.nightshift"'
for path in sorted(root.glob("*/SKILL.md")):
    text = path.read_text().replace(bind, "")
    if "$NIGHTSHIFT_WORKSPACE/.nightshift/" in text:
        raise SystemExit(f"repeated workspace prefix: {path}")
    if r"$NIGHTSHIFT_WORKSPACE\.nightshift" in text:
        raise SystemExit(f"repeated Windows workspace prefix: {path}")
PY
}

@test "Windows runtime helpers do not add a second toolchain" {
  if grep -RE 'brew |npm install|pip install|python3|jq is required' \
    "$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows"; then
    echo "Windows helper depends on a toolchain Nightshift does not ship" >&2
    return 1
  fi
}

@test "rules template keeps relative nightshift paths for owner editing" {
  rules="$SKILLS/nightshift/references/nightshift-rules-template.json"
  grep -qF '.nightshift/punch-list.md' "$rules"
  grep -qF '.nightshift/STOP' "$rules"
  ! grep -qF '$NIGHTSHIFT_WORKSPACE' "$rules"
}
