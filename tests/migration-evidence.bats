#!/usr/bin/env bats
# Migration evidence — inventory, compatibility, config parity, data safety, recovery, verdict.

ROOT="$BATS_TEST_DIRNAME/.."
ME="$ROOT/plugins/nightshift/runtime/migration-evidence.sh"
FIX="$ROOT/tests/fixtures/migration"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/migration-evidence.json"

@test "migration-evidence script is executable" {
  [ -x "$ME" ]
}

@test "migration inventory requires named migration and authoritative guidance" {
  run bash "$ME" migration-inventory --input "$FIX/inventory-complete.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "migration-inventory" and .inventoryComplete == true' >/dev/null
  printf '%s' "$output" | jq -e '.migrationName == "users-table-v2"' >/dev/null
  printf '%s' "$output" | jq -e '.inventory.oldNewOverlap.dualWrite == true' >/dev/null
  printf '%s' "$output" | jq -e '.legalAuthorityGuessed == false' >/dev/null

  run bash "$ME" migration-inventory --input "$FIX/inventory-missing-authority.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.inventoryComplete == false and .action == "park"' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="authority")] | length == 1' >/dev/null
}

@test "compatibility assess distinguishes additive and breaking migrations" {
  run bash "$ME" compatibility-assess --input "$FIX/compatibility-additive.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.compatibilityMaintained == true and .reviewFirstRequired == false' >/dev/null
  printf '%s' "$output" | jq -e '[.additive[] | select(.kind=="additive")] | length >= 1' >/dev/null

  run bash "$ME" compatibility-assess --input "$FIX/compatibility-breaking.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.compatibilityMaintained == false and .reviewFirstRequired == true' >/dev/null
  printf '%s' "$output" | jq -e '[.breaking[] | select(.action=="park-for-owner")] | length >= 1' >/dev/null
  printf '%s' "$output" | jq -e '.overlapPlanValid == false' >/dev/null
}

@test "config parity compares secret presence and shape only" {
  run bash "$ME" config-parity --input "$FIX/config-parity-match.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.parityMaintained == true and .secretValuesRetrieved == false' >/dev/null
  printf '%s' "$output" | jq -e '[.hiddenSecrets[] | select(.valuesCompared == false)] | length >= 1' >/dev/null

  run bash "$ME" config-parity --input "$FIX/config-parity-gap.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.parityMaintained == false' >/dev/null
  printf '%s' "$output" | jq -e '[.gaps[] | select(.kind=="shape-mismatch" or .kind=="missing")] | length >= 1' >/dev/null

  run bash "$ME" config-parity --input "$FIX/config-parity-secret-refusal.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.secretValueRetrievalRefused == true and .action == "refuse"' >/dev/null
}

@test "data safety refuses live production and unsupported semantics" {
  run bash "$ME" data-safety --input "$FIX/data-safety-disposable.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "proceed" and .productionRefused == false' >/dev/null

  run bash "$ME" data-safety --input "$FIX/data-safety-production-refused.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.productionRefused == true and .destructiveRefused == true' >/dev/null
  printf '%s' "$output" | jq -e '.action == "refuse"' >/dev/null
  printf '%s' "$output" | jq -e '.legalAuthorityGuessed == false' >/dev/null

  run bash "$ME" data-safety --input "$FIX/data-safety-unsupported-semantics.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "park"' >/dev/null
  printf '%s' "$output" | jq -e '[.blockers[] | select(.category=="unsupported-semantics")] | length >= 1' >/dev/null
}

@test "recovery plan covers failed mid-migration paths" {
  run bash "$ME" recovery-plan --input "$FIX/recovery-failed-mid-migration.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.midMigrationRecoveryAvailable == true' >/dev/null
  printf '%s' "$output" | jq -e '[.recoveryActions[] | select(.step=="rollback")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.recoveryActions[] | select(.step=="idempotent-retry")] | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '[.lockWarnings[] | select(.action=="release-before-retry")] | length >= 1' >/dev/null

  run bash "$ME" recovery-plan --input "$FIX/recovery-no-rollback.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.midMigrationRecoveryAvailable == false and .action == "park"' >/dev/null
}

@test "verdict reports bounded readiness and blocked breaking migrations" {
  run bash "$ME" verdict --input "$FIX/verdict-ready-bounded.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "ready-bounded" and .runDirectAllowed == true' >/dev/null
  printf '%s' "$output" | jq -e '.rollbackDocumented == true and .finiteEndingReached == true' >/dev/null

  run bash "$ME" verdict --input "$FIX/verdict-blocked-breaking.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "blocked" and .reviewFirstRequired == true' >/dev/null
  printf '%s' "$output" | jq -e '.runDirectAllowed == false and .legalAuthorityGuessed == false' >/dev/null
}

@test "production refusal verdict stays refused without owner approval" {
  run bash "$ME" production-refusal --input "$FIX/data-safety-production-refused.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kind == "production-refusal" and .productionRefused == true' >/dev/null

  f="$BATS_TEST_TMPDIR/verdict-production-refused.json"
  cat >"$f" <<'EOF'
{
  "inventory": {"action": "proceed", "inventory": {"rollbackSteps": ["restore-v1-read"]}},
  "compatibility": {"breaking": [], "reviewFirstRequired": false},
  "configParity": {"parityMaintained": true},
  "dataSafety": {"productionRefused": true, "action": "refuse", "blockers": []},
  "recovery": {"migrationState": "in-progress", "midMigrationRecoveryAvailable": true},
  "reviewFirstDefault": true,
  "runDirectBounded": false
}
EOF
  run bash "$ME" verdict --input "$f"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "refused" and .productionAuthorityRefused == true' >/dev/null
}

@test "migration evidence outputs validate against schema" {
  for pair in \
    "migration-inventory:$FIX/inventory-complete.json" \
    "compatibility-assess:$FIX/compatibility-additive.json" \
    "config-parity:$FIX/config-parity-match.json" \
    "data-safety:$FIX/data-safety-disposable.json" \
    "recovery-plan:$FIX/recovery-failed-mid-migration.json" \
    "verdict:$FIX/verdict-ready-bounded.json"; do
    cmd="${pair%%:*}"
    f="${pair#*:}"
    out="$BATS_TEST_TMPDIR/$cmd.json"
    bash "$ME" "$cmd" --input "$f" >"$out"
    python3 "$SCHEMA_PY" "$SCHEMA" "$out" \
      || { echo "schema failed: $cmd"; return 1; }
  done
}

@test "migration compatibility contract references migration-evidence helper" {
  grep -qF 'runtime/migration-evidence.sh migration-inventory' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/migration-compatibility.md"
  grep -qF 'runtime/migration-evidence.sh config-parity' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/migration-compatibility.md"
  grep -qF 'runtime/migration-evidence.sh data-safety' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/migration-compatibility.md"
  grep -qF 'runtime/migration-evidence.sh recovery-plan' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/migration-compatibility.md"
  grep -qF 'runtime/migration-evidence.sh verdict' \
    "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/migration-compatibility.md"
}
