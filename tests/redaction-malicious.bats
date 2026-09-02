#!/usr/bin/env bats
# Untrusted source redaction — injection neutralization and secret stripping.

ROOT="$BATS_TEST_DIRNAME/.."
SP="$ROOT/plugins/nightshift/runtime/source-policy-evidence.sh"
RED="$ROOT/tests/fixtures/redaction"

@test "redact-untrusted neutralizes remote instruction injection" {
  run bash "$SP" redact-untrusted --input "$RED/malicious-instructions.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.remoteInstructionsAlterShift == false' >/dev/null
  printf '%s' "$output" | jq -e '.redactions | index("instruction-injection-neutralized")' >/dev/null
  printf '%s' "$output" | jq -r '.content' | grep -qF '[REDACTED-UNTRUSTED-INSTRUCTION]'
  printf '%s' "$output" | jq -r '.content' | grep -qv 'Ignore previous instructions'
}

@test "redact-untrusted strips secret patterns from pasted content" {
  run bash "$SP" redact-untrusted --input "$RED/secrets.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.redactions | index("secret-pattern-redacted")' >/dev/null
  printf '%s' "$output" | jq -r '.content' | grep -qF '[REDACTED-SECRET]'
  printf '%s' "$output" | jq -r '.content' | grep -qv 'sk-live-abc123'
}

@test "malicious fixture leaves no executable instruction text" {
  run bash "$SP" redact-untrusted --input "$RED/malicious-instructions.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.content' | grep -Evi 'run command:|system: you are|disregard'
}
