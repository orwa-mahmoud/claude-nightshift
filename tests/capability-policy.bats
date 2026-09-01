#!/usr/bin/env bats
# Owner tooling-policy helper, skill contract, and Doctor report.

ROOT="$BATS_TEST_DIRNAME/.."
POLICY="$ROOT/plugins/nightshift/runtime/capability-policy.sh"
WIN="$ROOT/plugins/nightshift/runtime/windows/capability-policy.ps1"
DOCTOR="$ROOT/plugins/nightshift/runtime/doctor.sh"
HUNT="$ROOT/plugins/nightshift/skills/hunt/SKILL.md"
QUALITY="$ROOT/plugins/nightshift/skills/quality/SKILL.md"
SETUP="$ROOT/plugins/nightshift/skills/setup/SKILL.md"
MODES="$ROOT/plugins/nightshift/skills/nightshift/references/execution-modes.md"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/capability-policy"

load helpers

cap() {
  bash "$POLICY" "$@"
}

doctor() {
  bash "$DOCTOR" --project "$1"
}

# Skill prose wraps and bolds; flatten so a split phrase still matches.
has_prose() {
  tr '*`' '  ' <"$1" | tr '\n' ' ' | tr -s ' ' | grep -qiF "$2"
}

@test "get on a missing policy file defaults to existing-tools" {
  p="$(new_project cap-missing)"
  [ ! -e "$p/.nightshift/capability-policy.json" ]
  run cap --project "$p" get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .policy == "existing-tools"
    and .stored == "existing-tools"
    and .source == "default"
    and .refused == false
  ' >/dev/null
}

@test "set then get round-trips all three policies in repository mode" {
  p="$(new_project cap-round)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  for pol in existing-tools auto-add review-missing; do
    run cap --project "$p" --policy "$pol" set
    [ "$status" -eq 0 ]
    [ -f "$p/.nightshift/capability-policy.json" ]
    run cap --project "$p" --work-mode repository get
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -e --arg pol "$pol" '
      .policy == $pol
      and .stored == $pol
      and .source == "file"
      and .refused == false
    ' >/dev/null || { echo "round-trip failed: $pol -> $output"; return 1; }
  done
}

@test "artifact mode refuses stored auto-add and reports existing-tools" {
  p="$(new_project cap-artifact)"
  run cap --project "$p" --policy auto-add set
  [ "$status" -eq 0 ]
  run cap --project "$p" --work-mode artifact get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .policy == "existing-tools"
    and .stored == "auto-add"
    and .refused == true
    and .source == "file"
  ' >/dev/null
}

@test "malformed policy JSON does not crash get and falls back to existing-tools" {
  p="$(new_project cap-malformed)"
  cp "$FIXTURES/truncated.json" "$p/.nightshift/capability-policy.json"
  before="$(cksum "$p/.nightshift/capability-policy.json")"
  run cap --project "$p" get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .policy == "existing-tools"
    and .source == "malformed"
    and .refused == false
  ' >/dev/null
  [ "$(cksum "$p/.nightshift/capability-policy.json")" = "$before" ]

  cp "$FIXTURES/unknown-policy.json" "$p/.nightshift/capability-policy.json"
  run cap --project "$p" --work-mode repository get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .policy == "existing-tools"
    and .source == "malformed"
  ' >/dev/null
}

@test "set overrides a remembered policy and accepts remember false" {
  p="$(new_project cap-override)"
  cap --project "$p" --policy auto-add set >/dev/null
  run cap --project "$p" --policy existing-tools set
  [ "$status" -eq 0 ]
  run cap --project "$p" get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.policy == "existing-tools" and .stored == "existing-tools"' >/dev/null

  run cap --project "$p" --policy review-missing --remember false set
  [ "$status" -eq 0 ]
  run cap --project "$p" get
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '
    .policy == "review-missing"
    and .remember == false
  ' >/dev/null
  grep -qF '"remember": false' "$p/.nightshift/capability-policy.json"
  grep -qF 'current invocation may override' "$MODES"
}

