load helpers

ARCHIVE_SH="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/archive-receipts.sh"
ARCHIVE_PS1="$BATS_TEST_DIRNAME/../plugins/nightshift/runtime/windows/archive-receipts.ps1"
ARCHIVE_SKILL="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/archive/SKILL.md"

new_artifact() {
  local p="$BATS_TEST_TMPDIR/${1:-artifact}"
  mkdir -p "$p/.nightshift" "$p/out"
  cp "$RULES_TEMPLATE" "$p/.nightshift/rules.json"
  : >"$p/.nightshift/.shift-armed"
  printf 'artifact\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$(cd -P "$p" && pwd)" >"$p/.nightshift/work-target"
  printf '%s' "$p"
}

@test "archive-receipts copies regular receipts and leaves live copies" {
  p="$(new_artifact copy)"
  mkdir -p "$p/.nightshift/receipts"
  printf 'one\n' >"$p/.nightshift/receipts/20260101T000000Z-one.md"
  printf 'two\n' >"$p/.nightshift/receipts/20260101T000001Z-two.md"
  run bash "$ARCHIVE_SH" --project "$p" --date 2026-08-28
  [ "$status" -eq 0 ]
  dest="$output"
  case "$dest" in */.nightshift/archive/2026-08-28/receipts) ;; *) echo "dest=$dest"; return 1 ;; esac
  [ -f "$p/.nightshift/receipts/20260101T000000Z-one.md" ]
  [ -f "$p/.nightshift/receipts/20260101T000001Z-two.md" ]
  [ -f "$dest/20260101T000000Z-one.md" ]
  [ -f "$dest/20260101T000001Z-two.md" ]
  grep -qF 'one' "$dest/20260101T000000Z-one.md"
}

@test "archive-receipts skips hidden files and does not follow symlink receipts" {
  p="$(new_artifact hidden)"
  mkdir -p "$p/.nightshift/receipts"
  printf 'real\n' >"$p/.nightshift/receipts/20260101T000000Z-real.md"
  printf 'dot\n' >"$p/.nightshift/receipts/.not-a-receipt"
  ln -s "$p/.nightshift/receipts/20260101T000000Z-real.md" \
    "$p/.nightshift/receipts/20260101T000000Z-link.md"
  run bash "$ARCHIVE_SH" --project "$p" --date 2026-08-28
  [ "$status" -eq 0 ]
  dest="$p/.nightshift/archive/2026-08-28/receipts"
  [ -f "$dest/20260101T000000Z-real.md" ]
  [ ! -e "$dest/.not-a-receipt" ]
  [ ! -e "$dest/20260101T000000Z-link.md" ]
}

@test "archive-receipts is success when no receipts exist" {
  p="$(new_artifact empty)"
  run bash "$ARCHIVE_SH" --project "$p" --date 2026-08-28
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$p/.nightshift/archive/2026-08-28/receipts" ]
}

@test "archive-receipts refuses a malformed date and a missing project" {
  p="$(new_artifact bad-date)"
  run bash "$ARCHIVE_SH" --project "$p" --date not-a-date
  [ "$status" -eq 1 ]
  run bash "$ARCHIVE_SH" --project /no/such/nightshift-project
  [ "$status" -eq 1 ]
}

@test "archive-receipts refuses a symlink archive path" {
  p="$(new_artifact symlink-archive)"
  mkdir -p "$p/.nightshift/receipts" "$p/outside"
  printf 'real\n' >"$p/.nightshift/receipts/20260101T000000Z-real.md"
  ln -s "$p/outside" "$p/.nightshift/archive"
  run bash "$ARCHIVE_SH" --project "$p" --date 2026-08-28
  [ "$status" -eq 2 ]
  [ ! -e "$p/outside/receipts/20260101T000000Z-real.md" ]
}

@test "Archive skill names the receipts helper on POSIX and Windows" {
  grep -qF 'runtime/archive-receipts.sh' "$ARCHIVE_SKILL"
  grep -qF 'runtime\windows\archive-receipts.ps1' "$ARCHIVE_SKILL"
  grep -qF 'leave the live copies' "$ARCHIVE_SKILL"
  grep -qF 'Never delete live receipts' "$ARCHIVE_SKILL"
  grep -qF 'Never call `archive-receipts.sh`' "$ARCHIVE_SKILL"
  [ -f "$ARCHIVE_PS1" ]
  grep -qF 'Get-NSReceiptsDir' "$ARCHIVE_PS1"
  grep -qF "StartsWith('.')" "$ARCHIVE_PS1"
}
