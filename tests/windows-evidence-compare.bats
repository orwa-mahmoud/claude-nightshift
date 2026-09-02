load helpers

LOGIC="$BATS_TEST_DIRNAME/windows/evidence-compare-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"
WIN="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows"
MODULE="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/Nightshift.psm1"

@test "Windows comparison logic suite is registered with run.ps1" {
  [ -f "$LOGIC" ]
  grep -qF 'evidence-compare-logic.ps1' "$RUN"
}

@test "the Windows lifecycle helpers are native and thin" {
  [ -f "$WIN/evidence-compare.ps1" ]
  [ -f "$WIN/evidence-baseline.ps1" ]
  [ -f "$WIN/evidence-checkpoint.ps1" ]
  grep -qF 'Invoke-NSEvidenceCompareCommand' "$WIN/evidence-compare.ps1"
  grep -qF 'Invoke-NSEvidenceBaselineCommand' "$WIN/evidence-baseline.ps1"
  grep -qF 'Invoke-NSEvidenceCheckpointCommand' "$WIN/evidence-checkpoint.ps1"
  ! grep -RE 'brew |npm install|pip install|python3|jq is required' \
    "$WIN/evidence-compare.ps1" "$WIN/evidence-baseline.ps1" "$WIN/evidence-checkpoint.ps1"
}

@test "the comparison carries every frozen class and JSON key" {
  for class in new cleared unchanged regressed unavailable rejected-duplicate parked human-only; do
    grep -qF "'$class'" "$MODULE"
  done
  grep -qF "\$document['baseline'] = \$Baseline" "$MODULE"
  grep -qF "\$document['mode'] = \$mode" "$MODULE"
  grep -qF "\$document['pass'] = \$pass" "$MODULE"
  grep -qF "\$document['rows'] = \$rows.ToArray()" "$MODULE"
  grep -qF "\$document['schemaVersion'] = 1" "$MODULE"
  grep -qF "\$document['summary'] = \$summary" "$MODULE"
  grep -qF "\$row['id']" "$MODULE"
  grep -qF "\$row['class']" "$MODULE"
  grep -qF "\$row['digest']" "$MODULE"
  grep -qF "\$row['sources']" "$MODULE"
  grep -qF "\$row['locator']" "$MODULE"
  grep -qF '| ID | Class | Digest | Sources | Locator |' "$MODULE"
}

@test "the lifecycle records carry exactly the frozen details" {
  for field in sourceClass command versions environmentDigest rawDigest scope seen; do
    grep -qF "\$details['$field']" "$MODULE"
  done
  for field in worktreeDigest head baseline artifacts touched rollback plan; do
    grep -qF "\$details['$field']" "$MODULE"
  done
  grep -qF "'baseline'" "$MODULE"
  grep -qF "'checkpoint'" "$MODULE"
}

@test "the shift policy accepts completionMode and selectedDebt without resolving them" {
  grep -qF "'completionMode', 'selectedDebt'" "$MODULE"
  grep -qF "\$script:NSPolicyCompletionModes = @('clear-all', 'no-regression-plus-selected-debt')" "$MODULE"
  grep -qF 'completionMode: must be one of ' "$MODULE"
  grep -qF 'selectedDebt: must be an array of finding ids' "$MODULE"
  grep -qF 'resolve does not report completionMode' "$LOGIC"
  grep -qF 'resolve does not report selectedDebt' "$LOGIC"
}

@test "Windows comparison logic covers every class and both modes" {
  grep -qF 'a finding the baseline never saw is new' "$LOGIC"
  grep -qF 'a fixed finding is cleared' "$LOGIC"
  grep -qF 'the same digest is unchanged' "$LOGIC"
  grep -qF 'a moved digest on a known id is regressed' "$LOGIC"
  grep -qF 'an unavailable source is unavailable' "$LOGIC"
  grep -qF 'a baseline id the ledger no longer carries is unavailable, never cleared' "$LOGIC"
  grep -qF 'a duplicate root cause is rejected-duplicate' "$LOGIC"
  grep -qF 'a parked disposition is parked' "$LOGIC"
  grep -qF 'a human-only status is human-only' "$LOGIC"
  grep -qF 'dedupe keeps every originating tool on the surviving row' "$LOGIC"
  grep -qF 'clear-all fails while one finding is only unchanged' "$LOGIC"
  grep -qF 'no-regression passes when nothing regressed and the selected debt cleared' "$LOGIC"
  grep -qF 'selected debt that did not clear fails the relaxed mode' "$LOGIC"
}

@test "Windows comparison logic covers unavailable-is-not-improvement" {
  grep -qF 'a source the ledger marked unavailable never passes clear-all' "$LOGIC"
  grep -qF 'an unavailable tool clears nothing' "$LOGIC"
  grep -qF 'a changed environment digest is reported as unavailable, never as improvement' "$LOGIC"
}

@test "Windows comparison logic checks exact byte formatting" {
  grep -qF 'Test-NSNoCarriageReturn' "$LOGIC"
  grep -qF 'Test-NSSingleTrailingNewline' "$LOGIC"
  grep -qF 'Test-NSAsciiOnly' "$LOGIC"
  grep -qF 'Test-NSKeysSorted' "$LOGIC"
  grep -qF 'Test-NSHasBom' "$LOGIC"
  grep -qF 'rows are sorted by id in byte order' "$LOGIC"
  grep -qF 'the environment digest is sha256 over sorted tool/version lines' "$LOGIC"
}

@test "Windows comparison logic checks bash byte parity and its skip path" {
  grep -qF 'byte-identical' "$LOGIC"
  grep -qF 'evidence-compare.sh' "$LOGIC"
  grep -qF 'parity leg not run' "$LOGIC"
}

@test "Windows comparison logic passes when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    skip 'pwsh not installed'
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
