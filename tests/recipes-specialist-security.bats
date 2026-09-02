#!/usr/bin/env bats
# Specialist security and dead-code recipes: admission, plans, fallback, and fixture matrices.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PWPROV="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
AUDIT="$ROOT/plugins/nightshift/runtime/recipe-audit.sh"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/recipes/specialist/security"

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

recipe_path() {
  printf '%s/%s/%s.json' "$REGISTRY" "$1" "$2"
}

setup_fake_npm() {
  FAKE_NPM_BIN="$BATS_TEST_TMPDIR/fake-npm-bin"
  mkdir -p "$FAKE_NPM_BIN"
  ln -sf "$FIXTURES/fake-npm.sh" "$FAKE_NPM_BIN/npm"
  ln -sf "$FIXTURES/fake-npm.sh" "$FAKE_NPM_BIN/node"
  export PATH="$FAKE_NPM_BIN:$PATH"
  export NS_FAKE_MODE="${NS_FAKE_MODE:-green}"
}

setup_fake_govulncheck() {
  FAKE_GO_BIN="$BATS_TEST_TMPDIR/fake-govulncheck-bin"
  mkdir -p "$FAKE_GO_BIN"
  ln -sf "$FIXTURES/fake-govulncheck.sh" "$FAKE_GO_BIN/govulncheck"
  export PATH="$FAKE_GO_BIN:$PATH"
  export NS_FAKE_MODE="${NS_FAKE_MODE:-green}"
}

setup_python_venv() {
  p="$1"
  bash "$BATS_TEST_DIRNAME/fixtures/recipes/python/make-project.sh" "$p" pip-venv
  export VIRTUAL_ENV="$p/.venv"
  export PATH="$p/.venv/bin:$PATH"
}

@test "specialist recipes ship admission evidence and fallback-enabled shifts" {
  for recipe in \
    javascript-typescript/dependency-audit-npm \
    javascript-typescript/dead-code-knip \
    python/dependency-audit-pip \
    python/dead-code-vulture \
    go/dependency-audit-govulncheck; do
    path="$(recipe_path "${recipe%%/*}" "${recipe##*/}")"
    jq -e '.admission.contract and .admission.fixture and .admission.demand' "$path" >/dev/null
    jq -e '[.enabledShifts[] | type] | all(. == "object")' "$path" >/dev/null
    jq -e '[.enabledShifts[] | .contract and .fallback] | all' "$path" >/dev/null
    jq -e '.elevationCategories == []' "$path" >/dev/null
    for field in lastVerified upstream maintenance; do
      jq -e --arg f "$field" 'has($f)' "$path" >/dev/null
    done
  done
}

@test "audit reports inadmissible before missing-maintenance for specialist recipes without admission" {
  tmp="$BATS_TEST_TMPDIR/inadmissible-recipe"
  mkdir -p "$tmp/javascript-typescript"
  jq -n '{
    capabilityId: "security", ecosystems: ["javascript-typescript"], versionConstraints: {},
    detect: {command: "true"}, probe: {command: "true"}, packageManagerAdditions: [],
    allowedFiles: [], minimalConfig: {}, smoke: {command: "true"}, rollback: {command: "true"},
    enabledShifts: [{contract: "vulnerability-sweep", fallback: "no audit output is available"}],
    safetyClass: "local-dev-free", permissionRequirements: [], recipeVersion: "1",
    lastVerified: "2026-09-02", upstream: "https://example.test/npm-audit",
    maintenance: {check: "fixture", resolves: "true"}
  }' >"$tmp/javascript-typescript/dependency-audit-npm.json"
  run env NIGHTSHIFT_RECIPE_REGISTRY="$tmp" NIGHTSHIFT_EVIDENCE_NOW=2026-09-02T00:00:00Z \
    bash "$AUDIT" --project "$ROOT" audit --json
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | jq -e '.recipes[0].state == "inadmissible"' >/dev/null
}

