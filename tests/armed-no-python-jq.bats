#!/usr/bin/env bats
# 06A — a one-prompt feature night on a PATH with neither python3 nor jq.

load helpers

ROOT="$BATS_TEST_DIRNAME/.."
PLUGIN="$ROOT/plugins/nightshift"
HELPER="$BATS_TEST_DIRNAME/helpers/armed-path-no-parser.sh"
QUALITY="$PLUGIN/skills/quality/SKILL.md"
HUNT="$PLUGIN/skills/hunt/SKILL.md"
START="$PLUGIN/skills/start/SKILL.md"

# bash, coreutils, git, and the hook readers. No python3. No jq.
ARMED_PATH_TOOLSET="bash sh sed tr sort grep cut awk cat mktemp uname date \
rm mv cp ln printf head tail wc find test dirname basename cksum env true false \
chmod git touch mkdir sleep kill ps stat cmp xargs ls readlink"

@test "Quality routes a feature sentence to Hunt and keeps a quality sentence" {
  grep -qF 'continue as Hunt / Product Evolution' "$QUALITY"
  grep -qF 'Do not show Quality catalog cards' "$QUALITY"
  grep -qF 'stay in this skill' "$QUALITY"
  grep -qF 'use the next 20 hours adding features and enhancing existing ones' "$HUNT"
  grep -qF '8 hours clear lint and test debt' "$HUNT"
  grep -qF 'arm using `$NS/rules.json` alone' "$START"
  ! grep -qF 'python3' "$QUALITY"
  ! grep -qF 'python3' "$HUNT"
}

@test "the plugin ships no Python" {
  run git -C "$ROOT" ls-files 'plugins/nightshift/**/*.py'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an armed feature shift runs Setup through clock-out without python3 or jq" {
  bin="$(build_toolset_bin armed-no-parser-bin $ARMED_PATH_TOOLSET)"
  [ ! -e "$bin/python3" ]
  [ ! -e "$bin/jq" ]

  p="$BATS_TEST_TMPDIR/armed-feature"
  mkdir -p "$p"
  git -C "$p" init -q
  git -C "$p" config user.email tester@example.com
  git -C "$p" config user.name tester
  git -C "$p" commit -q --allow-empty -m init

  run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    bash "$HELPER" --plugin-root "$PLUGIN" --project "$p"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  printf '%s\n' "$output" | grep -qF 'PATH has neither python3 nor jq'
  printf '%s\n' "$output" | grep -qF 'ns_rules_check → 0'
  printf '%s\n' "$output" | grep -qF 'arm from rules.json alone'
  printf '%s\n' "$output" | grep -qF 'hardhat /usr/bin/sudo → deny'
  printf '%s\n' "$output" | grep -qF 'hardhat .nightshift//shift-policy.json write → deny'
  printf '%s\n' "$output" | grep -qF 'clock-out unreadable punch list → block (no release)'
  printf '%s\n' "$output" | grep -qF 'tick + receipt + clock-out → release'
  printf '%s\n' "$output" | grep -qF 'export-support default bundle omits planted ghp_ / AKIA'
  printf '%s\n' "$output" | grep -qxF 'armed-path: ok'
}
