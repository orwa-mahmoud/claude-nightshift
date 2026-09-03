E="$BATS_TEST_DIRNAME/../../plugins/nightshift/skills/nightshift/references/shifts/configuration-parity.md"

@test "configuration parity uses config-parity helper" {
  grep -qF 'receipt-templates.md' "$E"
}

@test "configuration parity never retrieves secret values" {
  grep -qi 'never retrieve' "$E"
  grep -qi 'shape' "$E"
}

@test "configuration parity is finite with item gate" {
  grep -qi 'Ends when' "$E"
  grep -qi 'item gate' "$E"
}