@test "review-first plan for npm audit refuses apply policy" {
  setup_fake_npm
  p="$(new_project rs-npm-plan)"
  bash "$FIXTURES/minimal-npm-audit.sh" "$p"
  enable_auto_add "$p"
  jq '.toolingPolicy = "review-missing"' "$p/.nightshift/shift-policy.json" >"$p/.nightshift/shift-policy.tmp"
  mv "$p/.nightshift/shift-policy.tmp" "$p/.nightshift/shift-policy.json"
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript dependency-audit-npm)" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refused == true and .reason == "policy-not-auto-add"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilityId == "security"' >/dev/null
}

@test "npm audit plans clean under auto-add and apply stays a dry run for local-dev-free" {
  setup_fake_npm
  p="$(new_project rs-npm-apply)"
  bash "$FIXTURES/minimal-npm-audit.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript dependency-audit-npm)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .refused == false and .capabilityId == "security"' >/dev/null
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript dependency-audit-npm)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "security"' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
}

@test "npm audit red baseline still plans when the fixture reports advisories" {
  setup_fake_npm
  export NS_FAKE_MODE=findings
  p="$(new_project rs-npm-red)"
  bash "$FIXTURES/minimal-npm-audit.sh" "$p"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript dependency-audit-npm)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "security"' >/dev/null
}

@test "govulncheck plans when the tool is absent and refuses only at apply smoke" {
  p="$(new_project rs-go-fallback)"
  bash "$FIXTURES/minimal-govulncheck.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path go dependency-audit-govulncheck)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "security"' >/dev/null
  run provision --project "$p" --recipe "$(recipe_path go dependency-audit-govulncheck)" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
}

@test "govulncheck apply with the scripted scanner records the security capability" {
  setup_fake_govulncheck
  p="$(new_project rs-go-apply)"
  bash "$FIXTURES/minimal-govulncheck.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path go dependency-audit-govulncheck)" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$(recipe_path go dependency-audit-govulncheck)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "security"' >/dev/null
  jq -e '.items[] | select(.capability == "security")' "$p/.nightshift/capabilities.json" >/dev/null
}

@test "pip-audit provisions through the fixture manager and smokes cleanly" {
  p="$(new_project rs-py-audit)"
  setup_python_venv "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path python dependency-audit-pip)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "security"' >/dev/null
}

@test "knip dead-code recipe plans on a decidable npm lockfile" {
  setup_fake_npm
  p="$(new_project rs-knip-plan)"
  bash "$FIXTURES/minimal-knip.sh" "$p"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript dead-code-knip)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "dead-code"' >/dev/null
  printf '%s\n' "$output" | jq -e '.minimalConfig["knip.json"] != null' >/dev/null
}

@test "vulture dead-code skips when the repository already carries the setup commit" {
  p="$(new_project rs-vulture-skip)"
  bash "$FIXTURES/minimal-python-dead-code.sh" "$p"
  git -C "$p" commit -q --allow-empty -m "chore(tooling): dead-code"
  enable_auto_add "$p"
  grant_unattended "$p"
  export VIRTUAL_ENV="$p/.venv"
  export PATH="$p/.venv/bin:$PATH"
  run provision --project "$p" --recipe "$(recipe_path python dead-code-vulture)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "native and bash plans agree byte-for-byte on dependency-audit-npm" {
  command -v pwsh >/dev/null || skip "pwsh is not on PATH"
  setup_fake_npm
  p="$(new_project rs-parity)"
  bash "$FIXTURES/minimal-npm-audit.sh" "$p"
  enable_auto_add "$p"
  bash_out="$BATS_TEST_TMPDIR/bash-plan.json"
  pwsh_out="$BATS_TEST_TMPDIR/pwsh-plan.json"
  provision --project "$p" --recipe "$(recipe_path javascript-typescript dependency-audit-npm)" plan >"$bash_out"
  run pwsh -NoProfile -File "$PWPROV" -Project "$p" plan -Recipe "$(recipe_path javascript-typescript dependency-audit-npm)"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$pwsh_out"
  cmp -s "$bash_out" "$pwsh_out"
}
