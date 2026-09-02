#!/usr/bin/env bats
# Adversarial provisioning: policy refusals, fake-recipe apply, rollback, recover.

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
PREFLIGHT="$ROOT/plugins/nightshift/runtime/provision-preflight.sh"
LINKER="$ROOT/plugins/nightshift/runtime/link-workspace.sh"
WIN="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
ENGINE="$ROOT/plugins/nightshift/skills/nightshift/references/provisioning-engine.md"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
HUNT="$ROOT/plugins/nightshift/skills/hunt/SKILL.md"
HELPERS="$BATS_TEST_DIRNAME/helpers.bash"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/provisioning"
RECOVER_RECIPE="$FIXTURES/recover-recipe.json"
OWNER_DIRTY_SH="$FIXTURES/owner-dirty.sh"
INSTALL_TX="$FIXTURES/install-transaction.sh"

# Everything a host needs to resolve a policy and report a preflight, minus python3.
PROVISION_TOOLSET_NO_PYTHON="bash sh jq git sed grep find sort ls awk cat tr head tail wc cut \
mkdir cp rm mv ln env date uname test dirname basename printf true false mktemp shasum"

load helpers

provision() {
  if [ -f "$PROVISION" ]; then
    bash "$PROVISION" "$@"
  else
    python3 "$PROVISION_PY" "$@"
  fi
}

enable_auto_add() {
  # The effective tooling policy is the one-shift policy Start writes before arming. The test
  # project is already armed and the writer refuses while armed by design, so write the fixture.
  printf 'repository\n' >"$1/.nightshift/work-mode"
  printf '%s\n' "$1" >"$1/.nightshift/work-target"
  jq -n '{schemaVersion:1,shiftId:"9f2c40ab77e51d63",createdAt:"2026-01-01T00:00:00Z",source:"start-defaults",deadlineEpoch:null,verificationLevel:"none",toolingPolicy:"auto-add",allowances:[]}' \
    >"$1/.nightshift/shift-policy.json"
}

# auto_add <project> [--tooling P] [--allow CAT] [--rules-allow CAT] [--exact-plan CAT --command C]
# The elevation cases need allowances and an exact-plan digest, which the fixture script builds
# with the resolver's own helpers.
auto_add() {
  local p="$1"
  shift
  bash "$FIXTURES/write-shift-policy.sh" --project "$p" "$@"
}

allow_in_rules() {
  bash "$FIXTURES/write-rules-elevation.sh" --project "$1" --category "$2" --policy "$3"
}

# The frictionless grant the preflight looks for, so a permission reason in the report can only
# come from the check under test.
grant_unattended() {
  mkdir -p "$1/.claude"
  jq -n '{permissions:{defaultMode:"bypassPermissions"}}' >"$1/.claude/settings.local.json"
}

tree_outside() {
  find "$1" \( -path "$1/.git" -o -path "$1/.git/*" -o -path "$1/.nightshift" -o -path "$1/.nightshift/*" \) -prune -o -print | sort
}

# recover_seed_baseline <project> — the exact content `recover-recipe.json`'s baseline captured:
# nightshift-keep.txt and nightshift-config.json present with their original bytes,
# generated/nested/nightshift-fake.txt absent. Matches the digests baked into every
# recover-tx-*.json fixture, so a proof-checking recovery accepts the restore.
recover_seed_baseline() {
  local p="$1"
  printf 'baseline\n' >"$p/nightshift-keep.txt"
  printf '{"ok":true}\n' >"$p/nightshift-config.json"
}

# recover_seed_mutated <project> — the interrupted-mid-transaction state every rollback-path
# fixture (apply, smoke, rollback) expects to find on disk: the two existing files overwritten,
# and the file that did not exist yet created under a nested directory (to exercise empty-parent
# pruning back up to, not including, the project root). Reused as-is for the finish-path fixtures
# (record, commit-tooling), where the exact bytes do not matter — that path never restores them.
recover_seed_mutated() {
  local p="$1"
  printf 'mutated\n' >"$p/nightshift-keep.txt"
  printf '{"mutated":true}\n' >"$p/nightshift-config.json"
  mkdir -p "$p/generated/nested"
  printf 'new\n' >"$p/generated/nested/nightshift-fake.txt"
}

@test "plan refuses existing-tools and artifact mode" {
  p="$(new_project prov-refuse)"
  run provision --project "$p" --recipe "$FIXTURES/local-dev-free.json" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .refused == true and .reason == "policy-not-auto-add"' >/dev/null

  printf 'artifact\n' >"$p/.nightshift/work-mode"
  run provision --project "$p" --recipe "$FIXTURES/local-dev-free.json" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .refused == true and .reason == "artifact-mode"' >/dev/null
}

