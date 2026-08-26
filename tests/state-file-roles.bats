ROOT="$BATS_TEST_DIRNAME/../plugins/nightshift/skills"
REF="$ROOT/nightshift/references"

@test "active workflow skills carry the same state map" {
  for skill in nightshift setup start status archive import-issues hunt quality; do
    file="$ROOT/$skill/SKILL.md"
    grep -qF 'punch-list.md` → owner-approved work active in this shift' "$file"
    grep -qF 'drafting-table.md` → known work staged for a later shift' "$file"
    grep -qF 'parking-lot.md` → unresolved owner' "$file"
    grep -qF 'work-orders.md` → timed catalog work composed' "$file"
    grep -qF 'only through Hunt' "$file"
  done
}

@test "state templates say what belongs and what does not" {
  grep -qF 'Owner-approved active work belongs here' "$REF/punch-list-template.md"
  grep -qF 'known later work' "$REF/drafting-table-template.md"
  grep -qF 'Known tasks and follow-ups do not belong here' "$REF/parking-lot-template.md"
  grep -qF 'composed only through Nightshift: Hunt' "$REF/work-orders-template.md"
}

@test "setup scaffolds the explicit work-order template" {
  grep -qF 'work-orders-template.md' "$ROOT/setup/SKILL.md"
  ! grep -qF 'work-orders.md` with a one-line header' "$ROOT/setup/SKILL.md"
}

@test "ordinary workflow guidance does not call later work parked" {
  ! grep -RqiE 'park(ed|ing)? (known |ordinary )?(work|task|plan)|park(ed|ing)? for later' \
    "$ROOT/nightshift/SKILL.md" "$ROOT/setup/SKILL.md" "$ROOT/start/SKILL.md" \
    "$ROOT/status/SKILL.md" "$ROOT/archive/SKILL.md" "$REF/punch-list-template.md" \
    "$REF/drafting-table-template.md" "$REF/parking-lot-template.md" "$REF/work-orders-template.md"
}

@test "routing is described as model guidance, not hook enforcement" {
  grep -qF 'State map:' "$ROOT/nightshift/SKILL.md"
  ! grep -RqiE 'hooks? (enforces?|forces?) (the )?(state|routing|classification)' \
    "$ROOT" "$REF"
}
