load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/detect-capabilities-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"

@test "Windows detect-capabilities logic suite is registered with run.ps1" {
  [ -f "$LOGIC" ]
  grep -qF 'detect-capabilities-logic.ps1' "$RUN"
}

@test "Windows detect-capabilities logic covers the frozen interface scenarios" {
  grep -qF 'artifact mode' "$LOGIC"
  grep -qF 'available-but-failing' "$LOGIC"
  grep -qF "'unavailable'" "$LOGIC"
  grep -qF 'monorepo=true' "$LOGIC" || grep -qF 'monorepo -eq $true' "$LOGIC"
  grep -qF 'make:build' "$LOGIC"
  grep -qF 'make:test' "$LOGIC"
  grep -qF 'api-schema' "$LOGIC"
  grep -qF 'localization' "$LOGIC"
  grep -qF 'structured-results' "$LOGIC"
}

@test "Windows detect-capabilities logic checks exact byte formatting" {
  grep -qF 'Test-NSNoCarriageReturn' "$LOGIC"
  grep -qF 'Test-NSSingleTrailingNewline' "$LOGIC"
  grep -qF 'Test-NSAsciiOnly' "$LOGIC"
  grep -qF 'top-level keys appear sorted' "$LOGIC"
}

@test "Windows detect-capabilities logic checks python3 byte parity and its skip path" {
  grep -qF 'Invoke-PythonReference' "$LOGIC"
  grep -qF 'Test-NSBytesEqual' "$LOGIC"
  grep -qF 'python3 not found on PATH' "$LOGIC"
}

@test "Windows detect-capabilities logic checks the detector wrote nothing" {
  grep -qF 'Get-NSTreeStamp' "$LOGIC"
  grep -qF 'wrote nothing into the js-repo fixture' "$LOGIC"
  grep -qF 'wrote nothing into the monorepo fixture' "$LOGIC"
}

@test "Windows detect-capabilities logic checks usage errors" {
  grep -qF 'missing -Project exits 1' "$LOGIC"
  grep -qF 'not a directory' "$LOGIC"
}

@test "Windows detect-capabilities logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    skip 'pwsh not installed'
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
