#!/usr/bin/env bats
# Read-only capability registry and detector.

ROOT="$BATS_TEST_DIRNAME/.."
DETECT="$ROOT/plugins/nightshift/runtime/detect-capabilities.sh"
REQ="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/catalog-requirements.json"
CAPS="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capabilities.json"
SHIFTS="$ROOT/plugins/nightshift/skills/nightshift/references/shifts"
FIXTURES="$ROOT/evals/fixtures/v1"

load helpers

@test "every catalog entry declares capability requirements" {
  jq -e '.schemaVersion == 1' "$REQ" >/dev/null
  for f in "$SHIFTS"/*.md; do
    id="$(basename "$f" .md)"
    jq -e --arg id "$id" '.contracts | has($id)' "$REQ" >/dev/null \
      || { echo "missing requirements: $id"; return 1; }
    jq -e --arg id "$id" '
      .contracts[$id] | (
        (.requires | type) == "array"
        and (.requiresAny | type) == "array"
        and (
          (.fallback | type) == "string"
          or .fallback == null
          or .tooling == "none"
        )
      )
    ' "$REQ" >/dev/null || { echo "incomplete requirements: $id"; return 1; }
  done
}

@test "the capability registry lists the required domains" {
  for cap in test coverage lint typecheck dead-code accessibility security \
    api-schema localization documentation-link benchmark mutation-fuzz \
    seo-performance source-export connector owner-gates scripts ci; do
    jq -e --arg c "$cap" '.capabilities | index($c)' "$CAPS" >/dev/null \
      || { echo "registry missing $cap"; return 1; }
  done
  jq -e '.provisioningDefault == "existing-tools"' "$CAPS" >/dev/null
}

@test "the same fixture normalizes identically across host adapters" {
  p="$(new_project js)"
  cp "$FIXTURES/repo-js/package.json" "$p/package.json"
  mkdir -p "$p/tests"
  cp "$FIXTURES/repo-js/tests/addition.test.js" "$p/tests/addition.test.js"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  a="$BATS_TEST_TMPDIR/claude.json"
  b="$BATS_TEST_TMPDIR/codex.json"
  c="$BATS_TEST_TMPDIR/cursor.json"
  bash "$DETECT" --project "$p" --host claude --normalize >"$a"
  bash "$DETECT" --project "$p" --host codex --normalize >"$b"
  bash "$DETECT" --project "$p" --host cursor --normalize >"$c"
  diff -u "$a" "$b"
  diff -u "$b" "$c"
  jq -e '.capabilities.test.status == "available-and-verified"' "$a" >/dev/null
  jq -e '.contracts["coverage-hunt"].applies == true' "$a" >/dev/null
}

@test "artifact mode reports file capabilities and never repository tools" {
  w="$BATS_TEST_TMPDIR/artifact"
  mkdir -p "$w/.nightshift"
  printf 'artifact\n' >"$w/.nightshift/work-mode"
  printf '%s\n' "$w" >"$w/.nightshift/work-target"
  cp "$FIXTURES/artifact-notes/notes.md" "$w/notes.md"
  cp "$FIXTURES/artifact-notes/index.html" "$w/index.html"
  run bash "$DETECT" --project "$w" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.workMode == "artifact"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities["local-markdown"].status == "available-and-verified"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities.test.status == "unavailable"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities.test.reason | test("artifact mode")' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts["coverage-hunt"].applies == false' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts["seo-audit"].applies == true' >/dev/null
}

@test "a package name without a usable command is not treated as verified tooling" {
  p="$(new_project named)"
  printf '%s\n' '{"name":"has-eslint-dep","devDependencies":{"eslint":"9.0.0"}}' >"$p/package.json"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  run env PATH="/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.capabilities.lint.status == "unavailable"' >/dev/null
}

@test "a present command that fails --version is failing, not missing" {
  p="$(new_project broken)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'echo broken >&2' 'exit 7' >"$bin/eslint"
  chmod +x "$bin/eslint"
  printf '%s\n' '{"scripts":{"lint":"eslint ."}}' >"$p/package.json"
  run env PATH="$bin:/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  # declared script still verifies; force probe of eslint via PATH by removing scripts
  printf '%s\n' '{"name":"x"}' >"$p/package.json"
  run env PATH="$bin:/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.capabilities.lint.status == "available-but-failing"' >/dev/null
}

@test "detection does not write or install anything in the work target" {
  p="$(new_project ro)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  printf '%s\n' '{"name":"ro"}' >"$p/package.json"
  before="$(find "$p" -print | sort)"
  bash "$DETECT" --project "$p" --host claude >/dev/null
  after="$(find "$p" -print | sort)"
  [ "$before" = "$after" ]
}

@test "unsupported environment explains that quality cannot gather toolchain evidence" {
  p="$(new_project empty)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  run env PATH="/usr/bin:/bin" bash "$DETECT" --project "$p" --host cursor
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.contracts.quality.status == "fallback-only"' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts.quality.reason | test("fallback")' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts.quality.missing | length > 0' >/dev/null
}
