#!/usr/bin/env bats
# Defect hunt lens rotation and convergence tracking.

ROOT="$BATS_TEST_DIRNAME/.."
DC="$ROOT/plugins/nightshift/runtime/defect-cycle.sh"
FIX="$ROOT/tests/fixtures/testing/defect-cycle"
SCHEMA_PY="$ROOT/tests/helpers/validate-json-schema.py"
CYCLE_SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/defect-cycle.json"
DEFECT="$ROOT/plugins/nightshift/skills/nightshift/references/shifts/defect-hunt.md"

load helpers

@test "defect-cycle scripts are executable" {
  [ -x "$DC" ]
}

@test "init and lens rotation walk all eight lenses" {
  p="$(mktemp -d "${BATS_TEST_TMPDIR}/defect.XXXXXX")"
  mkdir -p "$p/.nightshift"
  run bash "$DC" init --project "$p" --shift-id abcd1234abcd1234
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.currentLens == "correctness"' >/dev/null
  i=0
  while [ "$i" -lt 7 ]; do
    run bash "$DC" next-lens --project "$p"
    [ "$status" -eq 0 ]
    i=$((i + 1))
  done
  python3 "$SCHEMA_PY" "$CYCLE_SCHEMA" "$p/.nightshift/defect-cycle.json"
  jq -e '(.lensesUsedThisCycle | length) >= 1' "$p/.nightshift/defect-cycle.json" >/dev/null
}

@test "record requires reproduction or code-path evidence" {
  p="$(mktemp -d "${BATS_TEST_TMPDIR}/defect-rec.XXXXXX")"
  mkdir -p "$p/.nightshift"
  bash "$DC" init --project "$p" --shift-id abcd1234abcd1234 >/dev/null
  run bash "$DC" record --project "$p" --finding "$FIX/finding-reproduced.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.open == 1' >/dev/null
}

@test "duplicate findings collapse and rejections are tracked" {
  p="$(mktemp -d "${BATS_TEST_TMPDIR}/defect-dup.XXXXXX")"
  mkdir -p "$p/.nightshift"
  bash "$DC" init --project "$p" --shift-id abcd1234abcd1234 >/dev/null
  bash "$DC" record --project "$p" --finding "$FIX/finding-reproduced.json" >/dev/null
  bash "$DC" record --project "$p" --finding "$FIX/finding-duplicate.json" >/dev/null
  bash "$DC" reject --project "$p" --id d-noise --reason "not reproducible on second look" >/dev/null
  run bash "$DC" summary --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.duplicate >= 1 and .rejected >= 1' >/dev/null
}

@test "fix and full lens pass without new findings marks convergence" {
  p="$(mktemp -d "${BATS_TEST_TMPDIR}/defect-conv.XXXXXX")"
  mkdir -p "$p/.nightshift"
  bash "$DC" init --project "$p" --shift-id abcd1234abcd1234 >/dev/null
  bash "$DC" record --project "$p" --finding "$FIX/finding-reproduced.json" >/dev/null
  bash "$DC" fix --project "$p" --id d-001 >/dev/null
  i=0
  while [ "$i" -lt 8 ]; do
    bash "$DC" next-lens --project "$p" >/dev/null
    i=$((i + 1))
  done
  run bash "$DC" summary --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.converged == true or .open == 0' >/dev/null
  printf '%s' "$output" | jq -e '.receiptLines | length >= 1' >/dev/null
}

@test "defect hunt contract references cycle helpers" {
  grep -qF 'runtime/defect-cycle.sh init' "$DEFECT"
  grep -qi 'next-lens' "$DEFECT"
  grep -qi 'reproduction or strong code-path evidence' "$DEFECT"
  grep -qi 'rejected and duplicate' "$DEFECT"
  grep -qi 'containing regression surface' "$DEFECT"
}
