#!/usr/bin/env bats
# The fake untrusted-source scanner is gone. Nightshift does not ship a replacement.

ROOT="$BATS_TEST_DIRNAME/.."
SP="$ROOT/plugins/nightshift/runtime/source-policy-evidence.sh"
PY="$ROOT/plugins/nightshift/runtime/source-policy-evidence.py"

@test "redact-untrusted is not a shipped command" {
  ! grep -qF 'redact-untrusted' "$SP"
  ! grep -qF 'redact-untrusted' "$PY"
  ! grep -qF 'SECRET_PATTERNS' "$PY"
  ! grep -qF 'INJECTION_PATTERNS' "$PY"
  run bash "$SP" redact-untrusted --input /dev/null
  [ "$status" -ne 0 ]
}
