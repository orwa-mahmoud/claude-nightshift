#!/usr/bin/env bats
# Versioned evidence ledger.

ROOT="$BATS_TEST_DIRNAME/.."
EV="$ROOT/plugins/nightshift/runtime/evidence.sh"
WIN="$ROOT/plugins/nightshift/runtime/windows/evidence.ps1"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/finding.json"
EXPORT="$ROOT/plugins/nightshift/runtime/export-support.sh"

load helpers

sample() {
  jq -nc --arg id "$1" --arg host "${2:-claude}" '{
    schemaVersion:1, id:$id, domain:"lint", sourceClass:"eslint",
    source:"eslint --version", scope:"src/", severity:"medium",
    confidence:"high", impact:"developer", status:"open",
    ladder:"observed", locator:"src/app.js:3", digest:"abc",
    firstSeen:"2026-09-01T00:00:00Z", lastChecked:"2026-09-01T00:00:00Z",
    action:"fix", host:$host, workTarget:"/repo"
  }'
}

@test "a missing ledger is valid in an existing workspace" {
  p="$(new_project ev)"
  run bash "$EV" --project "$p" validate
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'no ledger'
}

@test "init append validate render and tsv export round-trip" {
  p="$(new_project ev2)"
  run bash "$EV" --project "$p" init
  [ "$status" -eq 0 ]
  [ -f "$p/.nightshift/evidence/findings.jsonl" ]
  rec="$(sample f1 claude)"
  run bash "$EV" --project "$p" append --record "$rec" --raw "eslint output"
  [ "$status" -eq 0 ]
  [ -f "$p/.nightshift/evidence/raw/f1.txt" ]
  run bash "$EV" --project "$p" validate
  [ "$status" -eq 0 ]
  run bash "$EV" --project "$p" render
  [ "$status" -eq 0 ]
  grep -q '| f1 |' "$p/.nightshift/evidence/findings.md"
  run bash "$EV" --project "$p" export-tsv
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q $'^id\tdomain'
  printf '%s\n' "$output" | grep -q $'^f1\tlint'
}

@test "identical records validate across host adapters" {
  p="$(new_project ev3)"
  bash "$EV" --project "$p" init >/dev/null
  bash "$EV" --project "$p" append --record "$(sample f2 claude)" >/dev/null
  bash "$EV" --project "$p" append --record "$(sample f3 codex)" >/dev/null
  bash "$EV" --project "$p" append --record "$(sample f4 cursor)" >/dev/null
  bash "$EV" --project "$p" validate
}

@test "malformed and secret-bearing evidence is rejected" {
  p="$(new_project ev4)"
  bash "$EV" --project "$p" init >/dev/null
  rec="$(sample f5 claude | jq '.severity="nope"')"
  run bash "$EV" --project "$p" append --record "$rec"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'invalid severity'
  rec="$(sample f6 claude | jq '. + {token:"secret", action:"token=supersecret"}')"
  # action with secret pattern
  rec="$(jq -nc '{
    schemaVersion:1, id:"f6", domain:"lint", sourceClass:"x", source:"x",
    scope:"s", severity:"low", confidence:"low", impact:"none", status:"open",
    ladder:"declared", locator:"f", digest:"d", firstSeen:"t", lastChecked:"t",
    action:"api_key=abcd", host:"claude", workTarget:"/r"
  }')"
  run bash "$EV" --project "$p" append --record "$rec"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'secret pattern'
}

@test "raw unrestricted remote locators are rejected unless marked untrusted" {
  p="$(new_project ev5)"
  bash "$EV" --project "$p" init >/dev/null
  rec="$(jq -nc '{
    schemaVersion:1, id:"f7", domain:"seo", sourceClass:"crawl", source:"curl",
    scope:"site", severity:"low", confidence:"low", impact:"user", status:"open",
    ladder:"declared", locator:"https://example.invalid/x", digest:"d",
    firstSeen:"t", lastChecked:"t", action:"", host:"claude", workTarget:"/r"
  }')"
  run bash "$EV" --project "$p" append --record "$rec"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'untrusted'
  rec="$(printf '%s' "$rec" | jq '.untrusted=true')"
  run bash "$EV" --project "$p" append --record "$rec"
  [ "$status" -eq 0 ]
}

@test "ladder promotion by prose is rejected" {
  p="$(new_project ev6)"
  bash "$EV" --project "$p" init >/dev/null
  bash "$EV" --project "$p" append --record "$(sample f8 claude)" >/dev/null
  rec="$(sample f8 claude | jq '.ladder="measured" | .promoteBy="prose" | .digest="x"')"
  run bash "$EV" --project "$p" append --record "$rec"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'prose'
}

@test "migrate is a no-op on a workspace with no ledger" {
  p="$(new_project ev7)"
  run bash "$EV" --project "$p" migrate
  [ "$status" -eq 0 ]
}

@test "Windows helper exists and names the same commands" {
  [ -f "$WIN" ]
  grep -q 'ValidateSet' "$WIN"
  grep -q 'init' "$WIN"
  grep -q 'export-tsv' "$WIN"
  grep -qi 'does not verify a Nightshift tick' "$WIN"
}

@test "support bundle omits evidence raw output" {
  grep -q 'evidence ledger raw output' "$EXPORT"
  grep -q 'evidence ledger raw output' "$ROOT/plugins/nightshift/runtime/windows/export-support.ps1"
}