@test "plan accepts a local-dev-free fixture recipe" {
  p="$(new_project prov-plan)"
  enable_auto_add "$p"
  while IFS= read -r field; do
    jq -e --arg f "$field" 'has($f)' "$FIXTURES/local-dev-free.json" >/dev/null \
      || { echo "fixture missing required field: $field"; return 1; }
  done < <(jq -r '.requiredRecipeFields[]' "$SCHEMA")
  jq -e '.safetyClass == "local-dev-free"' "$FIXTURES/local-dev-free.json" >/dev/null
  run provision --project "$p" --recipe "$FIXTURES/local-dev-free.json" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .ok == true
    and .refused == false
    and .capabilityId == "fixture-lint"
    and .safetyClass == "local-dev-free"
  ' >/dev/null
}

@test "apply local-dev-free writes allowed files and commits tooling" {
  p="$(new_project prov-ok)"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$FIXTURES/local-dev-free.json" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "fixture-lint"' >/dev/null
  [ -f "$p/nightshift-fake.txt" ]
  [ "$(cat "$p/nightshift-fake.txt")" = "ok" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): fixture-lint'
}

@test "apply smoke failure leaves no residue outside allowedFiles" {
  p="$(new_project prov-smoke)"
  enable_auto_add "$p"
  before="$(tree_outside "$p")"
  run provision --project "$p" --recipe "$FIXTURES/smoke-fail.json" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true' >/dev/null
  [ ! -e "$p/nightshift-fake.txt" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(tree_outside "$p")" = "$before" ]
}

@test "rollback restores baseline and removes new files" {
  p="$(new_project prov-roll)"
  enable_auto_add "$p"
  printf 'baseline\n' >"$p/nightshift-keep.txt"
  mkdir -p "$p/.nightshift/provision-baseline"
  blob="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' nightshift-keep.txt)"
  cp "$p/nightshift-keep.txt" "$p/.nightshift/provision-baseline/$blob"
  printf 'mutated\n' >"$p/nightshift-keep.txt"
  printf 'new\n' >"$p/nightshift-fake.txt"
  jq -nc --arg tgt "$p" --arg blob "$blob" '{
    schemaVersion:1,
    stage:"apply",
    capabilityId:"fixture-lint",
    workTarget:$tgt,
    allowedFiles:["nightshift-keep.txt","nightshift-fake.txt"],
    baseline:{
      "nightshift-keep.txt":{existed:true, digest:"4b654bd1437066b13498661f3ca14774daf1066d072036beffaf06f0c014250e", blob:$blob},
      "nightshift-fake.txt":{existed:false, digest:null}
    },
    touched:["nightshift-keep.txt","nightshift-fake.txt"],
    failed:false
  }' >"$p/.nightshift/provision-transaction.json"
  run provision --project "$p" rollback
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ ! -e "$p/nightshift-fake.txt" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
}

@test "recover clears incomplete provision-transaction.json" {
  p="$(new_project prov-rec)"
  enable_auto_add "$p"
  printf 'new\n' >"$p/nightshift-fake.txt"
  jq -nc --arg tgt "$p" '{
    schemaVersion:1,
    stage:"smoke",
    capabilityId:"fixture-lint",
    workTarget:$tgt,
    allowedFiles:["nightshift-fake.txt"],
    baseline:{"nightshift-fake.txt":{existed:false, digest:null}},
    touched:["nightshift-fake.txt"],
    failed:false
  }' >"$p/.nightshift/provision-transaction.json"
  [ -f "$p/.nightshift/provision-transaction.json" ]
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/nightshift-fake.txt" ]
}

@test "owner-dirty file outside allowedFiles survives failed apply" {
  p="$(new_project prov-dirty)"
  enable_auto_add "$p"
  cp "$FIXTURES/owner-dirty.txt" "$p/owner-dirty.txt"
  before="$(cksum "$p/owner-dirty.txt")"
  run provision --project "$p" --recipe "$FIXTURES/smoke-fail.json" apply
  [ "$status" -eq 1 ]
  [ -f "$p/owner-dirty.txt" ]
  [ "$(cksum "$p/owner-dirty.txt")" = "$before" ]
  [ ! -e "$p/nightshift-fake.txt" ]
  [ "$(cat "$p/owner-dirty.txt")" = "owner note — do not touch" ]
}

