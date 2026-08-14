LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
STATUS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/status/SKILL.md"
DOCTOR="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
DOCTOR_SKILL="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/doctor/SKILL.md"

CODES="completed owner-stop stale-pid invalid-session exhausted-retry unknown-wedge revived stand-down wrong-host deadline clean-session-end esc-standby silent-standby non-resumable-session unreadable-rules fresh-fallback unsupported-state process-evidence-unavailable"

@test "every shipped reason code has a stable label" {
  for c in $CODES; do
    label="$(bash -c '. "$1"; ns_reason_label "$2"' _ "$LIB" "$c")"
    [ -n "$label" ] || { echo "empty label: $c"; return 1; }
    [ "$label" != "unknown watchman outcome" ] || { echo "unlisted code: $c"; return 1; }
  done
}

@test "status and Doctor render the same shared reason file" {
  grep -qF '.watch-reason' "$STATUS"
  grep -qF 'ns_reason_label' "$STATUS"
  grep -qF 'ns_reason_code' "$DOCTOR"
  grep -qF 'ns_reason_label' "$DOCTOR"
  grep -qF '.watch-reason' "$DOCTOR_SKILL" || grep -qF 'watchman reason' "$DOCTOR"
}

@test "recording a reason strips controls and rejects unknown codes" {
  ns="$BATS_TEST_TMPDIR/ns"
  mkdir -p "$ns"
  bash -c '. "$1"; ns_record_reason "$2" revived "$(printf "ok\tdetail\nextra")"' _ "$LIB" "$ns"
  [ "$(sed -n 1p "$ns/.watch-reason")" = "revived" ]
  ! grep -q $'\t' "$ns/.watch-reason"
  bash -c '. "$1"; ns_record_reason "$2" not-a-real-code' _ "$LIB" "$ns"
  [ "$(sed -n 1p "$ns/.watch-reason")" = "stand-down" ]
}
