load helpers

APPLY="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/apply-profile.sh"
PROFILES="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/profiles"
SETUP="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"
PUNCHLIST_TEMPLATE="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/punch-list-template.md"

# Prints only the text of the punch list's `## Gates` block (between the heading and the next
# `## ` heading), the same slice apply-profile.sh rewrites.
gates_block() {
  awk '/^## Gates$/ { f = 1; next } /^## / { f = 0 } f' "$1"
}

@test "shipped v1 profiles are version 1 and use only schema keys" {
  schema="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/nightshift-rules.schema.json"
  for name in no-push strict-secrets isolated-branch; do
    f="$PROFILES/$name.json"
    [ -f "$f" ]
    jq -e --arg n "$name" '.name == $n and .version == 1 and .risk and .use and (.rules|type=="object")' "$f" >/dev/null
    jq -e --slurpfile s "$schema" '
      .rules | keys | all(. as $k | ($s[0].properties | has($k)) and $k != "$schema")
    ' "$f" >/dev/null
  done
}

@test "shipped v2 profiles are version 2 with the documented shiftDefaults and gates" {
  for name in fast balanced strict; do
    f="$PROFILES/$name.json"
    [ -f "$f" ]
    jq -e --arg n "$name" '.name == $n and .version == 2 and .risk and .use and (.rules|type=="object")' "$f" >/dev/null
  done
  jq -e '
    .shiftDefaults.verificationProfile == "fast"
    and .shiftDefaults.toolingPolicy == "existing-tools"
    and .shiftDefaults.execution == "run-direct"
    and .gates.itemGate == []
    and (.gates | has("siteInspection") | not)
  ' "$PROFILES/fast.json" >/dev/null
  jq -e '
    .shiftDefaults.verificationProfile == "balanced"
    and (.shiftDefaults | has("toolingPolicy") | not)
    and (.shiftDefaults | has("execution") | not)
    and .gates == null
    and .rules.stallMax == 0
    and .rules.stallWarnEvery == 3
    and .rules.watchMinutes == 10
    and .rules.watchRetrySeconds == "30 120"
  ' "$PROFILES/balanced.json" >/dev/null
  jq -e '
    .shiftDefaults.verificationProfile == "strict"
    and (.shiftDefaults | has("toolingPolicy") | not)
    and (.shiftDefaults | has("execution") | not)
    and .gates == null
  ' "$PROFILES/strict.json" >/dev/null
}

@test "list and preview are deterministic and write nothing" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  before="$(cksum "$p/.nightshift/rules.json")"
  run bash "$APPLY" --project "$p" --list
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no-push'
  printf '%s' "$output" | grep -q 'isolated-branch'
  printf '%s' "$output" | grep -q 'not a subscription'
  run bash "$APPLY" --project "$p" --profile no-push --mode fill
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Dry run'
  printf '%s' "$output" | grep -q 'forbiddenCommands'
  first="$output"
  run bash "$APPLY" --project "$p" --profile no-push --mode fill
  [ "$output" = "$first" ]
  [ "$(cksum "$p/.nightshift/rules.json")" = "$before" ]
}

@test "fill keeps owner values and replace shows a full next file" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  python3 -c '
import json,sys
p=sys.argv[1]
with open(p) as f: d=json.load(f)
d["forbiddenCommands"]="rm -rf"
with open(p,"w") as f: json.dump(d,f)
' "$p/.nightshift/rules.json"
  run bash "$APPLY" --project "$p" --profile no-push --mode fill --apply
  [ "$status" -eq 0 ]
  jq -e '.forbiddenCommands == "rm -rf"' "$p/.nightshift/rules.json" >/dev/null
  jq '.["$schema"] = 42' "$p/.nightshift/rules.json" >"$p/rules.tmp"
  mv "$p/rules.tmp" "$p/.nightshift/rules.json"
  run bash "$APPLY" --project "$p" --profile no-push --mode replace --apply
  [ "$status" -eq 0 ]
  jq -e '.forbiddenCommands == "git .*push"' "$p/.nightshift/rules.json" >/dev/null
  jq -e '
    (.["$schema"] | type) == "string"
    and (.["$schema"] | length) > 0
    and (.toolDeny.AskUserQuestion | type) == "string"
    and (.toolDeny.request_user_input | type) == "string"
    and (.toolDeny.AskQuestion | type) == "string"
    and (.watchMinutes | type) == "number"
    and (.clockOutMessage | length) > 0
  ' "$p/.nightshift/rules.json" >/dev/null
}

