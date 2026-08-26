load helpers

LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
STATE="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/state.sh"
PSM1="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/Nightshift.psm1"
DOCTOR_SH="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
DOCTOR_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/doctor.ps1"
SCHED_SH="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/schedule.sh"
SCHED_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/schedule.ps1"

@test "ns_open_boxes_file counts every open box and treats a missing file as zero" {
  f="$BATS_TEST_TMPDIR/orders.md"
  printf '# Work Orders\n\n- [ ] **one.**\n- [x] **done.**\n- [ ] **two.**\n' >"$f"
  [ "$(bash -c '. "$1"; ns_open_boxes_file "$2"' _ "$LIB" "$f")" = 2 ]
  [ "$(bash -c '. "$1"; ns_open_boxes_file "$2"' _ "$LIB" "$BATS_TEST_TMPDIR/missing.md")" = 0 ]
}

@test "ns_open_drafts ignores the item-shape example above the first rule" {
  f="$BATS_TEST_TMPDIR/drafts.md"
  cat >"$f" <<'EOF'
```text
- [ ] **1. example only.**
```

---

- [ ] **Real draft.**
- [x] **Already promoted.**
EOF
  [ "$(bash -c '. "$1"; ns_open_drafts "$2"' _ "$LIB" "$f")" = 1 ]
  [ "$(bash -c '. "$1"; ns_open_drafts "$2"' _ "$LIB" "$BATS_TEST_TMPDIR/missing-drafts.md")" = 0 ]
}

@test "Doctor and Schedule count drafts and orders through the shared helpers" {
  grep -qF 'ns_open_boxes_file' "$STATE"
  grep -qF 'ns_open_drafts' "$STATE"
  grep -qF 'Get-NSOpenBoxesInFile' "$PSM1"
  grep -qF 'Get-NSOpenDrafts' "$PSM1"
  for f in "$DOCTOR_SH" "$SCHED_SH"; do
    grep -qF 'ns_open_boxes_file' "$f"
    grep -qF 'ns_open_drafts' "$f"
    ! grep -qF 'seen && /^[[:space:]]*-' "$f"
  done
  for f in "$DOCTOR_PS1" "$SCHED_PS1"; do
    grep -qF 'Get-NSOpenBoxesInFile' "$f"
    grep -qF 'Get-NSOpenDrafts' "$f"
    ! grep -qF '$seenRule' "$f"
  done
}
