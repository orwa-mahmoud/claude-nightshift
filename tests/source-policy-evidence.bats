#!/usr/bin/env bats
# Source-policy evidence — closed/bounded/connected policies and manifests.

ROOT="$BATS_TEST_DIRNAME/.."
SP="$ROOT/plugins/nightshift/runtime/source-policy-evidence.sh"
FIX="$ROOT/tests/fixtures/research"
RED="$ROOT/tests/fixtures/redaction"

@test "source-policy script is executable" {
  [ -x "$SP" ]
}

@test "closed-list policy blocks sources not on the owner list" {
  run bash "$SP" policy-resolve --input "$FIX/closed-list.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.policy == "closed-list"' >/dev/null
  printf '%s' "$output" | jq -e '[.blocked[] | select(.reason=="not-on-closed-list")] | length == 1' >/dev/null
}

@test "bounded discovery cannot escape allowed domains or budget" {
  run bash "$SP" policy-resolve --input "$FIX/bounded-discovery.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.scopeEscapes == true' >/dev/null
  printf '%s' "$output" | jq -e '[.blocked[] | select(.reason=="outside-bounded-scope")] | length >= 2' >/dev/null
}

@test "connected corpus keeps exports local and rejects live connectors" {
  run bash "$SP" policy-resolve --input "$FIX/connected-corpus.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.allowed[] | select(.locator | startswith("file:exports/research/"))] | length == 2' >/dev/null
  printf '%s' "$output" | jq -e '[.blocked[] | select(.reason=="direct-connector-out-of-scope")] | length == 1' >/dev/null
}

@test "query manifest separates primary secondary and community evidence" {
  run bash "$SP" query-manifest --input "$FIX/query-manifest-input.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.primaryCount == 1 and .secondaryCount == 1 and .communityCount == 1' >/dev/null
  printf '%s' "$output" | jq -e '.contradictions | length == 1' >/dev/null
  printf '%s' "$output" | jq -e '.untrustedMaterial == true' >/dev/null
}

@test "artifact receipt plan never requires git or package managers" {
  run bash "$SP" artifact-receipt-plan --input "$FIX/artifact-plan.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.requiresRepository == false and .requiresPackageManager == false and .inventGitPrompts == false' >/dev/null
  printf '%s' "$output" | jq -e '.receipts | length == 2' >/dev/null
}

@test "connector boundary keeps credentials outside nightshift and integrations optional" {
  run bash "$SP" connector-boundary --input "$FIX/connector-boundary.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.directConnectorAllowed == true and .credentialsOutsideNightshift == true' >/dev/null
  printf '%s' "$output" | jq -e '.integrationsOptional == true and .redactionRequired == true' >/dev/null
}

@test "research synthesis and documentation writing reference source-policy helper" {
  grep -qF 'source-policy-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/research-synthesis.md"
  grep -qF 'source-policy-evidence.sh' "$ROOT/plugins/nightshift/skills/nightshift/references/shifts/documentation-writing.md"
}

@test "cited-research documents three source policies" {
  grep -qi 'closed list' "$ROOT/plugins/nightshift/skills/nightshift/references/cited-research.md"
  grep -qi 'bounded discovery' "$ROOT/plugins/nightshift/skills/nightshift/references/cited-research.md"
  grep -qi 'connected corpus' "$ROOT/plugins/nightshift/skills/nightshift/references/cited-research.md"
}
