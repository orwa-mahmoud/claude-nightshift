load helpers

LIB="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/lib.sh"
WRITE="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/write-receipt.sh"
WRITE_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/write-receipt.ps1"
WRITE_LOGIC="$BATS_TEST_DIRNAME/windows/write-receipt-logic.ps1"
DOCTOR="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/doctor.sh"
DOCTOR_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/doctor.ps1"
PSM1="$BATS_TEST_DIRNAME/../plugins/nightshift/lib/Nightshift.psm1"
GATE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/clock-out-gate.sh"
CODEX_GATE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/codex/clock-out-gate.sh"
WIN_GATE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/windows/clock-out-gate.ps1"
CORE="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks/shared/gate-core.sh"
SKILLS="$BATS_TEST_DIRNAME/../plugins/nightshift/skills"
NIGHTSHIFT="$SKILLS/nightshift/SKILL.md"
START="$SKILLS/start/SKILL.md"
STATUS="$SKILLS/status/SKILL.md"
DOCTOR_SKILL="$SKILLS/doctor/SKILL.md"
ARCHIVE="$SKILLS/archive/SKILL.md"
TEMPLATE="$SKILLS/nightshift/references/punch-list-template.md"
DOC="$BATS_TEST_DIRNAME/../docs/how-it-works.md"
VOCAB="$BATS_TEST_DIRNAME/../docs/vocabulary.md"
COMMANDS="$BATS_TEST_DIRNAME/../docs/commands.md"
WINDOC="$BATS_TEST_DIRNAME/../docs/windows.md"
README="$BATS_TEST_DIRNAME/../README.md"

new_artifact() {
  local p="$BATS_TEST_TMPDIR/${1:-artifact}"
  mkdir -p "$p/.nightshift" "$p/out"
  cp "$RULES_TEMPLATE" "$p/.nightshift/rules.json"
  : >"$p/.nightshift/.shift-armed"
  printf 'artifact\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$(cd -P "$p" && pwd)" >"$p/.nightshift/work-target"
  printf '%s' "$p"
}

