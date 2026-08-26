load helpers

REF="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references"
OPEN_BOX='^[[:space:]]*-[[:space:]]*\[[[:space:]]\]'

# Setup copies punch-list-template.md into .nightshift/punch-list.md after substituting
# $NIGHTSHIFT_WORKSPACE with the resolved workspace path. The clock-out gate blocks on any
# open "- [ ]" it finds there. A single illustrative checkbox in the template — even inside
# a comment, which the gate does not understand — would trap every freshly scaffolded
# project in a shift it never started.
@test "the punch-list template ships with no open checkbox" {
  n="$(grep -cE "$OPEN_BOX" "$REF/punch-list-template.md" || true)"
  [ "${n:-0}" -eq 0 ]
}

@test "a scaffolded punch list leaves the gate inert until the owner adds an item" {
  p="$(new_project)"
  cp "$REF/punch-list-template.md" "$p/.nightshift/punch-list.md"
  run gate "$p"
  is_release
  run hardhat_ask "$p"
  is_allow
}

@test "the punch-list template carries the headings the gate and setup depend on" {
  grep -q '^## Items' "$REF/punch-list-template.md"
  grep -q '^## Gates' "$REF/punch-list-template.md"
}

# The drafting table is where work waits, so it must show the item shape. It is never read by
# the gate — only the punch list is — which is exactly why proposals land there first.
@test "the drafting table and catalog entries do show the item shape" {
  [ "$(grep -cE "$OPEN_BOX" "$REF/drafting-table-template.md" || true)" -gt 0 ]
  for f in "$REF"/shifts/*.md; do
    [ "$(grep -cE "$OPEN_BOX" "$f" || true)" -gt 0 ] || { echo "no item shape: $f"; return 1; }
  done
}

@test "every template setup copies is present" {
  for t in punch-list drafting-table parking-lot snag-log product-research opportunity-map work-orders; do
    [ -f "$REF/$t-template.md" ] || { echo "missing $t-template.md"; return 1; }
    grep -qF "$t-template.md" "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md" \
      || { echo "setup does not scaffold $t-template.md"; return 1; }
  done
}

@test "the opportunity map carries a resumable single-building record" {
  t="$REF/opportunity-map-template.md"
  grep -qF 'Only one opportunity may be `building` at a time' "$t"
  grep -qF 'Current phase:' "$t"
  grep -qF 'Completed:' "$t"
  grep -qF 'Rejected:' "$t"
  grep -qF 'Next:' "$t"
  grep -qF 'Verify remaining:' "$t"
}

# The rules template is the owner's whole config surface — every synced key ships in it.
@test "the rules template is valid JSON and carries every synced key" {
  t="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json"
  jq -e 'type == "object"' "$t" >/dev/null
  for k in toolDeny forbiddenCommands neverCommitPatterns expectedEmail protectedDirs \
    stallMax stallWarnEvery watchMinutes watchRetrySeconds notifyCommand revivalPrompt freshRevivalPrompt clockOutMessage; do
    jq -e --arg k "$k" 'has($k)' "$t" >/dev/null || { echo "template missing $k"; return 1; }
  done
  # the shipped texts are the ONLY copy — they must ship filled, not as empty placeholders
  for k in revivalPrompt freshRevivalPrompt clockOutMessage watchRetrySeconds; do
    jq -e --arg k "$k" '.[$k] | length > 0' "$t" >/dev/null || { echo "template ships empty $k"; return 1; }
  done
  jq -e '.toolDeny.AskUserQuestion | length > 0' "$t" >/dev/null
  jq -e '.toolDeny.request_user_input | length > 0' "$t" >/dev/null
}

# Updates offer their improvements; they never overwrite the owner's words.
@test "setup's template evolution offers, never imposes" {
  s="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"
  grep -qF 'offer, never impose' "$s"
  grep -qF 'nested `toolDeny` keys' "$s"
  grep -qF '`request_user_input`; add it?' "$s"
  grep -qF 'touch a value the owner already has' "$s"
  grep -qF "wording wins every conflict" "$s"
  grep -qF 'open boxes is never touched' "$s"
  grep -qF 'leftover campaign text' "$s"
  grep -qF 'restore the template contract' "$s"
  grep -qF 'Never rewrite without an explicit yes' "$s"
  grep -qF 'PSObject.Properties.Name' "$s"
  grep -qF 'ConvertFrom-Json' "$s"
}

# The contracts the setup conversation must not drift on: the receipts repo is never
# "recommended", the rules live and die with nightshift's folder, and a pre-0.6.1 file is
# moved, not retyped.
@test "setup pins the neutral ask and the rules home" {
  s="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/setup/SKILL.md"
  grep -qF 'never describe the repo as recommended; the default is no' "$s"
  grep -qF '`$NS/rules.json` as-is' "$s"
  grep -qF 'removes all of nightshift, rules' "$s"
}

# Three answers, and exactly one of them arms the gate. A survey that writes to the punch list
# without starting would leave the owner's next session held by a shift nobody began.
@test "quality offers fix now, draft for later, or ignore" {
  q="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/quality/SKILL.md"
  grep -qi 'fix now' "$q"
  grep -qi 'draft for later' "$q"
  grep -qi 'ignore' "$q"
  grep -qi 'never write to the punch list on anything but an explicit' "$q"
  grep -qi 'or neither happens' "$q"
}

@test "quality cut goes through work-orders.md the same way Hunt does" {
  q="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/quality/SKILL.md"
  grep -qF '$NS/work-orders.md' "$q"
  grep -qi 'never write the punch list first' "$q"
  grep -qi 'never clobber orders already' "$q"
}

@test "command reference says Quality fix now goes through a Hunt work order" {
  grep -qF 'appends a Hunt work order' "$BATS_TEST_DIRNAME/../docs/commands.md"
}

@test "quality covers the full catalog and shares hunt execution modes" {
  q="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/quality/SKILL.md"
  grep -qF 'execution-modes.md' "$q"
  grep -qi 'Guided' "$q"
  grep -qi 'Automatic' "$q"
  grep -qi 'Review first' "$q"
  grep -qi 'Run directly' "$q"
  for area in 'flaky tests' coverage 'dead code' 'TODO/FIXME' accessibility localization \
    'API contract drift' 'documentation drift' 'CI warnings' dependencies 'vulnerability advisories'; do
    grep -qi "$area" "$q" || { echo "quality omits $area"; return 1; }
  done
}

@test "quality launch paths require the start preflight before arming" {
  local q fix_now run_direct section
  q="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/quality/SKILL.md"
  fix_now="$(awk '/^- \*\*fix now\*\*/ { capture=1 } /^- \*\*draft for later\*\*/ { exit } capture' "$q")"
  run_direct="$(awk '/^## 5\. Run directly/ { capture=1 } capture' "$q")"

  for section in "$fix_now" "$run_direct"; do
    printf '%s\n' "$section" | grep -qi 'preflight'
    printf '%s\n' "$section" | grep -qi 'arming'
  done

  printf '%s\n' "$run_direct" | grep -qi 'one-shift check'
  printf '%s\n' "$run_direct" | grep -qi 'stale run-control markers'
  printf '%s\n' "$run_direct" | grep -qi 'unattended permissions'
  printf '%s\n' "$run_direct" | grep -qF '$NS/.shift-armed'
}

# The install copies plugins/nightshift/ alone, and MIT asks for the notice to travel with every copy — so the
# licence exists twice on purpose. Two copies drift; this fails the moment they do.
@test "the shipped licence is the repository's licence" {
  cmp "$BATS_TEST_DIRNAME/../LICENSE" "$BATS_TEST_DIRNAME/../plugins/nightshift/LICENSE"
}