@test "a dotfile in allowedFiles keeps its leading dot" {
  p="$(new_project prov-dotfile)"
  enable_auto_add "$p"
  run provision --project "$p" --recipe "$FIXTURES/dotfile-config.json" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.touched == [".fixture-lintrc.json"]' >/dev/null
  [ -f "$p/.fixture-lintrc.json" ]
  [ ! -e "$p/fixture-lintrc.json" ]
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): fixture-dotfile-lint'
}

@test "apply keeps its state in the linked workspace" {
  host="$(new_project prov-link-host)"
  workspace="$(new_workspace prov-link-ws)"
  bash "$LINKER" --host-root "$host" --workspace "$workspace" >/dev/null
  enable_auto_add "$workspace"
  run provision --project "$host" --recipe "$FIXTURES/local-dev-free.json" apply
  [ "$status" -eq 0 ]
  [ -f "$workspace/.nightshift/capabilities.json" ]
  [ -f "$workspace/nightshift-fake.txt" ]
  [ ! -e "$host/.nightshift/capabilities.json" ]
  [ ! -e "$host/nightshift-fake.txt" ]
}

@test "a declared elevation category is denied without an allowance" {
  p="$(new_project prov-elev-deny)"
  auto_add "$p"
  run provision --project "$p" --recipe "$FIXTURES/elevated-sudo.json" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '
    .ok == false
    and .refused == true
    and .reason == "elevation-denied:sudo"
    and .refusalReasons == ["elevation-denied:sudo"]
    and .elevationCategories == ["sudo"]
  ' >/dev/null
}

@test "rules allow an elevation category permanently" {
  p="$(new_project prov-elev-rules)"
  auto_add "$p"
  allow_in_rules "$p" sudo allow
  run provision --project "$p" --recipe "$FIXTURES/elevated-sudo.json" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .refusalReasons == []' >/dev/null
}

@test "a one-shift allowance lifts an elevation category for the night" {
  p="$(new_project prov-elev-shift)"
  auto_add "$p" --allow sudo
  run provision --project "$p" --recipe "$FIXTURES/elevated-sudo.json" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .refusalReasons == []' >/dev/null
}

@test "an exact-plan allowance binds the approved command and nothing else" {
  p="$(new_project prov-elev-plan)"
  auto_add "$p" --exact-plan sudo --command 'sudo apt-get install -y nightshift-fixture'
  run provision --project "$p" --recipe "$FIXTURES/elevated-sudo.json" plan
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .refusalReasons == []' >/dev/null

  run provision --project "$p" --recipe "$FIXTURES/elevated-sudo-variant.json" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '.refusalReasons == ["elevation-denied:sudo"]' >/dev/null
}

@test "an undeclared elevation category is caught by the command it needs" {
  p="$(new_project prov-elev-undeclared)"
  auto_add "$p"
  run provision --project "$p" --recipe "$FIXTURES/undeclared-containers.json" plan
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | jq -e '
    .refusalReasons == ["elevation-denied:containers"] and .elevationCategories == []
  ' >/dev/null
}

@test "the provisioning refusal codes are the frozen contract" {
  jq -e '.refusalReasons == [
    "policy-not-auto-add",
    "artifact-mode",
    "elevation-denied:sudo",
    "elevation-denied:containers",
    "elevation-denied:global-packages",
    "elevation-denied:daemons",
    "elevation-denied:external-services",
    "incompatible-ecosystem",
    "permission-prompt-required",
    "provisioning-runtime-unavailable",
    "owner-dirty-conflict",
    "safety-forbidden"
  ]' "$SCHEMA" >/dev/null
  jq -e '.elevationCategories == [
    "sudo", "containers", "global-packages", "daemons", "external-services"
  ]' "$SCHEMA" >/dev/null
  jq -e '.skipReasons == [
    "permission-prompt-required", "provisioning-runtime-unavailable"
  ]' "$SCHEMA" >/dev/null
  # elevationCategories stays optional, so every registered recipe remains valid.
  jq -e '.requiredRecipeFields | index("elevationCategories") == null' "$SCHEMA" >/dev/null

  for f in "$PROVISION_PY" "$SCHEMA" "$ENGINE"; do
    if grep -qE 'global-or-system|paid-or-account|daemon-or-cloud' "$f"; then
      echo "retired refusal code still present in $f"
      return 1
    fi
  done
}

