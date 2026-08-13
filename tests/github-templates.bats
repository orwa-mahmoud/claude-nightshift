BUG="$BATS_TEST_DIRNAME/../.github/ISSUE_TEMPLATE/bug_report.yml"
FAILED="$BATS_TEST_DIRNAME/../.github/ISSUE_TEMPLATE/failed_shift.yml"
PR="$BATS_TEST_DIRNAME/../.github/PULL_REQUEST_TEMPLATE.md"
CONTRIBUTING="$BATS_TEST_DIRNAME/../CONTRIBUTING.md"
SECURITY="$BATS_TEST_DIRNAME/../SECURITY.md"

@test "bug reports offer Claude Code and Codex as first-class harnesses" {
  grep -qF 'Claude Code (hooks)' "$BUG"
  grep -qF 'OpenAI Codex (hooks and skills)' "$BUG"
}

@test "the pull request template asks about parity, not generic adapters" {
  grep -qF 'Harness parity (shared Claude Code / Codex behaviour)' "$PR"
  ! grep -qi 'Adapter (support for another harness)' "$PR"
  grep -qi 'not a generic adapter' "$CONTRIBUTING"
  grep -qF 'Codex and Claude Code' "$CONTRIBUTING"
}

parse_yaml() {
  ruby -ryaml -e 'YAML.load_file(ARGV[0]); puts "ok"' "$1"
}

@test "the failed-shift form is valid YAML with required diagnostic fields" {
  parse_yaml "$FAILED"
  grep -qF 'name: Failed shift' "$FAILED"
  grep -qF 'id: harness' "$FAILED"
  grep -qF 'id: plugin-version' "$FAILED"
  grep -qF 'id: host-version' "$FAILED"
  grep -qF 'id: expected' "$FAILED"
  grep -qF 'id: observed' "$FAILED"
  grep -qF 'id: markers' "$FAILED"
  grep -qF 'id: recovery' "$FAILED"
  grep -qF 'id: logs' "$FAILED"
}

@test "the failed-shift form redacts secrets and routes bypasses privately" {
  grep -qF 'Do not paste' "$FAILED"
  grep -qF 'prompts, credentials' "$FAILED"
  grep -qF 'full session transcript' "$FAILED"
  grep -qF 'https://github.com/orwa-mahmoud/nightshift/security/advisories/new' "$FAILED"
  grep -qF 'https://github.com/orwa-mahmoud/nightshift/blob/main/SECURITY.md' "$FAILED"
  grep -qF 'I have removed prompts, credentials, repository content, and full transcripts' "$FAILED"
  ! grep -qi 'paste the full transcript' "$FAILED"
  ! grep -qi 'include your prompt' "$FAILED"
}

@test "SECURITY.md points failed nights at the form and bypasses at advisories" {
  grep -qF 'issues/new?template=failed_shift.yml' "$SECURITY"
  grep -qF 'security/advisories/new' "$SECURITY"
  [ -f "$FAILED" ]
}