@test "fill refuses an old file with no explicit Codex question policy" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  jq 'del(.toolDeny.request_user_input)' "$p/.nightshift/rules.json" >"$p/rules.tmp"
  mv "$p/rules.tmp" "$p/.nightshift/rules.json"
  before="$(cksum "$p/.nightshift/rules.json")"
  run bash "$APPLY" --project "$p" --profile no-push --mode fill --apply
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'explicit native question policy'
  [ "$(cksum "$p/.nightshift/rules.json")" = "$before" ]
}

@test "unknown keys, malformed profiles, and armed writes are refused" {
  p="$(new_project)"
  run bash "$APPLY" --project "$p" --profile not-a-profile --mode fill
  [ "$status" -eq 1 ]
  run bash "$APPLY" --project "$p" --profile '../nightshift-rules-template' --mode fill
  [ "$status" -eq 1 ]
  : >"$p/.nightshift/.shift-armed"
  run bash "$APPLY" --project "$p" --profile no-push --mode fill --apply
  [ "$status" -eq 2 ]
  ! jq -e '.forbiddenCommands == "git .*push"' "$p/.nightshift/rules.json" >/dev/null
}

@test "v2 preview writes nothing and previews shift-defaults and the Gates block" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  run bash "$APPLY" --project "$p" --profile fast --mode fill
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Proposed shift-defaults.json'
  printf '%s' "$output" | grep -q '"verificationProfile": "fast"'
  printf '%s' "$output" | grep -q 'Proposed ## Gates block'
  [ ! -f "$p/.nightshift/shift-defaults.json" ]
  gates_block "$p/.nightshift/punch-list.md" | grep -qF '_None configured._'
}

@test "apply fast writes shift-defaults.json and an empty Gates placeholder" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  run bash "$APPLY" --project "$p" --profile fast --mode fill --apply
  [ "$status" -eq 0 ]
  jq -e '
    .schemaVersion == 1
    and .verificationProfile == "fast"
    and .hours == null
    and .toolingPolicy == "existing-tools"
    and .execution == "run-direct"
    and (.updatedAt | type) == "string"
  ' "$p/.nightshift/shift-defaults.json" >/dev/null
  gates_block "$p/.nightshift/punch-list.md" | grep -qF '_None configured._'
}

@test "apply strict after fast changes only verificationProfile and leaves the Gates block untouched" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  bash "$APPLY" --project "$p" --profile fast --mode fill --apply >/dev/null
  before_gates="$(cksum "$p/.nightshift/punch-list.md")"
  run bash "$APPLY" --project "$p" --profile strict --mode fill --apply
  [ "$status" -eq 0 ]
  jq -e '
    .verificationProfile == "strict"
    and .toolingPolicy == "existing-tools"
    and .execution == "run-direct"
  ' "$p/.nightshift/shift-defaults.json" >/dev/null
  [ "$(cksum "$p/.nightshift/punch-list.md")" = "$before_gates" ]
}

@test "apply of a v1 profile changes only rules.json; defaults and Gates stay untouched" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  bash "$APPLY" --project "$p" --profile fast --mode fill --apply >/dev/null
  before_defaults="$(cksum "$p/.nightshift/shift-defaults.json")"
  before_gates="$(cksum "$p/.nightshift/punch-list.md")"
  run bash "$APPLY" --project "$p" --profile no-push --mode replace --apply
  [ "$status" -eq 0 ]
  jq -e '.forbiddenCommands == "git .*push"' "$p/.nightshift/rules.json" >/dev/null
  [ "$(cksum "$p/.nightshift/shift-defaults.json")" = "$before_defaults" ]
  [ "$(cksum "$p/.nightshift/punch-list.md")" = "$before_gates" ]
}

@test "v2 apply refuses while armed and writes no shift-defaults.json" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  : >"$p/.nightshift/.shift-armed"
  run bash "$APPLY" --project "$p" --profile fast --mode fill --apply
  [ "$status" -eq 2 ]
  [ ! -f "$p/.nightshift/shift-defaults.json" ]
}

@test "a v2 profile with a non-null gates refuses to apply without a punch list" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  rm -f "$p/.nightshift/punch-list.md"
  run bash "$APPLY" --project "$p" --profile fast --mode fill --apply
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'punch-list.md'
}

