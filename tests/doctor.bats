load helpers

DOCTOR="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
SKILL="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/doctor/SKILL.md"
LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
CODEX_PLUGIN="$BATS_TEST_DIRNAME/../plugins/nightshift/.codex-plugin/plugin.json"

fingerprint() {
  (cd "$1" && find . \( -type f -o -type l \) -exec cksum {} \; | sort)
}

doctor() {
  bash "$DOCTOR" --project "$1"
}

@test "Doctor is executable and both hosts discover the skill" {
  [ -x "$DOCTOR" ]
  [ -f "$SKILL" ]
  grep -q '^name: doctor$' "$SKILL"
  grep -qF 'runtime/doctor.sh' "$SKILL"
  grep -qF '[safe]' "$SKILL"
  grep -qF '[confirm]' "$SKILL"
  grep -qF '[blocked]' "$SKILL"
  grep -qF 'do not' "$SKILL"
  grep -qF 'write the parking lot or ask' "$SKILL"
  grep -qF 'Offer the classified repairs' "$SKILL"
  grep -qF 'Never perform a repair' "$SKILL" || grep -qF 'change nothing' "$SKILL"
  jq -e '.skills == "./skills/"' "$CODEX_PLUGIN" >/dev/null
  [ -d "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/doctor" ]
}

@test "Doctor tells unattended runs to report, never write, confirmation repairs" {
  grep -qF 'report that' "$SKILL"
  grep -qF 'write the parking lot or ask' "$SKILL"
  grep -qF 'the Doctor invocation remains byte-identical' "$SKILL"
}

@test "a healthy armed site reports facts and never repairs" {
  p="$(new_project)"
  punch_open "$p"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Nightshift Doctor'
  printf '%s' "$output" | grep -q 'shift is armed'
  printf '%s' "$output" | grep -q 'open=1'
  printf '%s' "$output" | grep -q 'ticked=1'
  printf '%s' "$output" | grep -q 'rules.json is a JSON object'
  printf '%s' "$output" | grep -q 'watchMinutes 10'
  printf '%s' "$output" | grep -q '\[blocked\] Doctor never repairs'
  printf '%s' "$output" | grep -q 'Actions (Doctor does not perform these)'
}

@test "Doctor reports lease ownership without printing its capability" {
  p="$(new_project)"
  punch_open "$p"
  printf 'shift-session\n\n\n\nclaude\n' >"$p/.nightshift/.shift-session"
  claim="$(bash -c '. "$1"; ns_lease_takeover "$2/.nightshift" shift-session claude' \
    nightshift "$LIB" "$p")"
  nonce="${claim#* }"

  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Lease:       valid (generation'
  printf '%s' "$output" | grep -q 'watchman recovery (capability not printed)'
  ! printf '%s' "$output" | grep -qF "$nonce"
}

@test "invoking Doctor alone changes no state" {
  p="$(new_project)"
  punch_open "$p"
  printf '99999\n' >"$p/.nightshift/.watchman"
  : >"$p/.nightshift/STOP"
  before="$(fingerprint "$p")"
  run doctor "$p"
  [ "$status" -eq 0 ]
  after="$(fingerprint "$p")"
  [ "$before" = "$after" ]
  [ -f "$p/.nightshift/.shift-armed" ]
  [ -f "$p/.nightshift/STOP" ]
  [ "$(cat "$p/.nightshift/.watchman")" = "99999" ]
  [ ! -e "$p/.nightshift/.watch-reason" ]
}

@test "missing setup is a confirmation offer, not a repair" {
  empty="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty"
  run doctor "$empty"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Nightshift:  missing'
  printf '%s' "$output" | grep -q '\[confirm\]'
  printf '%s' "$output" | grep -q 'run Nightshift setup'
  [ ! -d "$empty/.nightshift" ]
}

@test "an invalid link fails closed and offers confirmation" {
  host="$(new_project host)"
  printf 'relative/path\n' >"$host/.nightshift-link"
  before="$(fingerprint "$host")"
  run doctor "$host"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Link:        invalid'
  printf '%s' "$output" | grep -q 'invalid .nightshift-link'
  printf '%s' "$output" | grep -q '\[confirm\].*link-workspace.sh'
  printf '%s' "$output" | grep -q '/runtime/link-workspace.sh'
  ! printf '%s' "$output" | grep -q 'using runtime/link-workspace.sh'
  after="$(fingerprint "$host")"
  [ "$before" = "$after" ]
}

@test "a valid link diagnoses the workspace, not the task root" {
  host="$(new_project host)"
  rm -rf "$host/.nightshift"
  workspace="$(new_project workspace)"
  punch_open "$workspace"
  bash "$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/link-workspace.sh" \
    --host-root "$host" --workspace "$workspace" >/dev/null
  run doctor "$host"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Link:        valid'
  printf '%s' "$output" | grep -qF "Workspace:   $(cd -P "$workspace" && pwd)"
  printf '%s' "$output" | grep -q 'open=1'
  ! printf '%s' "$output" | grep -q 'no .nightshift/'
}

@test "broken rules are a warning, not a rewrite" {
  p="$(new_project)"
  printf '{not json\n' >"$p/.nightshift/rules.json"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'unreadable or not a JSON object'
  printf '%s' "$output" | grep -q '\[confirm\].*rules.json'
  grep -q '{not json' "$p/.nightshift/rules.json"
}

@test "missing native question rules are reported without an invented fallback" {
  p="$(new_project)"
  jq 'del(.toolDeny.request_user_input)' "$p/.nightshift/rules.json" >"$p/rules.tmp"
  mv "$p/rules.tmp" "$p/.nightshift/rules.json"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'toolDeny.request_user_input is missing'
  printf '%s' "$output" | grep -q '\[confirm\].*request_user_input'
  ! jq -e '.toolDeny | has("request_user_input")' "$p/.nightshift/rules.json" >/dev/null
}

@test "stale unarmed watchman pid is classified safe automatic" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  printf '99999\n' >"$p/.nightshift/.watchman"
  punch_open "$p"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'watchman pid 99999 is stale'
  printf '%s' "$output" | grep -q '\[safe\].*leftover .watchman'
  [ -f "$p/.nightshift/.watchman" ]
}

