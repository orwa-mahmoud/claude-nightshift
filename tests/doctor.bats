load helpers

DOCTOR="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
SKILL="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/doctor/SKILL.md"
STATUS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/status/SKILL.md"
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
  grep -qF '$NS/deadline' "$SKILL"
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

@test "doctor warns when watchman recovery keys are empty" {
  p="$(new_project)"
  python3 -c '
import json,sys
p=sys.argv[1]
with open(p) as f: d=json.load(f)
d["watchRetrySeconds"]=""
d["revivalPrompt"]=""
d["freshRevivalPrompt"]=""
with open(p,"w") as f: json.dump(d,f)
' "$p/.nightshift/rules.json"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'watchRetrySeconds is empty'
  printf '%s' "$output" | grep -q 'revivalPrompt is empty'
  printf '%s' "$output" | grep -q 'freshRevivalPrompt is empty'
  printf '%s' "$output" | grep -q 'watchman will refuse to arm'
  printf '%s' "$output" | grep -q 'restore revivalPrompt from the shipped template'
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

@test "Doctor reports a missing deadline as none" {
  p="$(new_project)"
  punch_open "$p"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'deadline=none'
}

@test "Doctor reports remaining seconds for a UNIX epoch deadline" {
  p="$(new_project)"
  punch_open "$p"
  future="$(( $(date +%s) + 3600 ))"
  printf '%s' "$future" >"$p/.nightshift/deadline"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "deadline=$future remaining="
  ! printf '%s' "$output" | grep -q 'deadline is not a UNIX epoch'
}

@test "Doctor reports elapsed when the UNIX epoch deadline is past" {
  p="$(new_project)"
  punch_open "$p"
  past="$(( $(date +%s) - 60 ))"
  printf '%s' "$past" >"$p/.nightshift/deadline"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF "deadline=$past remaining=0s (elapsed)"
}

@test "Doctor warns when the deadline is not a UNIX epoch" {
  p="$(new_project)"
  punch_open "$p"
  printf '2026-08-27T08:45:56+04:00\n' >"$p/.nightshift/deadline"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'deadline is not a UNIX epoch'
  ! printf '%s' "$output" | grep -q 'deadline=none'
}

@test "Doctor warns when the deadline path is a symlink" {
  p="$(new_project)"
  punch_open "$p"
  echo $(($(date +%s) - 60)) >"$p/.nightshift/deadline-plant"
  ln -s deadline-plant "$p/.nightshift/deadline"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'deadline path is not a usable file'
  ! printf '%s' "$output" | grep -q 'deadline=none'
  ! printf '%s' "$output" | grep -q 'remaining=0s'
  grep -qF 'deadline path is not a usable file' "$SKILL"
  grep -qF 'deadline path is not a usable file' "$STATUS"
}

@test "Doctor warns when the ended path is a symlink" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/ended-plant"
  ln -s ended-plant "$p/.nightshift/.ended"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'ended path is not a usable file'
  ! printf '%s' "$output" | grep -qF 'gate has clocked the shift out'
  grep -qF 'ended path is not a usable file' "$SKILL"
  grep -qF 'ended path is not a usable file' "$STATUS"
}

@test "Doctor warns when the stall path is a symlink" {
  p="$(new_project)"
  punch_open "$p"
  printf 'fp\n99\n' >"$p/.nightshift/stall-plant"
  ln -s stall-plant "$p/.nightshift/.stall"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'stall path is not a usable file'
  ! printf '%s' "$output" | grep -qF 'stall count'
  grep -qF 'stall path is not a usable file' "$SKILL"
  grep -qF 'stall path is not a usable file' "$STATUS"
}

@test "Doctor warns when the session-end path is a symlink" {
  p="$(new_project)"
  punch_open "$p"
  : >"$p/.nightshift/session-end-plant"
  ln -s session-end-plant "$p/.nightshift/.session-end"
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'session-end path is not a usable file'
  ! printf '%s' "$output" | grep -qF 'clean session-end marker is present'
  grep -qF 'session-end path is not a usable file' "$SKILL"
  grep -qF 'session-end path is not a usable file' "$STATUS"
}

@test "the drafting-table item-shape example is not a staged draft" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  cp "$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/drafting-table-template.md" \
    "$p/.nightshift/drafting-table.md"
  printf '## Items\n\n' >"$p/.nightshift/punch-list.md"
  run doctor "$p"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'staged drafting-table items='
}

@test "drafting-table items after the rule are counted" {
  p="$(new_project)"
  rm -f "$p/.nightshift/.shift-armed"
  printf '## Items\n\n' >"$p/.nightshift/punch-list.md"
  cat >"$p/.nightshift/drafting-table.md" <<'EOF'
# Drafting Table

```text
- [ ] **1. example only.**
```

---

- [ ] **Real draft.**
  - Verify: true
  - Commit: `fix: x`
EOF
  run doctor "$p"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'staged drafting-table items=1'
  printf '%s' "$output" | grep -q '\[confirm\].*drafting-table items'
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
  grep -qF '/nightshift:doctor' "$BATS_TEST_DIRNAME/../docs/how-it-works.md"
  grep -qF 'never repairs' "$BATS_TEST_DIRNAME/../docs/how-it-works.md"
  grep -qF 'runtime/export-support.sh' "$BATS_TEST_DIRNAME/../docs/commands.md"
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

LOGIC="$BATS_TEST_DIRNAME/windows/codex-identity-logic.ps1"
RUN="$BATS_TEST_DIRNAME/windows/run.ps1"

@test "Windows CI runs the portable Codex identity shape suite" {
  [ -f "$LOGIC" ]
  grep -qF 'codex-identity-logic.ps1' "$RUN"
  grep -qF 'Get-NSCodexIdentityKind' "$LOGIC"
  grep -qF 'thread_abc' "$LOGIC"
  grep -qF 'function Get-NSCodexIdentityKind' \
    "$BATS_TEST_DIRNAME/../plugins/nightshift/lib/Nightshift.psm1"
}

@test "Windows Codex identity kinds match POSIX when pwsh is present" {
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ]
}
