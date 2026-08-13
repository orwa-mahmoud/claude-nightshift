SHIFTS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/shifts"
CAT="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/shift-catalog.md"
RECIPE="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/catalog-recipe.md"

# Structural rules only. Every assertion here globs the directory, so a contributed shift is
# covered the moment its file lands — nobody edits this file to add an entry, which is the whole
# reason entries are one per file.

@test "the catalog directory has entries" {
  [ -d "$SHIFTS" ]
  n="$(find "$SHIFTS" -name '*.md' | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ]
}

# The ending decides whether hunt asks for hours at all, so every entry states it in its title
# line where both a reader and the skill see it without parsing the body.
@test "every entry declares its ending in its title" {
  for f in "$SHIFTS"/*.md; do
    head -n1 "$f" | grep -qE '^# .+ — (finite|open-ended) — ' \
      || { echo "entry does not declare its ending: $f"; return 1; }
  done
}

@test "every entry ships a pasteable punch-list item" {
  for f in "$SHIFTS"/*.md; do
    grep -q '^```text$' "$f" || { echo "no fenced item block: $f"; return 1; }
    grep -qE '^- \[ \] \*\*.+\*\*$' "$f" || { echo "no punch-list item: $f"; return 1; }
  done
}

# An item with no Verify line cannot prove its work, and the gate has nothing to be green about.
@test "every entry ends with a Verify line" {
  for f in "$SHIFTS"/*.md; do
    grep -qE '^[[:space:]]*- Verify: ' "$f" || { echo "no Verify line: $f"; return 1; }
  done
}

# The definition of done is the lever the whole product rests on. An entry that never says what
# ends it is a shift that ends whenever the model feels finished.
@test "every entry states what ends it" {
  for f in "$SHIFTS"/*.md; do
    grep -qiE 'ends when|stop (only )?at|quitting time|converge' "$f" \
      || { echo "entry does not state its ending condition: $f"; return 1; }
  done
}

# One file per entry is what keeps two contributors out of the same diff. An index that listed
# them would put everyone back in it.
@test "the catalog index points at the directory and lists no entries" {
  grep -qF 'shifts/' "$CAT"
  grep -qi 'this page never lists' "$CAT"
  ! grep -qE '^## .+ — (finite|open-ended) — ' "$CAT"
}

# A contributed shift is a contract handed to an unattended agent on a stranger's repo. The six
# declarations are what makes such a PR reviewable at all.
@test "the catalog recipe demands every declaration a reviewer needs" {
  [ -f "$RECIPE" ]
  for d in 'finite or open-ended' 'Discovery' 'Definition of done' 'never do' 'Verification' 'Supported stacks'; do
    grep -qi "$d" "$RECIPE" || { echo "recipe does not demand: $d"; return 1; }
  done
  grep -qi 'read by a human before merge' "$RECIPE"
}

@test "the recipe tells a contributor to add a file, not edit a shared one" {
  grep -qF 'shifts/' "$RECIPE"
  grep -qi 'tests/shifts/' "$RECIPE"
}

@test "the recipe points at the proposal form without replacing the two-file contract" {
  grep -qF 'issues/new?template=catalog_shift.yml' "$RECIPE"
  grep -qF 'orwa-mahmoud/nightshift/issues/21' "$RECIPE"
  grep -qi 'does not replace' "$RECIPE"
}