@test "gates.itemGate renders commands, and the site-inspection sentence only when that key is present" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  plugincopy="$BATS_TEST_TMPDIR/plugincopy"
  mkdir -p "$plugincopy"
  cp -R "$BATS_TEST_DIRNAME/../plugins" "$plugincopy/plugins"
  cat >"$plugincopy/plugins/nightshift/skills/nightshift/references/profiles/probe.json" <<'JSON'
{
  "name": "probe",
  "version": 2,
  "risk": "low",
  "use": "test",
  "rules": {},
  "shiftDefaults": null,
  "gates": {
    "itemGate": ["eslint .", "tsc --noEmit"],
    "siteInspection": { "every": "5 items", "commands": ["knip"] }
  }
}
JSON
  run bash "$plugincopy/plugins/nightshift/runtime/apply-profile.sh" --project "$p" --profile probe --mode fill --apply
  [ "$status" -eq 0 ]
  gates="$(gates_block "$p/.nightshift/punch-list.md")"
  printf '%s' "$gates" | grep -qF '`eslint .`'
  printf '%s' "$gates" | grep -qF '`tsc --noEmit`'
  printf '%s' "$gates" | grep -qF '**Site inspection**'
  printf '%s' "$gates" | grep -qF 'every 5 items'
  printf '%s' "$gates" | grep -qF '`knip`'

  cat >"$plugincopy/plugins/nightshift/skills/nightshift/references/profiles/probe2.json" <<'JSON'
{
  "name": "probe2",
  "version": 2,
  "risk": "low",
  "use": "test",
  "rules": {},
  "shiftDefaults": null,
  "gates": { "itemGate": ["eslint ."] }
}
JSON
  run bash "$plugincopy/plugins/nightshift/runtime/apply-profile.sh" --project "$p" --profile probe2 --mode fill --apply
  [ "$status" -eq 0 ]
  gates2="$(gates_block "$p/.nightshift/punch-list.md")"
  printf '%s' "$gates2" | grep -qF '`eslint .`'
  ! printf '%s' "$gates2" | grep -qF '**Site inspection**'
}

@test "malformed v2 shiftDefaults or gates are refused before any write" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$PUNCHLIST_TEMPLATE" "$p/.nightshift/punch-list.md"
  plugincopy="$BATS_TEST_TMPDIR/plugincopy-bad"
  mkdir -p "$plugincopy"
  cp -R "$BATS_TEST_DIRNAME/../plugins" "$plugincopy/plugins"
  cat >"$plugincopy/plugins/nightshift/skills/nightshift/references/profiles/bad-sd.json" <<'JSON'
{
  "name": "bad-sd", "version": 2, "risk": "low", "use": "t", "rules": {},
  "shiftDefaults": { "verificationProfile": "nope" }, "gates": null
}
JSON
  run bash "$plugincopy/plugins/nightshift/runtime/apply-profile.sh" --project "$p" --profile bad-sd --mode fill
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'verificationProfile'
  [ ! -f "$p/.nightshift/shift-defaults.json" ]

  cat >"$plugincopy/plugins/nightshift/skills/nightshift/references/profiles/bad-gates.json" <<'JSON'
{
  "name": "bad-gates", "version": 2, "risk": "low", "use": "t", "rules": {},
  "shiftDefaults": null,
  "gates": { "itemGate": ["x"], "siteInspection": { "every": "abc", "commands": [] } }
}
JSON
  run bash "$plugincopy/plugins/nightshift/runtime/apply-profile.sh" --project "$p" --profile bad-gates --mode fill
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'siteInspection.every'
}

@test "profiles never fetch the network and setup documents confirmation" {
  ! grep -E 'curl|wget|http' "$APPLY" "$PROFILES"/*.json
  grep -qF 'apply-profile.sh' "$SETUP"
  grep -qF 'one-time local copy' "$SETUP"
  grep -qF 'Refuse `--apply` / `-Apply` while armed' "$SETUP"
  grep -qF 'every version-1 JSON file' "$SETUP"
  grep -qF 'every version-1 JSON file' "$BATS_TEST_DIRNAME/../docs/knobs.md"
}

@test "Windows apply-profile usage errors name native flags" {
  ps1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/apply-profile.ps1"
  grep -qF -- '-Mode must be replace or fill' "$ps1"
  ! grep -qF '--mode must be' "$ps1"
}

LOGIC="$BATS_TEST_DIRNAME/windows/apply-profile-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"

@test "Windows CI runs the portable apply-profile armed-refuse suite" {
  [ -f "$LOGIC" ]
  grep -qF 'apply-profile-logic.ps1' "$RUN"
  grep -qF 'refuse to write rules while the shift is armed' "$LOGIC"
}

@test "Windows apply-profile refuses Apply when armed if pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