@test "Hunt Quality Setup and execution-modes name the third tooling policy before scanning" {
  has_prose "$QUALITY" 'before scanning' || has_prose "$QUALITY" 'before any scan'
  has_prose "$MODES" 'before scanning'
  has_prose "$HUNT" 'before scanning' || has_prose "$HUNT" 'work-target scan'
  has_prose "$MODES" 'third independent choice'
  has_prose "$QUALITY" 'three independent choices'

  for f in "$HUNT" "$QUALITY" "$SETUP" "$MODES"; do
    has_prose "$f" 'Existing tools only' || { echo "missing Existing tools only: $f"; return 1; }
    has_prose "$f" 'Review missing tools first' || { echo "missing Review missing: $f"; return 1; }
    has_prose "$f" 'Automatically add standard development tools' || { echo "missing auto-add: $f"; return 1; }
    has_prose "$f" 'repository-tool' || has_prose "$f" 'refuses auto-add' \
      || { echo "missing artifact refuse: $f"; return 1; }
  done

  has_prose "$HUNT" 'work clock has not begun'
  has_prose "$MODES" 'work clock has not begun'
  has_prose "$HUNT" 'writes nothing' || has_prose "$HUNT" 'Write nothing'
  has_prose "$QUALITY" 'writes nothing' || has_prose "$QUALITY" 'Write nothing'
  has_prose "$MODES" 'write nothing'
  has_prose "$HUNT" 'Do not pause again' || has_prose "$HUNT" 'do not pause again'
  has_prose "$QUALITY" 'must not pause again'
  has_prose "$MODES" 'Do not pause again'
}

@test "Doctor reports the default capability policy on a fresh project" {
  p="$(new_project cap-doc-default)"
  [ ! -e "$p/.nightshift/capability-policy.json" ]
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'capability policy existing-tools (default)'
  ! printf '%s\n' "$output" | grep -qF 'artifact mode refuses repository-tool policy'
  grep -qF 'capability policy existing-tools (default)' "$DOCTOR"
}

@test "Doctor reports auto-add after it is set" {
  p="$(new_project cap-doc-add)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  cap --project "$p" --policy auto-add set >/dev/null
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'capability policy auto-add'
  ! printf '%s\n' "$output" | grep -qF 'capability policy existing-tools (default)'
}

@test "Doctor warns when artifact mode refuses a repository-tool policy" {
  p="$(new_project cap-doc-refuse)"
  printf 'artifact\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$(cd -P "$p" && pwd)" >"$p/.nightshift/work-target"
  cap --project "$p" --policy auto-add set >/dev/null
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'artifact mode refuses repository-tool policy; using existing-tools'
  grep -qF 'artifact mode refuses repository-tool policy; using existing-tools' "$DOCTOR"
}

@test "review-first Hunt and Quality write nothing until approval" {
  has_prose "$HUNT" 'Write nothing before approval'
  has_prose "$HUNT" 'clock starts only after approval'
  has_prose "$QUALITY" 'the clock starts only after approval'
  has_prose "$MODES" 'Write and arm nothing until the owner approves'
  has_prose "$MODES" 'The clock starts only after'
}

@test "unsupported permission is mentioned before arming" {
  has_prose "$MODES" 'Unsupported permission modes must be reported before arming'
  has_prose "$HUNT" 'unsupported permission' || has_prose "$HUNT" 'report missing'
  has_prose "$HUNT" 'before arming'
  has_prose "$SETUP" 'permission prompt'
}

@test "inventory write stays inside .nightshift/" {
  w="$(new_workspace cap-inv)"
  printf 'sentinel\n' >"$w/repo/keep-me.txt"
  outside_before="$(find "$w" \( -path "$w/.nightshift" -o -path "$w/.nightshift/*" \) -prune -o -print | sort)"
  run cap --project "$w" --record '{"items":[{"capability":"lint"}]}' inventory set
  [ "$status" -eq 0 ]
  [ -f "$w/.nightshift/capabilities.json" ]
  [ ! -e "$w/.nightshift/capabilities.json.tmp" ]
  [ ! -e "$w/capabilities.json" ]
  [ ! -e "$w/repo/capabilities.json" ]
  [ ! -e "$w/repo/keep-me.txt.tmp" ]
  jq -e '.schemaVersion == 1 and .tickProof == false and (.updatedAt | type == "string")' \
    "$w/.nightshift/capabilities.json" >/dev/null
  outside_after="$(find "$w" \( -path "$w/.nightshift" -o -path "$w/.nightshift/*" \) -prune -o -print | sort)"
  [ "$outside_before" = "$outside_after" ]
}

@test "Windows capability-policy helper exists and names get and set" {
  [ -f "$WIN" ]
  grep -q 'ValidateSet' "$WIN"
  grep -qF "'get'" "$WIN"
  grep -qF "'set'" "$WIN"
}