@test "empty punch list reports leftover contract without rewriting it" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  printf '## Shift contract\n- leftover campaign\n\n## Gates\n- none\n\n## Items\n\n' \
    >"$p/.nightshift/punch-list.md"
  before="$(fingerprint "$p")"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'leftover Shift contract and Gates'
  printf '%s' "$output" | grep -q 'empty punch list will inherit the current contract'
  printf '%s' "$output" | grep -q '\[confirm\].*review punch-list.md contract'
  after="$(fingerprint "$p")"
  [ "$before" = "$after" ]
  grep -q 'leftover campaign' "$p/.nightshift/punch-list.md"
}

@test "pending Hunt work orders are counted when the punch list is empty" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  printf '## Items\n\n' >"$p/.nightshift/punch-list.md"
  printf '# Work Orders\n\n## Work order — test\nHours: 2\n\n- [ ] **Coverage hunt.**\n' \
    >"$p/.nightshift/work-orders.md"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'pending Hunt work orders=1'
  printf '%s' "$output" | grep -q '\[confirm\].*promote a parked Hunt order'
}

@test "leftover STOP while unarmed requires owner confirmation" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  : >"$p/.nightshift/STOP"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'STOP leftover'
  printf '%s' "$output" | grep -q '\[confirm\].*stale STOP'
}

@test "a non-resumable Codex identity is blocked, never printed" {
  p="$(new_project)"
  punch_open "$p"
  printf 'thread_abc\n/tmp/rollout.jsonl\n\n\ncodex\n' >"$p/.nightshift/.shift-session"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'recorded host codex'
  printf '%s' "$output" | grep -q 'Codex identity kind unsupported'
  printf '%s' "$output" | grep -q '\[blocked\].*resumable Codex session id'
  ! printf '%s' "$output" | grep -q 'thread_abc'
}

@test "a resumable Codex identity is reported without printing the id" {
  p="$(new_project)"
  sid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  printf '%s\n\n\n\ncodex\n' "$sid" >"$p/.nightshift/.shift-session"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'Codex identity kind resumable'
  ! printf '%s' "$output" | grep -q "$sid"
}

@test "Doctor renders a recorded watchman reason without transcript content" {
  p="$(new_project)"
  printf 'owner-stop\nnever paste a prompt here\n' >"$p/.nightshift/.watch-reason"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'watchman reason owner-stop (owner stop-work order)'
  ! printf '%s' "$output" | grep -q 'never paste a prompt'
}

@test "paths with spaces are diagnosed read-only" {
  p="$BATS_TEST_TMPDIR/site with spaces"
  mkdir -p "$p/.nightshift"
  cp "$RULES_TEMPLATE" "$p/.nightshift/rules.json"
  : >"$p/.nightshift/.shift-armed"
  punch_open "$p"
  git -C "$p" init -q
  git -C "$p" config user.email dev@example.com
  git -C "$p" config user.name tester
  git -C "$p" commit -q --allow-empty -m init
  before="$(fingerprint "$p")"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'site with spaces'
  after="$(fingerprint "$p")"
  [ "$before" = "$after" ]
}

@test "docs expose Doctor as a read-only command" {
  grep -qF '/nightshift:doctor' "$BATS_TEST_DIRNAME/../docs/commands.md"
  grep -qF 'never repairs' "$BATS_TEST_DIRNAME/../docs/commands.md"
  grep -qF '/nightshift:doctor' "$BATS_TEST_DIRNAME/../docs/troubleshooting.md"
}

@test "identity helpers classify Codex session shapes" {
  run bash -c '. "$1"
    ns_codex_identity_kind ""
    echo
    ns_codex_identity_kind "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    echo
    ns_codex_identity_kind "deadbeefdeadbeefdeadbeefdeadbeef"
    echo
    ns_codex_identity_kind "thread_abc"
    echo
    ns_codex_identity_kind "id with space"
    echo
    ns_codex_identity_kind "/tmp/rollout.jsonl"
  ' _ "$LIB"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | awk 'NR==1{exit $0=="missing"?0:1}'
  printf '%s\n' "$output" | awk 'NR==2{exit $0=="resumable"?0:1}'
  printf '%s\n' "$output" | awk 'NR==3{exit $0=="resumable"?0:1}'
  printf '%s\n' "$output" | awk 'NR==4{exit $0=="unsupported"?0:1}'
  printf '%s\n' "$output" | awk 'NR==5{exit $0=="malformed"?0:1}'
  printf '%s\n' "$output" | awk 'NR==6{exit $0=="malformed"?0:1}'
}
