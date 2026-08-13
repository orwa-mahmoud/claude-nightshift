README="$BATS_TEST_DIRNAME/../README.md"
T="$BATS_TEST_DIRNAME/../examples/bad-night-template.md"
SECURITY="$BATS_TEST_DIRNAME/../SECURITY.md"

@test "README points at the bad-night template beside real receipts" {
  grep -qF '[`examples/bad-night-template.md`](examples/bad-night-template.md)' "$README"
  grep -qF 'orwa-mahmoud/nightshift/issues/22' "$README"
}

@test "the template separates facts from interpretation and refuses tick-as-proof" {
  grep -qF '## Facts (observed)' "$T"
  grep -qF '## Interpretation (yours, not the agent' "$T"
  grep -qi 'not independent proof' "$T"
  grep -qF '## Redaction checklist' "$T"
  grep -qF 'No prompts' "$T"
  grep -qF 'No credentials' "$T"
  grep -qF 'No full session transcript' "$T"
  grep -qF 'orwa-mahmoud/nightshift/issues/22' "$T"
  grep -qF 'security/advisories/new' "$T"
}

@test "the template asks for public links only when the run is public" {
  grep -qF 'only if the run is public' "$T"
  grep -qF 'This file is a template, not a recorded night' "$T"
  ! grep -qiE '2026-0[0-9]-[0-9]{2} .*watchman' "$T"
}

@test "bad-night template links resolve" {
  [ -f "$BATS_TEST_DIRNAME/../examples/adapttable-overnight.md" ]
  [ -f "$BATS_TEST_DIRNAME/../examples/codex-hardening-shift.md" ]
  [ -f "$BATS_TEST_DIRNAME/../docs/troubleshooting.md" ]
  [ -f "$SECURITY" ]
}
