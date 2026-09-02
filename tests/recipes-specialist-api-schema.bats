#!/usr/bin/env bats
# Specialist api-schema recipes: admission, OpenAPI validation, and fixture matrices.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PWPROV="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/recipes/specialist/api-schema"
RECIPE="$REGISTRY/javascript-typescript/api-schema-openapi.json"

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
  local exit_code="${1:-0}"
  FAKE_NPM_BIN="$BATS_TEST_TMPDIR/fake-npm-bin"
  mkdir -p "$FAKE_NPM_BIN"
  for mgr in npm npx pnpm yarn; do
    sed "s/@EXIT@/$exit_code/" "$FIXTURES/fake-npm.sh" >"$FAKE_NPM_BIN/$mgr"
    chmod +x "$FAKE_NPM_BIN/$mgr"
  done
  export PATH="$FAKE_NPM_BIN:$PATH"
}

@test "api-schema recipe carries the frozen contract, admission evidence, and fallback shift" {
  while IFS= read -r field; do
    [ -n "$field" ] || continue
    req="$req $field"
  done < <(jq -r '.requiredRecipeFields[]' "$SCHEMA")
  while IFS= read -r field; do
    [ -n "$field" ] || continue
    maint="$maint $field"
  done < <(jq -r '.maintenanceFields[]?' "$SCHEMA")
  for field in $req; do
    jq -e --arg f "$field" 'has($f)' "$RECIPE" >/dev/null \
      || { echo "$RECIPE missing $field"; return 1; }
  done
  for field in $maint; do
    jq -e --arg f "$field" 'has($f)' "$RECIPE" >/dev/null \
      || { echo "$RECIPE missing maintenance $field"; return 1; }
  done
  while IFS= read -r field; do
    jq -e --arg f "$field" '.admission | has($f)' "$RECIPE" >/dev/null \
      || { echo "$RECIPE missing admission.$field"; return 1; }
  done < <(jq -r '.admissionFields[]' "$SCHEMA")
  jq -e '.admission.contract == "api-contract-drift"' "$RECIPE" >/dev/null
  jq -e '.admission.fixture | test("tests/fixtures/recipes/specialist/api-schema")' "$RECIPE" >/dev/null
  jq -e '.enabledShifts[0].contract == "api-contract-drift"' "$RECIPE" >/dev/null
  jq -e '.enabledShifts[0].fallback | test("do not fetch or adopt an external schema")' "$RECIPE" >/dev/null
  jq -e '.smoke.command | test("openapi\\.ya?ml|openapi\\.json")' "$RECIPE" >/dev/null
  jq -e '.smoke.command | test("lint")' "$RECIPE" >/dev/null
  jq -e '.smoke.command | test("local file only")' "$RECIPE" >/dev/null
}

@test "review-first plan for api-schema refuses apply policy" {
  p="$(new_project rs-as-plan)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-openapi
  enable_auto_add "$p"
  jq '.toolingPolicy = "review-missing"' "$p/.nightshift/shift-policy.json" >"$p/.nightshift/shift-policy.tmp"
  mv "$p/.nightshift/shift-policy.tmp" "$p/.nightshift/shift-policy.json"
  run provision --project "$p" --recipe "$RECIPE" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refused == true and .reason == "policy-not-auto-add"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilityId == "api-schema"' >/dev/null
  printf '%s\n' "$output" | jq -e '.enabledShifts[0].fallback | test("repository-owned OpenAPI")' >/dev/null
}

@test "api-schema plans on a decidable lockfile with a repository-owned schema" {
  p="$(new_project rs-as-detect)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-openapi
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$RECIPE" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "api-schema"' >/dev/null
  printf '%s\n' "$output" | jq -e '.smoke.command | test("@redocly/cli lint")' >/dev/null
}

@test "api-schema apply refuses when two lockfiles make the manager ambiguous" {
  p="$(new_project rs-as-wrong)"
  bash "$FIXTURES/make-project.sh" "$p" wrong-manager
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$RECIPE" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
}

@test "api-schema apply with the scripted toolchain records inventory and a tooling commit" {
  setup_fake_npm
  p="$(new_project rs-as-apply)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-openapi
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$RECIPE" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "api-schema"' >/dev/null
  jq -e '.items[] | select(.capability == "api-schema")' "$p/.nightshift/capabilities.json" >/dev/null
  grep -q 'fixture manager' "$p/package-lock.json"
}

@test "api-schema skips when the repository already carries the setup commit" {
  p="$(new_project rs-as-skip)"
  bash "$FIXTURES/already-configured.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "api-schema package failure rolls back and leaves no transaction" {
  setup_fake_npm 17
  p="$(new_project rs-as-fail)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-openapi
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$RECIPE" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  ! grep -q '@redocly/cli' "$p/package.json"
}

@test "api-schema red baseline smoke reports validation findings" {
  setup_fake_npm
  export NS_FAKE_MODE=findings
  p="$(new_project rs-as-red)"
  bash "$FIXTURES/make-project.sh" "$p" red-baseline
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$RECIPE" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "api-schema"' >/dev/null
  jq -e '.items[] | select(.capability == "api-schema")' "$p/.nightshift/capabilities.json" >/dev/null
}

@test "native and bash plans agree byte-for-byte on the api-schema recipe" {
  command -v pwsh >/dev/null || skip "pwsh is not on PATH"
  p="$(new_project rs-as-parity)"
  bash "$FIXTURES/make-project.sh" "$p" minimal-openapi
  enable_auto_add "$p"
  bash_out="$BATS_TEST_TMPDIR/bash-as-plan.json"
  pwsh_out="$BATS_TEST_TMPDIR/pwsh-as-plan.json"
  provision --project "$p" --recipe "$RECIPE" plan >"$bash_out"
  run pwsh -NoProfile -File "$PWPROV" -Project "$p" plan -Recipe "$RECIPE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$pwsh_out"
  cmp -s "$bash_out" "$pwsh_out"
}
