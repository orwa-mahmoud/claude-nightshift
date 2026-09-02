#!/usr/bin/env bats
# Specialist accessibility and localization recipes: admission, fallbacks, and fixture matrices.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PWPROV="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/recipes/specialist/a11y-l10n"
A11Y_RECIPE="$REGISTRY/javascript-typescript/accessibility.json"
L10N_RECIPE="$REGISTRY/javascript-typescript/localization.json"
HONESTY='automated checks; not WCAG or user conformance'

load helpers

provision() {
  if [ -f "$PROVISION" ]; then
    bash "$PROVISION" "$@"
  else
    python3 "$PROVISION_PY" "$@"
  fi
}

enable_auto_add() {
  printf 'repository\n' >"$1/.nightshift/work-mode"
  printf '%s\n' "$1" >"$1/.nightshift/work-target"
  jq -n '{
    schemaVersion: 1, shiftId: "9f2c40ab77e51d63", createdAt: "2026-01-01T00:00:00Z",
    source: "start-defaults", deadlineEpoch: null, verificationLevel: "none",
    toolingPolicy: "auto-add", allowances: []
  }' >"$1/.nightshift/shift-policy.json"
}

grant_unattended() {
  mkdir -p "$1/.claude"
  jq -n '{permissions:{defaultMode:"bypassPermissions"}}' >"$1/.claude/settings.local.json"
}

setup_fake_npm() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-npm-bin"
  mkdir -p "$FAKE_BIN"
  export PATH="$FAKE_BIN:$PATH"
}

@test "specialist a11y and l10n recipes carry admission evidence and object enabledShifts" {
  for recipe in "$A11Y_RECIPE" "$L10N_RECIPE"; do
    jq -e '.admission.contract and .admission.fixture and .admission.demand' "$recipe" >/dev/null \
      || { echo "$recipe missing admission block"; return 1; }
    jq -e '.enabledShifts | all(type == "object" and .contract and .fallback)' "$recipe" >/dev/null \
      || { echo "$recipe enabledShifts must use object form"; return 1; }
    jq -e --arg f '.maintenanceFields[]?' "$SCHEMA" >/dev/null 2>&1 || true
    for field in lastVerified upstream maintenance; do
      jq -e --arg f "$field" 'has($f)' "$recipe" >/dev/null \
        || { echo "$recipe missing maintenance $field"; return 1; }
    done
  done
}

@test "accessibility recipe fallback carries the WCAG honesty disclaimer verbatim" {
  jq -e --arg h "$HONESTY" '
    ([.enabledShifts[].fallback] + [.permissionRequirements[]] | join("\n")) | contains($h)
  ' "$A11Y_RECIPE" >/dev/null
}

@test "accessibility admission names accessibility-repair and the lane fixture" {
  jq -e '
    .admission.contract == "accessibility-repair"
    and (.admission.fixture | test("tests/fixtures/recipes/specialist/a11y-l10n/"))
    and (.admission.demand | test("accessibility-repair.md|evals/README.md"))
  ' "$A11Y_RECIPE" >/dev/null
}

@test "localization admission names localization-parity and the lane fixture" {
  jq -e '
    .admission.contract == "localization-parity"
    and (.admission.fixture | test("tests/fixtures/recipes/specialist/a11y-l10n/"))
    and (.admission.demand | test("localization-parity.md|evals/README.md"))
  ' "$L10N_RECIPE" >/dev/null
}

@test "review-first plan for accessibility refuses apply policy" {
  p="$(new_project rs-a11y-plan)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-npm-a11y
  enable_auto_add "$p"
  jq '.toolingPolicy = "review-missing"' "$p/.nightshift/shift-policy.json" >"$p/.nightshift/shift-policy.tmp"
  mv "$p/.nightshift/shift-policy.tmp" "$p/.nightshift/shift-policy.json"
  run provision --project "$p" --recipe "$A11Y_RECIPE" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refused == true and .reason == "policy-not-auto-add"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilityId == "accessibility"' >/dev/null
}

@test "accessibility apply provisions through the fixture npm manager" {
  setup_fake_npm
  p="$(new_project rs-a11y-apply)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-npm-a11y
  enable_auto_add "$p"
  grant_unattended "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$A11Y_RECIPE" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$A11Y_RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "accessibility"' >/dev/null
  [ -f "$p/axe.config.mjs" ]
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): accessibility'
}

@test "accessibility skips when the repository already carries the setup commit" {
  setup_fake_npm
  p="$(new_project rs-a11y-skip)"
  bash "$FIXTURES/make-project.sh" "$p" already-configured-a11y
  git -C "$p" commit -q --allow-empty -m "chore(tooling): accessibility"
  enable_auto_add "$p"
  grant_unattended "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$A11Y_RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "accessibility package failure rolls back and leaves no transaction" {
  setup_fake_npm
  p="$(new_project rs-a11y-fail)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-npm-a11y 17
  enable_auto_add "$p"
  grant_unattended "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$A11Y_RECIPE" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -f "$p/axe.config.mjs" ]
}

@test "accessibility red-baseline still plans when HTML violations exist" {
  setup_fake_npm
  p="$(new_project rs-a11y-red)"
  bash "$FIXTURES/make-project.sh" "$p" red-baseline-a11y
  enable_auto_add "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$A11Y_RECIPE" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "accessibility"' >/dev/null
}

@test "localization apply writes the parity script and records inventory" {
  setup_fake_npm
  p="$(new_project rs-l10n-apply)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-npm-l10n
  enable_auto_add "$p"
  grant_unattended "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$L10N_RECIPE" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$L10N_RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "localization"' >/dev/null
  [ -f "$p/scripts/check-locale-parity.mjs" ]
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): localization'
}

@test "localization skips when the repository already carries the setup commit" {
  setup_fake_npm
  p="$(new_project rs-l10n-skip)"
  bash "$FIXTURES/make-project.sh" "$p" already-configured-l10n
  git -C "$p" commit -q --allow-empty -m "chore(tooling): localization"
  enable_auto_add "$p"
  grant_unattended "$p"
  export PATH="$p/.fake-bin:$PATH"
  run provision --project "$p" --recipe "$L10N_RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "localization red-baseline reports key drift through the parity script" {
  command -v node >/dev/null || skip "node is not on PATH"
  p="$(new_project rs-l10n-red)"
  bash "$FIXTURES/make-project.sh" "$p" red-baseline-l10n
  mkdir -p "$p/scripts"
  jq -r '.minimalConfig["scripts/check-locale-parity.mjs"]' "$L10N_RECIPE" >"$p/scripts/check-locale-parity.mjs"
  run bash -c 'cd "$1" && PATH="$1/.fake-bin:$PATH" node scripts/check-locale-parity.mjs' _ "$p"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'missing cancel'
}

@test "native and bash plans agree byte-for-byte on the accessibility recipe" {
  command -v pwsh >/dev/null || skip "pwsh is not on PATH"
  setup_fake_npm
  p="$(new_project rs-a11y-parity)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-npm-a11y
  enable_auto_add "$p"
  export PATH="$p/.fake-bin:$PATH"
  bash_out="$BATS_TEST_TMPDIR/bash-a11y-plan.json"
  pwsh_out="$BATS_TEST_TMPDIR/pwsh-a11y-plan.json"
  provision --project "$p" --recipe "$A11Y_RECIPE" plan >"$bash_out"
  run pwsh -NoProfile -File "$PWPROV" -Project "$p" plan -Recipe "$A11Y_RECIPE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$pwsh_out"
  cmp -s "$bash_out" "$pwsh_out"
}
