README="$BATS_TEST_DIRNAME/../README.md"
DOC="$BATS_TEST_DIRNAME/../docs/morning-receipt.md"

@test "README links the morning receipt doc from the receipts section" {
  grep -qF '[Morning receipt](docs/morning-receipt.md)' "$README"
}

@test "morning-receipt doc covers every section, view, and the zero-gate line" {
  for heading in '## What each section means' '## Which view is for whom' '## Determinism'; do
    grep -qF "$heading" "$DOC" || { echo "missing: $heading"; return 1; }
  done
  grep -qF '**Shift**' "$DOC"
  grep -qF '**Baseline**' "$DOC"
  grep -qF '**What changed**' "$DOC"
  grep -qF '**Parked**' "$DOC"
  grep -qF '**Unsupported / unmeasured**' "$DOC"
  grep -qF '**Next**' "$DOC"
  grep -qF '`Verified:`' "$DOC"
  grep -qF '`Disabled by owner:`' "$DOC"
  grep -qF '`Unavailable:`' "$DOC"
  grep -qF 'Verified: none — verification level none (owner)' "$DOC"
  grep -qF '**owner**' "$DOC"
  grep -qF '**reviewer**' "$DOC"
  grep -qF '**release**' "$DOC"
  grep -qF '**artifact**' "$DOC"
  grep -qF 'no git terminology appears' "$DOC"
  grep -qF 'invents nothing' "$DOC"
  grep -qF 'never upgraded into proof' "$DOC"
  grep -qF 'runtime/morning-receipt.sh' "$DOC"
  grep -qF 'runtime/windows/morning-receipt.ps1' "$DOC"
  grep -qF '.nightshift/receipts/morning-<YYYY-MM-DD>-<shiftId>.md' "$DOC"
}

@test "morning-receipt doc names no competing tool" {
  if grep -qiE 'copilot|windsurf|cline|devin|aider' "$DOC"; then
    return 1
  fi
}
