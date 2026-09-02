#!/usr/bin/env bats
# Engineering-confidence shared evidence helpers.

ROOT="$BATS_TEST_DIRNAME/.."
EE="$ROOT/plugins/nightshift/runtime/engineering-evidence.sh"
FIX="$ROOT/tests/fixtures/engineering"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/engineering-evidence.json"

@test "engineering-evidence script is executable" {
  [ -x "$EE" ]
}

@test "flaky matrix captures repetition dimensions" {
  run bash "$EE" flaky-matrix --input "$FIX/flaky-matrix.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "flaky-matrix" and .rows[0].repetitions == 25' >/dev/null
  printf '%s' "$output" | jq -e '.rows[0].seed == 42 and .rows[0].parallelism == "disabled"' >/dev/null
}

@test "ci warnings split repository-owned from external emitters" {
  run bash "$EE" ci-warnings --input "$FIX/ci-warnings.txt"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.warnings[] | select(.causeClass=="repository-owned")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '[.warnings[] | select(.causeClass=="external")] | length >= 1' >/dev/null
}

@test "dead-code guard forbids public export deletion" {
  run bash "$EE" dead-code-guard --input "$FIX/dead-code-forbidden.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "forbidden" and .guards.publicExport == true' >/dev/null
}

@test "todo classify separates actionable from ambiguous" {
  run bash "$EE" todo-classify --input "$FIX/todo-actionable.txt"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.classification == "actionable"' >/dev/null
  run bash "$EE" todo-classify --input "$FIX/todo-ambiguous.txt"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.classification == "ambiguous" and .stageTo == "drafting-table"' >/dev/null
}

@test "vuln enrich records provenance and reachability" {
  run bash "$EE" vuln-enrich --input "$FIX/vuln-advisory.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.provenance == "npm audit" and .reachable == true' >/dev/null
  printf '%s' "$output" | jq -e '.transitivePath | length == 3' >/dev/null
}

@test "dep batch orders patch before minor before major" {
  run bash "$EE" dep-batch --input "$FIX/dep-outdated.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.ordered[0].kind == "patch" and .ordered[-1].kind == "major"' >/dev/null
}

@test "all six engineering-confidence contracts reference the helper" {
  for f in flaky-test-repair ci-warning-cleanup dead-code-cleanup todo-fixme-debt vulnerability-sweep dependency-upgrade-sweep; do
    grep -qF 'runtime/engineering-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/$f.md" \
      || { echo "missing helper reference: $f"; return 1; }
  done
}
