#!/usr/bin/env bats
# Native status helper — evidence counts, policy view, and lifecycle lines.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
STATUS="$ROOT/plugins/nightshift/runtime/status.sh"
REF="$ROOT/plugins/nightshift/skills/nightshift/references"

load helpers

@test "status reports evidence counts and separate lifecycle lines" {
  p="$(new_project status-basic)"
  cp "$REF/nightshift-rules-template.json" "$p/.nightshift/rules.json"
  mkdir -p "$p/.nightshift/evidence"
  printf '{"schemaVersion":1,"id":"b1","domain":"baseline","severity":"low","confidence":"medium","impact":"local","status":"open","ladder":"declared","locator":"x","source":"fixture","sourceClass":"test","host":"local"}\n' \
    >"$p/.nightshift/evidence/findings.jsonl"
  printf '{"schemaVersion":1,"id":"c1","domain":"checkpoint","severity":"low","confidence":"medium","impact":"local","status":"open","ladder":"declared","locator":"x","source":"fixture","sourceClass":"test","host":"local"}\n' \
    >>"$p/.nightshift/evidence/findings.jsonl"
  printf '1735689600 test-session\n' >"$p/.nightshift/.shift-pulse"
  printf '1\n2\n' >"$p/.nightshift/.stall"
  printf '## Items\n- [ ] **1. work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  run bash "$STATUS" --project "$p"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'evidence:    findings=2 open=2 baseline=1 checkpoint=1'
  printf '%s\n' "$output" | grep -qF 'liveness:'
  printf '%s\n' "$output" | grep -qF 'last activity:'
  printf '%s\n' "$output" | grep -qF 'last checkpoint: c1'
  printf '%s\n' "$output" | grep -qF 'stall attempts: 2'
  printf '%s\n' "$output" | grep -qF 'resolved policy'
}

@test "checkpoint changes the stall fingerprint and resets the counter" {
  p="$(new_project status-stall)"
  cp "$REF/nightshift-rules-template.json" "$p/.nightshift/rules.json"
  printf '## Items\n- [ ] **1. work.**\n' >"$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  git -C "$p" commit -q --allow-empty -m "progress"
  FP1="$(bash -c 'PROJECT_DIR="'"$p"'"; . "'"$ROOT"'/plugins/nightshift/lib/lib.sh"; . "'"$ROOT"'/plugins/nightshift/hooks/shared/gate-core.sh"; ns_gate_progress_token')"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  bash "$ROOT/plugins/nightshift/runtime/evidence.sh" --project "$p" init >/dev/null
  bash "$ROOT/plugins/nightshift/runtime/evidence.sh" --project "$p" append --record "$(
    jq -nc --arg t "$p" '{
      schemaVersion: 1, id: "c1", domain: "checkpoint", sourceClass: "worktree",
      source: "manual", scope: "unit", severity: "info", confidence: "high",
      impact: "none", status: "open", ladder: "observed", locator: "nohead",
      digest: "digest-c1", firstSeen: "2026-09-02T00:00:00Z",
      lastChecked: "2026-09-02T00:00:00Z", action: "checkpoint recorded",
      host: "claude", workTarget: $t,
      details: { baseline: "b1", touched: ["README"], rollback: "manual", plan: "fixture" }
    }')" >/dev/null
  FP2="$(bash -c 'PROJECT_DIR="'"$p"'"; . "'"$ROOT"'/plugins/nightshift/lib/lib.sh"; . "'"$ROOT"'/plugins/nightshift/hooks/shared/gate-core.sh"; ns_gate_progress_token')"
  [ "$FP1" != "$FP2" ]
}