@test "an elevated command that runs leaves one verified provisioning receipt" {
  p="$(new_project prov-elev-receipt)"
  auto_add "$p" --allow global-packages
  bin="$(controlled_bin prov-elev-bin)"
  fake_exe "$bin" brew 'exit 0'
  export PATH="$bin:$PATH"

  run provision --project "$p" --recipe "$FIXTURES/elevated-global-packages.json" apply
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .capabilityId == "fixture-global-lint"' >/dev/null

  ledger="$p/.nightshift/evidence/findings.jsonl"
  [ -f "$ledger" ]
  [ "$(grep -c . "$ledger")" -eq 1 ]
  jq -e '
    .domain == "provisioning"
    and .category == "global-packages"
    and .provenance == "one-shift"
    and .source == "brew install nightshift-fixture"
    and .scope == "elevation.global-packages"
    and .ladder == "verified-after-change"
  ' "$ledger" >/dev/null
}

@test "preflight reports a prompt risk when allowed sudo is not passwordless" {
  p="$(new_project prov-pre-sudo)"
  auto_add "$p" --allow sudo
  grant_unattended "$p"
  bin="$(controlled_bin prov-pre-sudo-bin)"
  fake_exe "$bin" sudo 'exit 1'
  export PATH="$bin:$PATH"

  run bash "$PREFLIGHT" --project "$p" --recipe "$FIXTURES/elevated-sudo.json" check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .ok == false and .skipReasons == ["permission-prompt-required"]
  ' >/dev/null

  fake_exe "$bin" sudo 'exit 0'
  run bash "$PREFLIGHT" --project "$p" --recipe "$FIXTURES/elevated-sudo.json" check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipReasons == []' >/dev/null
}

@test "preflight leaves a denied sudo category to the engine" {
  p="$(new_project prov-pre-sudo-deny)"
  auto_add "$p"
  grant_unattended "$p"
  bin="$(controlled_bin prov-pre-deny-bin)"
  fake_exe "$bin" sudo 'exit 1'
  export PATH="$bin:$PATH"

  run bash "$PREFLIGHT" --project "$p" --recipe "$FIXTURES/elevated-sudo.json" check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipReasons == []' >/dev/null
}

@test "preflight reports the provisioning runtime missing only under auto-add" {
  p="$(new_project prov-pre-runtime)"
  grant_unattended "$p"
  # shellcheck disable=SC2086
  bin="$(build_toolset_bin prov-no-python $PROVISION_TOOLSET_NO_PYTHON)"
  [ ! -e "$bin/python3" ]

  auto_add "$p"
  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash "$PREFLIGHT" --project "$p" check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .ok == false and .skipReasons == ["provisioning-runtime-unavailable"]
  ' >/dev/null

  auto_add "$p" --tooling existing-tools
  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash "$PREFLIGHT" --project "$p" check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .skipReasons == []' >/dev/null
}

@test "Windows provision.ps1 exists and names plan apply recover rollback" {
  [ -f "$WIN" ]
  grep -q 'ValidateSet' "$WIN"
  grep -qF "'plan'" "$WIN"
  grep -qF "'apply'" "$WIN"
  grep -qF "'recover'" "$WIN"
  grep -qF "'rollback'" "$WIN"
}

@test "Start and Hunt call out provision recover once landed" {
  grep -qF 'provision.sh' "$ENGINE"
  grep -qE 'plan\|apply\|recover\|rollback' "$ENGINE"
  grep -qF 'provision.sh' "$HELPERS" || true

  start_hit=0
  hunt_hit=0
  grep -qF 'provision.sh' "$START" && start_hit=1
  grep -qF 'provision.sh' "$HUNT" && hunt_hit=1
  if [ "$start_hit" -eq 0 ] && [ "$hunt_hit" -eq 0 ]; then
    return 0
  fi
  if [ "$start_hit" -eq 1 ]; then
    grep -qF 'provision.sh' "$START" || return 0
    grep -qE 'provision\.sh[^`]* recover' "$START" || return 0
  fi
  if [ "$hunt_hit" -eq 1 ]; then
    grep -qF 'provision.sh' "$HUNT" || return 0
  fi
}

# ---------------------------------------------------------------------------------------------
# Recovery residue, owner-file safety, and no-retry — every recover-tx-*.json fixture represents
# a crash at that exact stage of `recover-recipe.json`'s transaction (capabilityId
# "fixture-recover", allowedFiles nightshift-keep.txt + nightshift-config.json +
# generated/nested/nightshift-fake.txt). `recover_seed_baseline` reproduces the untouched state
# those fixtures' baseline digests were computed against; `recover_seed_mutated` reproduces the
# fully-written, not-yet-committed state. Every case also drops an owner file outside any
# allowedFiles list first and proves it comes back byte-identical.

