#!/usr/bin/env bats
# SEO evidence runtime — Local, Live, and Connected modes.

ROOT="$BATS_TEST_DIRNAME/.."
SE="$ROOT/plugins/nightshift/runtime/seo-evidence.sh"
FIX="$ROOT/tests/fixtures/seo"

@test "seo-evidence script is executable" {
  [ -x "$SE" ]
}

@test "local-inventory ranks orphans and never invents rankings" {
  run bash "$SE" local-inventory --input "$FIX/local/static-site-inventory.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.evidenceMode == "local" and .rankingsInvented == false' >/dev/null
  printf '%s' "$output" | jq -e '.orphanCount >= 1 and (.notMeasured | length) >= 5' >/dev/null
}

@test "live-crawl rejects origin escapes and flags malicious instructions" {
  run bash "$SE" live-crawl --input "$FIX/live/bounded-crawl-snapshot.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.neverLeaveApprovedOrigins == true' >/dev/null
  printf '%s' "$output" | jq -e '.maliciousPages | length >= 1' >/dev/null
}

@test "connected-export keeps metrics separate and forbids clicks-equals-sessions" {
  run bash "$SE" connected-export --input "$FIX/connected/connected-export-sample.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.clicksEqualSessionsClaimAllowed == false' >/dev/null
  printf '%s' "$output" | jq -e '.searchConsoleRows >= 1 and .analyticsRows >= 1' >/dev/null
}

@test "receipt-summary states evidence modes and unknowable surfaces" {
  cat >"$BATS_TEST_TMPDIR/receipt-input.json" <<'EOF'
{"evidenceModes":["local","connected"],"notMeasured":[{"surface":"rankings","reason":"not supplied"}]}
EOF
  run bash "$SE" receipt-summary --input "$BATS_TEST_TMPDIR/receipt-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.receiptMustStateModes == true' >/dev/null
  printf '%s' "$output" | jq -r '.text' | grep -q 'local'
}

@test "seo audit contract references seo-evidence helper" {
  grep -qF 'runtime/seo-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/seo-audit.md"
}
