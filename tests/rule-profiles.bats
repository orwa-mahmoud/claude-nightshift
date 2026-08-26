load helpers

APPLY="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/apply-profile.sh"
PROFILES="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/profiles"
SETUP="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"

@test "shipped profiles are version 1 and use only schema keys" {
  schema="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/nightshift-rules.schema.json"
  for name in balanced no-push strict-secrets isolated-branch; do
    f="$PROFILES/$name.json"
    [ -f "$f" ]
    jq -e --arg n "$name" '.name == $n and .version == 1 and .risk and .use and (.rules|type=="object")' "$f" >/dev/null
    jq -e --slurpfile s "$schema" '
      .rules | keys | all(. as $k | ($s[0].properties | has($k)) and $k != "$schema")
    ' "$f" >/dev/null
  done
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

@test "profiles never fetch the network and setup documents confirmation" {
  ! grep -E 'curl|wget|http' "$APPLY" "$PROFILES"/*.json
  grep -qF 'apply-profile.sh' "$SETUP"
  grep -qF 'one-time local copy' "$SETUP"
  grep -qF 'every version-1 JSON file' "$SETUP"
  grep -qF 'every version-1 JSON file' "$BATS_TEST_DIRNAME/../docs/knobs.md"
}