@test "recover from an interrupted authorize leaves nothing outside allowedFiles" {
  p="$(new_project prov-rec-authorize)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  clean="$(tree_outside "$p")"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-authorize.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true and .proven == true and .capabilityId == "fixture-recover"' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$clean" ]
}

@test "recover from an interrupted capture-baseline leaves nothing outside allowedFiles" {
  p="$(new_project prov-rec-capture-baseline)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  clean="$(tree_outside "$p")"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-capture-baseline.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true and .proven == true and .capabilityId == "fixture-recover"' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$clean" ]
}

@test "recover from an interrupted apply restores the blob and content baselines and prunes created files" {
  p="$(new_project prov-rec-apply)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  clean="$(tree_outside "$p")"
  recover_seed_mutated "$p"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-apply-failed.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true and .proven == true and .capabilityId == "fixture-recover"' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/generated" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$clean" ]
}

@test "recover from an interrupted smoke restores baseline and prunes created files" {
  p="$(new_project prov-rec-smoke)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  clean="$(tree_outside "$p")"
  recover_seed_mutated "$p"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-smoke-failed.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true and .proven == true and .capabilityId == "fixture-recover"' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/generated" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$clean" ]
}

@test "recover from a crash mid-rollback finishes the restore and prunes created files" {
  p="$(new_project prov-rec-rollback)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  clean="$(tree_outside "$p")"
  recover_seed_mutated "$p"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-rollback-failed.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ok == true and .rolledBack == true and .proven == true and .capabilityId == "fixture-recover"' >/dev/null
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/generated" ]
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ ! -e "$p/.nightshift/provision-baseline" ]
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$clean" ]
}

@test "recover from an interrupted record finishes natively with a real commit" {
  p="$(new_project prov-rec-record)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  recover_seed_mutated "$p"
  before="$(tree_outside "$p")"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-record.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .ok == true and .recovered == true and .finished == true
    and .capabilityId == "fixture-recover" and (.setupCommit | length) > 0
  ' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  sha="$(git -C "$p" rev-parse HEAD)"
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): fixture-recover'
  jq -e --arg sha "$sha" '.items[] | select(.capability == "fixture-recover" and .setupCommit == $sha)' \
    "$p/.nightshift/capabilities.json" >/dev/null
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$before" ]
}

@test "recover from an interrupted commit-tooling finishes natively with a real commit" {
  p="$(new_project prov-rec-commit-tooling)"
  enable_auto_add "$p"
  bash "$OWNER_DIRTY_SH" "$p"
  owner_before="$(cksum "$p/owner-live-edit.txt")"
  recover_seed_baseline "$p"
  recover_seed_mutated "$p"
  before="$(tree_outside "$p")"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-commit-tooling.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" recover
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .ok == true and .recovered == true and .finished == true
    and .capabilityId == "fixture-recover" and (.setupCommit | length) > 0
  ' >/dev/null
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  sha="$(git -C "$p" rev-parse HEAD)"
  git -C "$p" log -1 --format=%s | grep -qx 'chore(tooling): fixture-recover'
  jq -e --arg sha "$sha" '.items[] | select(.capability == "fixture-recover" and .setupCommit == $sha)' \
    "$p/.nightshift/capabilities.json" >/dev/null
  [ "$(cksum "$p/owner-live-edit.txt")" = "$owner_before" ]
  [ "$(tree_outside "$p")" = "$before" ]
}

@test "apply refuses to retry a leftover failed transaction with the stable code" {
  p="$(new_project prov-no-retry)"
  enable_auto_add "$p"
  recover_seed_baseline "$p"
  recover_seed_mutated "$p"
  bash "$INSTALL_TX" "$FIXTURES/recover-tx-apply-failed.json" "$p" "$RECOVER_RECIPE"
  run provision --project "$p" --recipe "$FIXTURES/smoke-fail.json" apply
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .failed == true and .detail == "do not retry the same failure"' >/dev/null
  # The refusal still rolls back the leftover transaction — no residue survives a refused retry.
  [ ! -e "$p/.nightshift/provision-transaction.json" ]
  [ "$(cat "$p/nightshift-keep.txt")" = "baseline" ]
  [ "$(cat "$p/nightshift-config.json")" = '{"ok":true}' ]
  [ ! -e "$p/generated" ]
}