@test "write-receipt records a durable artifact receipt" {
  p="$(new_artifact ok)"
  printf 'research notes\n' >"$p/out/topic.md"
  run bash "$WRITE" --project "$p" --item 'Write the brief' --verify 'file exists' \
    --source 'https://example.com/doc' --output "$p/out/topic.md"
  [ "$status" -eq 0 ]
  dest="$output"
  [ -f "$dest" ]
  case "$dest" in */.nightshift/receipts/*.md) ;; *) echo "dest=$dest"; return 1 ;; esac
  grep -qF '# Nightshift artifact receipt' "$dest"
  grep -qF 'item: Write the brief' "$dest"
  grep -qF 'verification: file exists' "$dest"
  grep -qF 'mode: artifact' "$dest"
  grep -qF 'https://example.com/doc' "$dest"
  grep -qF 'sha256:' "$dest"
  grep -qF 'bytes:' "$dest"
  grep -qF 'mtime:' "$dest"
  run bash -c '. "$1"; ns_receipts_count "$2"' _ "$LIB" "$p"
  [ "$output" = 1 ]
}

@test "write-receipt refuses repository mode" {
  p="$(new_project receipt-repo)"
  printf 'ok\n' >"$p/out.md"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' --output "$p/out.md"
  [ "$status" -eq 3 ]
  [ ! -d "$p/.nightshift/receipts" ]
}

@test "write-receipt rejects a missing output" {
  p="$(new_artifact missing)"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' --output "$p/out/nope.md"
  [ "$status" -eq 2 ]
  [ ! -d "$p/.nightshift/receipts" ]
}

@test "write-receipt rejects an empty output" {
  p="$(new_artifact empty)"
  : >"$p/out/blank.md"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' --output "$p/out/blank.md"
  [ "$status" -eq 2 ]
  [ ! -d "$p/.nightshift/receipts" ]
}

@test "write-receipt rejects a symlink output" {
  p="$(new_artifact link)"
  printf 'ok\n' >"$p/out/real.md"
  ln -s "$p/out/real.md" "$p/out/alias.md"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' --output "$p/out/alias.md"
  [ "$status" -eq 2 ]
  [ ! -d "$p/.nightshift/receipts" ]
}

@test "write-receipt omits secret lines" {
  p="$(new_artifact secret)"
  printf 'ok\n' >"$p/out/topic.md"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' \
    --decision 'password=supersecret' --output "$p/out/topic.md"
  [ "$status" -eq 0 ]
  ! grep -qF 'supersecret' "$output"
  grep -qF 'decision: (redacted)' "$output"
}

@test "Doctor reports artifact receipts only in artifact mode" {
  a="$(new_artifact doctor)"
  printf 'ok\n' >"$a/out/topic.md"
  bash "$WRITE" --project "$a" --item 'x' --verify 'ok' --output "$a/out/topic.md" >/dev/null
  run bash "$DOCTOR" --project "$a"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'work mode artifact'
  printf '%s' "$output" | grep -qF 'artifact receipts 1'

  r="$(new_project receipt-doctor-repo)"
  run bash "$DOCTOR" --project "$r"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'work mode repository'
  ! printf '%s' "$output" | grep -qF 'artifact receipts'
}

@test "an artifact receipt resets the stall counter" {
  p="$(new_artifact stall)"
  punch_open "$p"
  run gate "$p"
  run gate "$p"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "2" ]
  printf 'ok\n' >"$p/out/topic.md"
  run bash "$WRITE" --project "$p" --item 'x' --verify 'ok' --output "$p/out/topic.md"
  [ "$status" -eq 0 ]
  run gate "$p"
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "1" ]
}

@test "repository mode still treats a commit as stall progress" {
  grep -qF 'a commit resets the stall counter' "$BATS_TEST_DIRNAME/clock-out-gate.bats"
  p="$(new_project receipt-commit-stall)"
  punch_open "$p"
  run gate "$p"
  run gate "$p"
  git -C "$p" commit -q --allow-empty -m progress
  run gate "$p"
  is_block "$output"
  [ "$(sed -n '2p' "$p/.nightshift/.stall")" = "1" ]
}

@test "archive copies receipts and leaves live copies" {
  grep -qF 'archive/<YYYY-MM-DD>/receipts/' "$ARCHIVE"
  grep -qF 'leave the live copies' "$ARCHIVE"
}

@test "skills and docs name artifact receipts" {
  grep -qF 'runtime/write-receipt.sh' "$NIGHTSHIFT"
  grep -qF 'runtime\windows\write-receipt.ps1' "$NIGHTSHIFT"
  grep -qF 'runtime/write-receipt.sh' "$START"
  grep -qF 'artifact receipts N' "$STATUS"
  grep -qF 'artifact receipts N' "$DOCTOR_SKILL"
  grep -qF 'artifact receipt' "$TEMPLATE"
  grep -qF 'runtime/write-receipt.sh' "$DOC"
  grep -qF '**artifact receipt**' "$VOCAB"
  grep -qF 'runtime/write-receipt.sh' "$COMMANDS"
  grep -qF 'runtime\windows\write-receipt.ps1' "$COMMANDS"
  grep -qF 'runtime\windows\write-receipt.ps1' "$WINDOC"
  grep -qF 'artifact receipts' "$README"
}

@test "Windows helpers pair the same receipt and stall token" {
  grep -qF 'function Get-NSReceiptsDir' "$PSM1"
  grep -qF 'function Get-NSReceiptsCount' "$PSM1"
  grep -qF 'function Get-NSReceiptsFingerprint' "$PSM1"
  grep -qF 'function Get-NSProgressToken' "$PSM1"
  grep -qF 'Get-NSReceiptsCount' "$DOCTOR_PS1"
  grep -qF 'artifact receipts' "$DOCTOR_PS1"
  grep -qF 'Get-NSProgressToken' "$WIN_GATE"
  grep -qF 'ns_gate_progress_token' "$CORE"
  grep -qF 'ns_gate_progress_token' "$GATE"
  grep -qF 'ns_gate_progress_token' "$CODEX_GATE"
  [ -f "$WRITE_PS1" ]
  grep -qF 'Get-NSWorkMode' "$WRITE_PS1"
  grep -qF 'exit 3' "$WRITE_PS1"
  grep -qF 'exit 2' "$WRITE_PS1"
}

@test "Windows write-receipt logic passes when pwsh is present" {
  [ -f "$WRITE_LOGIC" ]
  grep -qF 'write-receipt-logic.ps1' "$BATS_TEST_DIRNAME/windows/run.ps1"
  if ! command -v pwsh >/dev/null 2>&1; then
    return 0
  fi
  run pwsh -NoProfile -NonInteractive -File "$WRITE_LOGIC"
  [ "$status" -eq 0 ]
}
