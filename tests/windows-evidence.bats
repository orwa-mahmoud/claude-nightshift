load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/evidence-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"

@test "Windows evidence logic suite is registered with run.ps1" {
  [ -f "$LOGIC" ]
  grep -qF 'evidence-logic.ps1' "$RUN"
}

@test "Windows evidence logic covers the frozen interface scenarios" {
  grep -qF 'invalid severity' "$LOGIC"
  grep -qF 'untrusted' "$LOGIC"
  grep -qF 'prose' "$LOGIC"
  grep -qF 'unknown id' "$LOGIC"
  grep -qF 'malformed JSON on line' "$LOGIC"
  grep -qF 'no .nightshift/' "$LOGIC"
}

@test "Windows evidence logic checks exact byte formatting" {
  grep -qF 'Test-NSNoCarriageReturn' "$LOGIC"
  grep -qF 'Test-NSSingleTrailingNewline' "$LOGIC"
  grep -qF 'Test-NSAsciiOnly' "$LOGIC"
  grep -qF 'Test-NSKeysSorted' "$LOGIC"
  grep -qF 'Test-NSHasBom' "$LOGIC"
}

@test "Windows evidence logic checks python3 byte parity and its skip path" {
  grep -qF 'Invoke-EvidencePython' "$LOGIC"
  grep -qF 'byte-identical' "$LOGIC"
  grep -qF 'python3 not found on PATH' "$LOGIC"
}

@test "Windows evidence logic checks the wrapper guard fails precisely" {
  grep -qF 'evidence.ps1 is still a wrapper' "$LOGIC"
  grep -qF 'Get-Command python' "$LOGIC"
}

@test "Windows evidence logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    skip 'pwsh not installed'
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
