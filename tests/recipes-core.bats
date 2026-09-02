#!/usr/bin/env bats
# Core capability recipes: registry contract, review-first plans, and fixture matrices.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PWPROV="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
REGISTRY="$ROOT/plugins/nightshift/skills/nightshift/references/recipes"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/recipes"
PROV_FIX="$BATS_TEST_DIRNAME/fixtures/provisioning"

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
  printf '%s/%s/%s.json' "$REGISTRY" "$1" "$2"
}

setup_fake_go() {
  FAKE_GO_BIN="$BATS_TEST_TMPDIR/fake-go-bin"
  mkdir -p "$FAKE_GO_BIN"
  ln -sf "$FIXTURES/go/fake-go.sh" "$FAKE_GO_BIN/go"
  ln -sf "$FIXTURES/go/fake-go.sh" "$FAKE_GO_BIN/gofmt"
  export PATH="$FAKE_GO_BIN:$PATH"
  export NS_FAKE_MODE=green
}

@test "every registered recipe carries the frozen contract and maintenance provenance" {
  while IFS= read -r field; do
    [ -n "$field" ] || continue
    req="$req $field"
  done < <(jq -r '.requiredRecipeFields[]' "$SCHEMA")
  while IFS= read -r field; do
    [ -n "$field" ] || continue
    maint="$maint $field"
  done < <(jq -r '.maintenanceFields[]?' "$SCHEMA")
  while IFS= read -r path; do
    for field in $req; do
      jq -e --arg f "$field" 'has($f)' "$path" >/dev/null \
        || { echo "$path missing $field"; return 1; }
    done
    for field in $maint; do
      jq -e --arg f "$field" 'has($f)' "$path" >/dev/null \
        || { echo "$path missing maintenance $field"; return 1; }
    done
  done < <(find "$REGISTRY" -name '*.json' ! -name index.json | sort)
}

@test "review-first plan for make test names exact writes and refuses apply policy" {
  p="$(new_project rc-make-plan)"
  bash "$FIXTURES/make/minimal-makefile.sh" "$p"
  enable_auto_add "$p"
  jq '.toolingPolicy = "review-missing"' "$p/.nightshift/shift-policy.json" >"$p/.nightshift/shift-policy.tmp"
  mv "$p/.nightshift/shift-policy.tmp" "$p/.nightshift/shift-policy.json"
  run provision --project "$p" --recipe "$(recipe_path make test)" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refused == true and .reason == "policy-not-auto-add"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilityId == "test" and (.smoke.command | test("make -n test"))' >/dev/null
}

@test "make test plans clean under auto-add and apply stays a dry run" {
  command -v make >/dev/null || skip "make is not on PATH"
  p="$(new_project rc-make-apply)"
  bash "$FIXTURES/make/minimal-makefile.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path make test)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .refused == false and .capabilityId == "test"' >/dev/null
  run provision --project "$p" --recipe "$(recipe_path make test)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "test"' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
}

@test "go test apply with the scripted toolchain records inventory without a tooling commit" {
  setup_fake_go
  p="$(new_project rc-go-apply)"
  bash "$FIXTURES/go/minimal-module.sh" "$p"
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path go test)" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$(recipe_path go test)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "test" and (.setupCommit | length) == 0' >/dev/null
  jq -e '.items[] | select(.capability == "test")' "$p/.nightshift/capabilities.json" >/dev/null
}

@test "go test skips when the repository already carries the setup commit" {
  setup_fake_go
  p="$(new_project rc-go-skip)"
  bash "$FIXTURES/go/already-configured.sh" "$p" test
  enable_auto_add "$p"
  grant_unattended "$p"
  run provision --project "$p" --recipe "$(recipe_path go test)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "python uv test provisions through the fixture manager" {
  p="$(new_project rc-py-uv)"
  bash "$FIXTURES/python/make-project.sh" "$p" uv
  enable_auto_add "$p"
  grant_unattended "$p"
  export VIRTUAL_ENV="$p/.venv"
  export PATH="$p/.venv/bin:$PATH"
  run provision --project "$p" --recipe "$(recipe_path python test)" plan
  [ "$status" -eq 0 ]
  run provision --project "$p" --recipe "$(recipe_path python test)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "test"' >/dev/null
  [ -f "$p/pytest.ini" ]
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): test'
}

@test "python already-configured defers to repository tooling" {
  p="$(new_project rc-py-skip)"
  bash "$FIXTURES/python/make-project.sh" "$p" already-configured
  git -C "$p" commit -q --allow-empty -m "chore(tooling): test"
  enable_auto_add "$p"
  grant_unattended "$p"
  export VIRTUAL_ENV="$p/.venv"
  export PATH="$p/.venv/bin:$PATH"
  run provision --project "$p" --recipe "$(recipe_path python test)" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipped == "already-present"' >/dev/null
}

@test "python package failure rolls back and leaves no transaction" {
  p="$(new_project rc-py-fail)"
  bash "$FIXTURES/python/make-project.sh" "$p" uv 17
  enable_auto_add "$p"
  grant_unattended "$p"
  export VIRTUAL_ENV="$p/.venv"
  export PATH="$p/.venv/bin:$PATH"
  run provision --project "$p" --recipe "$(recipe_path python test)" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -f "$p/pytest.ini" ]
}

@test "javascript-typescript test plans on a decidable lockfile" {
  p="$(new_project rc-js-plan)"
  bash "$FIXTURES/javascript-typescript/minimal-npm.sh" "$p"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$(recipe_path javascript-typescript test)" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "test"' >/dev/null
}

@test "native and bash plans agree byte-for-byte on the make test recipe" {
  command -v pwsh >/dev/null || skip "pwsh is not on PATH"
  command -v make >/dev/null || skip "make is not on PATH"
  p="$(new_project rc-parity)"
  bash "$FIXTURES/make/minimal-makefile.sh" "$p"
  enable_auto_add "$p"
  bash_out="$BATS_TEST_TMPDIR/bash-plan.json"
  pwsh_out="$BATS_TEST_TMPDIR/pwsh-plan.json"
  provision --project "$p" --recipe "$(recipe_path make test)" plan >"$bash_out"
  run pwsh -NoProfile -File "$PWPROV" -Project "$p" plan -Recipe "$(recipe_path make test)"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$pwsh_out"
  cmp -s "$bash_out" "$pwsh_out"
}
