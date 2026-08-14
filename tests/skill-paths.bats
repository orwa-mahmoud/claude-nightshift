SKILLS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills"
SETUP="$SKILLS/setup/SKILL.md"
START="$SKILLS/start/SKILL.md"
STOP="$SKILLS/stop/SKILL.md"

# A skill's paths resolve against the shell's working directory, which persists between Bash calls
# and drifts into the code repo the moment a gate, a build, or stack detection runs from inside it.
# On the recommended layout — code repo a level below the project root — a bare relative path then
# writes into the repo instead of the site. Every skill has to say so; one that doesn't is the next
# misplaced settings file.
@test "every skill resolves explicit linked workspaces without searching" {
  for s in "$SKILLS"/*/SKILL.md; do
    grep -qF '.nightshift-link' "$s" || { echo "no linked-workspace rule: $s"; return 1; }
    grep -qF 'Never search' "$s" || { echo "no no-search rule: $s"; return 1; }
  done
}

@test "every skill names the working directory as the reason" {
  for s in "$SKILLS"/*/SKILL.md; do
    grep -qF "working directory persists between Bash calls" "$s" \
      || { echo "no cwd caveat: $s"; return 1; }
  done
}

# The permission mode is what a headless revival inherits. A copy written into a nested code repo
# grants the project nothing, and the shift discovers it at the first prompt of the night.
@test "setup writes the permission settings to an absolute path" {
  grep -qF '$CLAUDE_PROJECT_DIR/.claude/settings.local.json' "$SETUP"
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

# git resolves its repo from the working directory, so the receipts repo is the one place a stray
# cd would init a repo inside the code tree instead of the site.
@test "setup inits the receipts repo without relying on the working directory" {
  grep -qF 'git -C "$NIGHTSHIFT_WORKSPACE/.nightshift" init' "$SETUP"
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
}

@test "start validates the captured Codex identity before its watchman or item work" {
  checkpoint="$(grep -n '^### Codex identity checkpoint' "$START" | cut -d: -f1)"
  watchman="$(grep -n '^## 5\. Arm the night watchman' "$START" | cut -d: -f1)"
  work="$(grep -n '^## 6\. Work' "$START" | cut -d: -f1)"
  [ -n "$checkpoint" ]
  [ "$checkpoint" -lt "$watchman" ]
  [ "$checkpoint" -lt "$work" ]
  grep -qF 'ns_codex_identity_kind' "$START"
  grep -qF 'pwd' "$START"
  grep -qF 'Remove only the markers created by' "$START"
  grep -qF '.shift-armed' "$START"
  grep -qF '.shift-session' "$START"
  grep -qF 'stop before the watchman or item work' "$START"
}

@test "stop writes the stop-work order and disarms the watchman" {
  grep -qF '.nightshift/STOP' "$STOP"
  grep -qF '.nightshift/.watchman' "$STOP"
  grep -qi 'kill' "$STOP"
}
