#!/usr/bin/env bats
# Specialist seo-performance recipes: admission, evidence-only receipts, and fixture matrices.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PWPROV="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/recipes/specialist/seo-perf"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"

load helpers

provision() {
  if [ -f "$PROVISION" ]; then
    bash "$PROVISION" "$@"
  else
    python3 "$PROVISION_PY" "$@"
  fi
}

enable_auto_add() {
  printf 'repository\n' >"$1/.nightshift/work-mode"
  printf '%s\n' "$1" >"$1/.nightshift/work-target"
  jq -n '{
    schemaVersion: 1, shiftId: "9f2c40ab77e51d63", createdAt: "2026-01-01T00:00:00Z",
    source: "start-defaults", deadlineEpoch: null, verificationLevel: "none",
    toolingPolicy: "auto-add", allowances: []
  }' >"$1/.nightshift/shift-policy.json"
}

grant_unattended() {
  mkdir -p "$1/.claude"
  jq -n '{permissions:{defaultMode:"bypassPermissions"}}' >"$1/.claude/settings.local.json"
}

recipe_path() {
  printf '%s/javascript-typescript/seo-performance.json' "$REGISTRY"
}

setup_fake_npm() {
  FAKE_NPM_BIN="$BATS_TEST_TMPDIR/fake-npm-bin"
  mkdir -p "$FAKE_NPM_BIN"
  sed 's/@EXIT@/0/' "$FIXTURES/fake-npm.sh" >"$FAKE_NPM_BIN/npm"
  chmod +x "$FAKE_NPM_BIN/npm"
  export PATH="$FAKE_NPM_BIN:$PATH"
}

setup_fake_npm_fail() {
  FAKE_NPM_BIN="$BATS_TEST_TMPDIR/fake-npm-bin-fail"
  mkdir -p "$FAKE_NPM_BIN"
  sed 's/@EXIT@/17/' "$FIXTURES/fake-npm.sh" >"$FAKE_NPM_BIN/npm"
  chmod +x "$FAKE_NPM_BIN/npm"
  export PATH="$FAKE_NPM_BIN:$PATH"
}

@test "seo-performance recipe carries admission evidence and specialist enabledShifts fallback" {
  path="$(recipe_path)"
  jq -e '
    .capabilityId == "seo-performance" and
    .admission.contract == "seo-audit" and
    .admission.fixture == "tests/fixtures/recipes/specialist/seo-perf/static-site" and
    (.admission.demand | test("evals/cases/v1.json")) and
    (.enabledShifts | length) == 1 and
    .enabledShifts[0].contract == "seo-audit" and
    (.enabledShifts[0].fallback | test("audit owner-supplied local files only"))
  ' "$path" >/dev/null
  jq -e '
    .permissionRequirements[] | select(test("evidence lines only"))
  ' "$path" >/dev/null
  jq -e '
    .permissionRequirements[] | select(test("rankings")) | select(test("never"))
  ' "$path" >/dev/null
}

@test "seo-performance detection refuses a tree with no html files" {
  p="$(new_project rsp-no-html)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  rm -f "$p"/*.html
  git -C "$p" add -A
  git -C "$p" commit -q -m "drop html"
  enable_auto_add "$p"
  grant_unattended "$p"
  setup_fake_npm
  run provision --project "$p" --recipe "$(recipe_path)" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
}

@test "seo-performance review-first plan refuses apply policy and names exact writes" {
  p="$(new_project rsp-plan)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  enable_auto_add "$p"
  jq '.toolingPolicy = "review-missing"' "$p/.nightshift/shift-policy.json" >"$p/.nightshift/shift-policy.tmp"
  mv "$p/.nightshift/shift-policy.tmp" "$p/.nightshift/shift-policy.json"
  run provision --project "$p" --recipe "$(recipe_path)" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refused == true and .reason == "policy-not-auto-add"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilityId == "seo-performance"' >/dev/null
  printf '%s\n' "$output" | jq -e '.minimalConfig | has(".htmlhintrc")' >/dev/null
}

@test "seo-performance apply with the scripted npm manager records inventory without a tooling commit" {
  setup_fake_npm
  p="$(new_project rsp-apply)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path)" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$(recipe_path)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "seo-performance"' >/dev/null
  [ -f "$p/.htmlhintrc" ]
  jq -e '.items[] | select(.capability == "seo-performance")' "$p/.nightshift/capabilities.json" >/dev/null
}

@test "seo-performance already configured defers to repository tooling" {
  setup_fake_npm
  p="$(new_project rsp-skip)"
  bash "$FIXTURES/already-configured.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "seo-performance package failure rolls back and leaves no transaction" {
  setup_fake_npm_fail
  p="$(new_project rsp-fail)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path)" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -f "$p/.htmlhintrc" ]
}

@test "seo-performance red baseline smoke reports lint findings as working evidence" {
  setup_fake_npm
  p="$(new_project rsp-red)"
  bash "$FIXTURES/make-static-site.sh" "$p" red-baseline
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "seo-performance"' >/dev/null
}

@test "seo-performance fallback sentence is present when tooling is absent from the tree" {
  p="$(new_project rsp-fallback)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$(recipe_path)" plan
  [ "$status" -eq 0 ]
  fallback="$(jq -r '.enabledShifts[0].fallback // empty' "$(recipe_path)")"
  [ -n "$fallback" ]
  printf '%s\n' "$fallback" | grep -q 'audit owner-supplied local files only'
  printf '%s\n' "$fallback" | grep -qv 'ranking'
}

@test "seo-performance smoke receipts stay evidence-only strings" {
  path="$(recipe_path)"
  jq -r '.smoke.command' "$path" | grep -q 'evidence: file-size'
  jq -r '.smoke.command' "$path" | grep -q 'evidence: local-timing'
  jq -r '.smoke.command' "$path" | grep -q 'htmlhint'
  jq -r '.permissionRequirements[]' "$path" | grep -q 'never rankings, traffic, field data, or strategy'
}

@test "native and bash plans agree byte-for-byte on the seo-performance recipe" {
  command -v pwsh >/dev/null || skip "pwsh is not on PATH"
  p="$(new_project rsp-parity)"
  bash "$FIXTURES/make-static-site.sh" "$p"
  enable_auto_add "$p"
  bash_out="$BATS_TEST_TMPDIR/bash-seo-plan.json"
  pwsh_out="$BATS_TEST_TMPDIR/pwsh-seo-plan.json"
  provision --project "$p" --recipe "$(recipe_path)" plan >"$bash_out"
  run pwsh -NoProfile -File "$PWPROV" -Project "$p" plan -Recipe "$(recipe_path)"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$pwsh_out"
  cmp -s "$bash_out" "$pwsh_out"
}

@test "seo-performance fixture static site is a minimal html tree for seo-audit evidence" {
  [ -f "$FIXTURES/static-site/index.html" ]
  [ -f "$FIXTURES/static-site/about.html" ]
  grep -q '<title>' "$FIXTURES/static-site/index.html"
  grep -q 'styles.css' "$FIXTURES/static-site/index.html"
}
