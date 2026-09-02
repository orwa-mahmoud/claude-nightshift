E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/data-migration.md"

@test "data migration uses data-safety and production-refusal helpers" {
  grep -qF 'migration-evidence.sh data-safety' "$E"
  grep -qF 'production-refusal' "$E"
}

@test "data migration refuses production destructive direct mode" {
  grep -qi 'production' "$E"
  grep -qi 'owner-approved' "$E" || grep -qi 'owner approved' "$E"
  grep -qi 'disposable' "$E"
}

@test "data migration handles mid-migration recovery" {
  grep -qi 'mid-migration' "$E" || grep -qi 'midMigrationRecovery' "$E"
  grep -qi 'rollback' "$E"
}

@test "data migration is finite with item gate" {
  grep -qi 'Ends when' "$E"
  grep -qi 'item gate' "$E"
}
