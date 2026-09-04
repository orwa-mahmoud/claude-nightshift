#!/usr/bin/env bats
# Quality workflow — skill writes the receipt. Pipeline wrapper removed.

ROOT="$BATS_TEST_DIRNAME/.."
QUALITY_SKILL="$ROOT/plugins/nightshift/skills/quality/SKILL.md"
CLEAR="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/clear-quality-debt.md"
TEMPLATES="$ROOT/plugins/nightshift/skills/nightshift/references/receipt-templates.md"

@test "quality workflow and scan wrappers are gone" {
  [ ! -e "$ROOT/plugins/nightshift/runtime/quality-workflow.sh" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/quality-workflow.py" ]
  [ ! -e "$ROOT/plugins/nightshift/runtime/quality-scan.sh" ]
}

@test "Quality skill does not require the workflow helpers" {
  ! grep -qF 'runtime/quality-workflow.sh' "$QUALITY_SKILL"
  ! grep -qF 'runtime/quality-scan.sh' "$QUALITY_SKILL"
  ! grep -qF 'quality-workflow' "$QUALITY_SKILL"
  ! grep -qF 'quality-scan' "$QUALITY_SKILL"
  ! grep -qF 'compose-discovery' "$QUALITY_SKILL"
  ! grep -qF 'python3' "$QUALITY_SKILL"
  grep -qF "the project's own tools" "$QUALITY_SKILL"
  grep -qF 'unavailable' "$QUALITY_SKILL"
}

@test "receipt templates forbid the quality pipeline" {
  grep -qF 'quality-workflow.sh' "$TEMPLATES"
  grep -qF 'quality-scan.sh' "$TEMPLATES"
}

@test "clear-quality-debt contract mentions evidence-ranked workflow" {
  grep -qi 'evidence' "$CLEAR"
  grep -qi 'baseline' "$CLEAR"
  grep -qi 'dedupe' "$CLEAR"
}
