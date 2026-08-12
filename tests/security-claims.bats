SECURITY="$BATS_TEST_DIRNAME/../SECURITY.md"
KNOBS="$BATS_TEST_DIRNAME/../docs/knobs.md"

@test "security policy distinguishes Nightshift from launched agents" {
  grep -qF 'does not phone home' "$SECURITY"
  grep -qF 'coding agent selected by' "$SECURITY"
  ! grep -qF 'no network calls' "$SECURITY"
}

@test "notification command is documented as unrestricted owner shell" {
  grep -qF 'unrestricted owner-provided shell' "$SECURITY"
  grep -qF 'unrestricted owner-provided shell' "$KNOBS"
  grep -qF 'can access the network' "$KNOBS"
}
