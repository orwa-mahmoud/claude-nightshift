#!/usr/bin/env bats
# A skill that names a helper which no longer ships is worse than a skill that says nothing: the
# model looks for the file, fails, and improvises. Every backticked path in the composition and
# housekeeping skills must resolve inside the shipped plugin.

ROOT="$BATS_TEST_DIRNAME/.."
PLUGIN="$ROOT/plugins/nightshift"
SKILLS="$PLUGIN/skills"

# Files under .nightshift/ that the owner's workspace holds, not the plugin.
STATE_FILES="punch-list.md drafting-table.md parking-lot.md work-orders.md snag-log.md
shift-log.md product-research.md opportunity-map.md shipped.md"

# Every path-shaped word inside a backtick span, unquoted and unpunctuated.
backticked_paths() {
  grep -o '`[^`]*`' "$1" \
    | tr -d '`' \
    | tr ' \t' '\n\n' \
    | sed -e 's/^[("'"'"'&]*//' -e 's/[)",;:'"'"']*$//' -e 's/\.$//' \
    | grep -E '\.(sh|ps1|jq|psm1|py|md)$' || true
}

# 0 when the reference resolves (or is not the plugin's to resolve), 1 when it is a dead pointer.
resolves() {
  local ref="$1" rel base
  case "$ref" in
    *'$NIGHTSHIFT_PLUGIN_ROOT'*)
      rel="${ref#*NIGHTSHIFT_PLUGIN_ROOT}"
      rel="$(printf '%s' "$rel" | tr '\\' '/')"
      [ -e "$PLUGIN/${rel#/}" ] && return 0
      return 1
      ;;
    skills/*|runtime/*|lib/*|hooks/*)
      [ -e "$PLUGIN/$ref" ] && return 0
      return 1
      ;;
    */*|*'$'*)
      # a workspace path, or an expression this test does not own
      return 0
      ;;
  esac

  base="$ref"
  case "$base" in
    *.md)
      for s in $STATE_FILES; do
        [ "$base" = "$s" ] && return 0
      done
      [ -n "$(find "$SKILLS" -name "$base" -print -quit)" ] && return 0
      return 1
      ;;
    *)
      [ -n "$(find "$PLUGIN" -name "$base" -print -quit)" ] && return 0
      return 1
      ;;
  esac
}

owned_skills() {
  for s in hunt quality nightshift archive import-issues schedule stop reset purge; do
    printf '%s\n' "$SKILLS/$s/SKILL.md"
  done
  printf '%s\n' "$SKILLS/nightshift/references/execution-modes.md"
  printf '%s\n' "$SKILLS/nightshift/references/shift-catalog.md"
}

@test "every backticked path in the composition and housekeeping skills exists" {
  local dead=""
  while read -r f; do
    [ -f "$f" ] || { echo "missing skill file: $f"; return 1; }
    while read -r ref; do
      [ -n "$ref" ] || continue
      resolves "$ref" || dead="$dead
  $(basename "$(dirname "$f")")/$(basename "$f"): $ref"
    done < <(backticked_paths "$f")
  done < <(owned_skills)

  [ -z "$dead" ] || { echo "dead references:$dead"; return 1; }
}

# The removed planners, previews, and pipeline wrappers must not come back as prose.
@test "no composition or housekeeping skill names a removed helper" {
  local removed="shift-planner.sh shift-planner.ps1 shift-planner.py
shift-preview.sh shift-preview.ps1 shift-preview.py plan-learning.sh plan-learning.py
quality-workflow.sh quality-workflow.py quality-scan.sh compose-discovery
history-context.sh history-context.py evidence.py"
  while read -r f; do
    for helper in $removed; do
      ! grep -qF "$helper" "$f" \
        || { echo "$f still names $helper"; return 1; }
    done
  done < <(owned_skills)
}

# The reference is loaded by name from both composition skills; a rename there is silent.
@test "the shared execution-modes reference is reachable from both composition skills" {
  for s in hunt quality; do
    grep -qF 'skills/nightshift/references/execution-modes.md' "$SKILLS/$s/SKILL.md" \
      || { echo "$s does not name the shared reference"; return 1; }
  done
  [ -f "$SKILLS/nightshift/references/execution-modes.md" ]
}
