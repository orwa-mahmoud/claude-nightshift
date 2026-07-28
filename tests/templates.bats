load helpers

REF="$BATS_TEST_DIRNAME/../skills/nightshift/references"
OPEN_BOX='^[[:space:]]*-[[:space:]]*\[[[:space:]]\]'

# /nightshift:setup copies punch-list-template.md verbatim into .nightshift/punch-list.md, and
# the clock-out gate blocks on any open "- [ ]" it finds there. A single illustrative checkbox
# in the template — even inside a comment, which the gate does not understand — would trap every
# freshly scaffolded project in a shift it never started.
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
@test "the drafting table and walkthrough templates do show the item shape" {
  [ "$(grep -cE "$OPEN_BOX" "$REF/drafting-table-template.md" || true)" -gt 0 ]
  [ "$(grep -cE "$OPEN_BOX" "$REF/walkthrough-item.md" || true)" -gt 0 ]
}

@test "every template setup copies is present" {
  for t in punch-list drafting-table parking-lot snag-log; do
    [ -f "$REF/$t-template.md" ] || { echo "missing $t-template.md"; return 1; }
    grep -qF "$t-template.md" "$BATS_TEST_DIRNAME/../skills/setup/SKILL.md" \
      || { echo "setup does not scaffold $t-template.md"; return 1; }
  done
}
