load helpers

SCHEMA="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/nightshift-rules.schema.json"
TEMPLATE="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json"
VALIDATOR="$BATS_TEST_DIRNAME/helpers/validate-json-schema.py"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/rules-schema"
KNOBS="$BATS_TEST_DIRNAME/../docs/knobs.md"
SETUP="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"

validate() {
  python3 "$VALIDATOR" "$SCHEMA" "$1"
}

@test "the rules schema is valid JSON and describes the shipped keys" {
  jq -e 'type == "object"' "$SCHEMA" >/dev/null
  jq -e '.additionalProperties == false' "$SCHEMA" >/dev/null
  for k in toolDeny forbiddenCommands neverCommitPatterns expectedEmail protectedDirs \
    stallMax stallWarnEvery watchMinutes watchRetrySeconds watchAgent receiptsAutoCommit \
    notifyCommand revivalPrompt freshRevivalPrompt clockOutMessage retention; do
    jq -e --arg k "$k" '.properties | has($k)' "$SCHEMA" >/dev/null \
      || { echo "schema missing $k"; return 1; }
  done
  jq -e '.properties["$schema"]' "$SCHEMA" >/dev/null
  jq -e '.required | index("toolDeny")' "$SCHEMA" >/dev/null
  jq -e '.properties.toolDeny.required | index("AskUserQuestion")' "$SCHEMA" >/dev/null
  jq -e '.properties.toolDeny.required | index("request_user_input")' "$SCHEMA" >/dev/null
}

@test "the shipped rules template validates against the schema" {
  validate "$TEMPLATE"
}

@test "a copied rules file still validates after setup copies the template" {
  p="$(new_project)"
  validate "$p/.nightshift/rules.json"
}

@test "unknown properties, wrong types, and invalid values are rejected" {
  for f in unknown-property stallMax-string watchMinutes-negative \
    toolDeny-not-object toolDeny-value-number watchRetrySeconds-bad; do
    run validate "$FIXTURES/$f.json"
    [ "$status" -ne 0 ] || { echo "fixture should fail: $f"; return 1; }
  done
}

@test "a partial owner file with only valid keys still validates" {
  f="$BATS_TEST_TMPDIR/partial.json"
  printf '%s\n' '{"toolDeny":{"AskUserQuestion":"","request_user_input":""},"stallMax":4,"watchMinutes":0}' >"$f"
  validate "$f"
}

@test "both native question-tool keys are required explicitly" {
  f="$BATS_TEST_TMPDIR/missing-native-tool.json"
  printf '%s\n' '{"toolDeny":{"AskUserQuestion":"park"}}' >"$f"
  run validate "$f"
  [ "$status" -ne 0 ]
  printf '%s\n' '{"stallMax":4}' >"$f"
  run validate "$f"
  [ "$status" -ne 0 ]
}

@test "knobs and setup document editor discovery of the schema" {
  grep -qF 'nightshift-rules.schema.json' "$KNOBS"
  grep -qF 'json.schemas' "$KNOBS"
  grep -qF '.nightshift/rules.json' "$KNOBS"
  grep -qF 'nightshift-rules.schema.json' "$SETUP"
  grep -qF 'docs/knobs.md' "$SETUP"
}
