#!/usr/bin/env bats
# The recipe registry's index writer and maintenance audit.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
AUDIT="$ROOT/plugins/nightshift/runtime/recipe-audit.sh"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
VALIDATOR="$BATS_TEST_DIRNAME/helpers/validate-json-schema.py"

setup() { export NIGHTSHIFT_EVIDENCE_NOW=2026-09-02T00:00:00Z; }

@test "index lists every registered recipe in byte order" {
  run bash "$AUDIT" --project "$ROOT" index --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .count == 23' >/dev/null
  [ -f "$REGISTRY/index.json" ]
  [ "$(jq 'length' "$REGISTRY/index.json")" -eq 23 ]
  jq -e 'sort_by(.ecosystem, .capabilityId) == .' "$REGISTRY/index.json" >/dev/null
  while IFS= read -r path; do
    rel="${path#"$REGISTRY/"}"
    jq -e --arg p "recipes/$rel" '.[] | select(.path == $p)' "$REGISTRY/index.json" >/dev/null
  done < <(find "$REGISTRY" -name '*.json' ! -name index.json | sort)
}

@test "audit names contract failures before it reaches the network" {
  tmp="$BATS_TEST_TMPDIR/audit-bad"
  mkdir -p "$tmp/bad"
  printf '{"capabilityId":"test","ecosystems":["make"],"versionConstraints":{},"detect":{},"probe":{},"packageManagerAdditions":[],"allowedFiles":[],"minimalConfig":{},"smoke":{},"rollback":{},"enabledShifts":[],"safetyClass":"local-dev-free","permissionRequirements":[],"recipeVersion":"1"}\n' \
    >"$tmp/bad/test.json"
  run env NIGHTSHIFT_RECIPE_REGISTRY="$tmp" bash "$AUDIT" --project "$ROOT" audit --json
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | jq -e '.recipes[0].state == "missing-maintenance"' >/dev/null
}

@test "audit reads staleness from lastVerified and NIGHTSHIFT_EVIDENCE_NOW" {
  tmp="$BATS_TEST_TMPDIR/audit-stale"
  mkdir -p "$tmp/stale"
  jq -n '{
    capabilityId: "test", ecosystems: ["make"], versionConstraints: {make: ">=3.81"},
    detect: {command: "true"}, probe: {command: "true"}, packageManagerAdditions: [],
    allowedFiles: [], minimalConfig: {}, smoke: {command: "true"}, rollback: {command: "true"},
    enabledShifts: ["quality"], safetyClass: "local-dev-free", permissionRequirements: [],
    recipeVersion: "1", lastVerified: "2020-01-01", upstream: "https://example.test/make",
    maintenance: {check: "fixture", resolves: "make --version"}
  }' >"$tmp/stale/test.json"
  run env NIGHTSHIFT_RECIPE_REGISTRY="$tmp" NIGHTSHIFT_EVIDENCE_NOW=2026-09-02T00:00:00Z \
    bash "$AUDIT" --project "$ROOT" audit --json
  [ "$status" -eq 3 ]
  printf '%s\n' "$output" | jq -e '.recipes[0].state == "stale"' >/dev/null
}

@test "make recipes audit ok when make is on PATH" {
  command -v make >/dev/null || skip "make is not on PATH"
  run bash "$AUDIT" --project "$ROOT" audit --json
  printf '%s\n' "$output" | jq -e '
    [.recipes[] | select(.ecosystem == "make") | .state] | unique == ["ok"]
  ' >/dev/null
}
