BUG="$BATS_TEST_DIRNAME/../.github/ISSUE_TEMPLATE/bug_report.yml"
PR="$BATS_TEST_DIRNAME/../.github/PULL_REQUEST_TEMPLATE.md"
CONTRIBUTING="$BATS_TEST_DIRNAME/../CONTRIBUTING.md"

@test "bug reports offer Claude Code and Codex as first-class harnesses" {
  grep -qF 'Claude Code (hooks)' "$BUG"
  grep -qF 'OpenAI Codex (hooks and skills)' "$BUG"
}

@test "the pull request template asks about parity, not generic adapters" {
  grep -qF 'Harness parity (shared Claude Code / Codex behaviour)' "$PR"
  ! grep -qi 'Adapter (support for another harness)' "$PR"
  grep -qi 'not a generic adapter' "$CONTRIBUTING"
  grep -qF 'Claude Code and Codex' "$CONTRIBUTING"
}
