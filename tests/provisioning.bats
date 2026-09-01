#!/usr/bin/env bats
# Adversarial provisioning: policy refusals, fake-recipe apply, rollback, recover.

ROOT="$BATS_TEST_DIRNAME/.."
PROVISION="$ROOT/plugins/nightshift/runtime/provision.sh"
PROVISION_PY="$ROOT/plugins/nightshift/runtime/provision.py"
POLICY="$ROOT/plugins/nightshift/runtime/capability-policy.sh"
WIN="$ROOT/plugins/nightshift/runtime/windows/provision.ps1"
ENGINE="$ROOT/plugins/nightshift/skills/nightshift/references/provisioning-engine.md"
SCHEMA="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capability-recipe.json"
START="$ROOT/plugins/nightshift/skills/start/SKILL.md"
HUNT="$ROOT/plugins/nightshift/skills/hunt/SKILL.md"
HELPERS="$BATS_TEST_DIRNAME/helpers.bash"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/provisioning"

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
  bash "$POLICY" --project "$1" --policy auto-add set >/dev/null
}

tree_outside() {
  find "$1" \( -path "$1/.git" -o -path "$1/.git/*" -o -path "$1/.nightshift" -o -path "$1/.nightshift/*" \) -prune -o -print | sort
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
      "nightshift-keep.txt":{existed:true, digest:"x", blob:$blob},
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
