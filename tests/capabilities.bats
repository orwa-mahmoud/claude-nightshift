#!/usr/bin/env bats
# Read-only capability registry and detector.

# `run --separate-stderr` (used below) is a Bats >=1.5.0 feature; declaring the requirement
# up front stops Bats from emitting an advisory BW002 warning on every run under 1.14.0.
bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
DETECT="$ROOT/plugins/nightshift/runtime/detect-capabilities.sh"
DETECT_PY="$ROOT/plugins/nightshift/runtime/detect-capabilities.py"
DETECT_PS1="$ROOT/plugins/nightshift/runtime/windows/detect-capabilities.ps1"
REQ="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/catalog-requirements.json"
CAPS="$ROOT/plugins/nightshift/skills/nightshift/references/schemas/v1/capabilities.json"
SHIFTS="$ROOT/plugins/nightshift/skills/nightshift/references/shifts"
FIXTURES="$ROOT/evals/fixtures/v1"

# Resolved once per test process (Bats re-sources this whole file per @test). Empty when no
# pwsh binary exists anywhere on the real PATH.
PWSH_BIN="$(command -v pwsh 2>/dev/null || true)"

load helpers

@test "every catalog entry declares capability requirements" {
  jq -e '.schemaVersion == 1' "$REQ" >/dev/null
  for f in "$SHIFTS"/*.md; do
    id="$(basename "$f" .md)"
    jq -e --arg id "$id" '.contracts | has($id)' "$REQ" >/dev/null \
      || { echo "missing requirements: $id"; return 1; }
    jq -e --arg id "$id" '
      .contracts[$id] | (
        (.requires | type) == "array"
        and (.requiresAny | type) == "array"
        and (
          (.fallback | type) == "string"
          or .fallback == null
          or .tooling == "none"
        )
      )
    ' "$REQ" >/dev/null || { echo "incomplete requirements: $id"; return 1; }
  done
}

@test "the capability registry lists the required domains" {
  for cap in test coverage lint typecheck dead-code accessibility security \
    api-schema localization documentation-link benchmark mutation-fuzz \
    seo-performance source-export connector owner-gates scripts ci; do
    jq -e --arg c "$cap" '.capabilities | index($c)' "$CAPS" >/dev/null \
      || { echo "registry missing $cap"; return 1; }
  done
  jq -e '.provisioningDefault == "existing-tools"' "$CAPS" >/dev/null
}

@test "the same fixture normalizes identically across host adapters" {
  p="$(new_project js)"
  cp "$FIXTURES/repo-js/package.json" "$p/package.json"
  mkdir -p "$p/tests"
  cp "$FIXTURES/repo-js/tests/addition.test.js" "$p/tests/addition.test.js"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  a="$BATS_TEST_TMPDIR/claude.json"
  b="$BATS_TEST_TMPDIR/codex.json"
  c="$BATS_TEST_TMPDIR/cursor.json"
  bash "$DETECT" --project "$p" --host claude --normalize >"$a"
  bash "$DETECT" --project "$p" --host codex --normalize >"$b"
  bash "$DETECT" --project "$p" --host cursor --normalize >"$c"
  diff -u "$a" "$b"
  diff -u "$b" "$c"
  jq -e '.capabilities.test.status == "available-and-verified"' "$a" >/dev/null
  jq -e '.contracts["coverage-hunt"].applies == true' "$a" >/dev/null
}

@test "artifact mode reports file capabilities and never repository tools" {
  w="$BATS_TEST_TMPDIR/artifact"
  mkdir -p "$w/.nightshift"
  printf 'artifact\n' >"$w/.nightshift/work-mode"
  printf '%s\n' "$w" >"$w/.nightshift/work-target"
  cp "$FIXTURES/artifact-notes/notes.md" "$w/notes.md"
  cp "$FIXTURES/artifact-notes/index.html" "$w/index.html"
  run bash "$DETECT" --project "$w" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.workMode == "artifact"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities["local-markdown"].status == "available-and-verified"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities.test.status == "unavailable"' >/dev/null
  printf '%s\n' "$output" | jq -e '.capabilities.test.reason | test("artifact mode")' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts["coverage-hunt"].applies == false' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts["seo-audit"].applies == true' >/dev/null
}

@test "a package name without a usable command is not treated as verified tooling" {
  p="$(new_project named)"
  printf '%s\n' '{"name":"has-eslint-dep","devDependencies":{"eslint":"9.0.0"}}' >"$p/package.json"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  run env PATH="/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.capabilities.lint.status == "unavailable"' >/dev/null
}

@test "a present command that fails --version is failing, not missing" {
  p="$(new_project broken)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'echo broken >&2' 'exit 7' >"$bin/eslint"
  chmod +x "$bin/eslint"
  printf '%s\n' '{"scripts":{"lint":"eslint ."}}' >"$p/package.json"
  run env PATH="$bin:/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  # declared script still verifies; force probe of eslint via PATH by removing scripts
  printf '%s\n' '{"name":"x"}' >"$p/package.json"
  run env PATH="$bin:/usr/bin:/bin" bash "$DETECT" --project "$p" --host claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.capabilities.lint.status == "available-but-failing"' >/dev/null
}

@test "detection does not write or install anything in the work target" {
  p="$(new_project ro)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  printf '%s\n' '{"name":"ro"}' >"$p/package.json"
  before="$(find "$p" -print | sort)"
  bash "$DETECT" --project "$p" --host claude >/dev/null
  after="$(find "$p" -print | sort)"
  [ "$before" = "$after" ]
}

@test "unsupported environment explains that quality cannot gather toolchain evidence" {
  p="$(new_project empty)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  run env PATH="/usr/bin:/bin" bash "$DETECT" --project "$p" --host cursor
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.contracts.quality.status == "fallback-only"' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts.quality.reason | test("fallback")' >/dev/null
  printf '%s\n' "$output" | jq -e '.contracts.quality.missing | length > 0' >/dev/null
}

# ---------------------------------------------------------------------------------------------
# Native-detector parity: the bash detector (detect-capabilities.sh), the Python reference
# (detect-capabilities.py), and the native PowerShell detector (windows/detect-capabilities.ps1)
# must emit byte-identical JSON for the same fixture and PATH. The pwsh leg runs whenever a pwsh
# binary exists and is skipped, never silently, when it does not.

have_pwsh() { [ -n "$PWSH_BIN" ]; }

# controlled_bin <dir-name> — makes and echoes an empty $BATS_TEST_TMPDIR/<dir-name> for a
# test to drop fake executables into.
controlled_bin() {
  local d="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

# fake_exe <dir> <name> <script-line...> — writes an executable POSIX shell script.
fake_exe() {
  local dir="$1" name="$2"
  shift 2
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$@"
  } >"$dir/$name"
  chmod +x "$dir/$name"
}

# fake_node <bin-dir> — a `node` that always prints a fixed version string, so the `test`
# capability probe is deterministic regardless of what real node (if any) the host has.
fake_node() { fake_exe "$1" node 'echo v20.0.0'; }

# build_fixture_js <name> — evals/fixtures/v1/repo-js in repository mode with an owner Gates
# block in the punch list. Echoes the project path. Does not put a `node` on PATH itself —
# callers control that via the PATH they run the detector with, so the same fixture can be
# probed both with and without a working toolchain.
build_fixture_js() {
  local p
  p="$(new_project "$1")"
  cp "$FIXTURES/repo-js/package.json" "$p/package.json"
  mkdir -p "$p/tests"
  cp "$FIXTURES/repo-js/tests/addition.test.js" "$p/tests/addition.test.js"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  printf '%s\n' '## Gates' '- [ ] ship it' >"$p/.nightshift/punch-list.md"
  printf '%s' "$p"
}

# resolve_tool_path <tool> — prints an absolute path for <tool>. Bypasses any shell function
# or alias of the same name in the calling shell (a wrapped `grep`/`find`, say) so it can never
# leak into a fixture's controlled PATH, and falls back to /bin or /usr/bin for builtins like
# `test`, `printf`, `true`, `false` that `command -v` reports by bare name only.
resolve_tool_path() {
  local tool="$1" real cand
  real="$(unset -f "$tool" 2>/dev/null; command -v "$tool" 2>/dev/null)"
  case "$real" in
  */*)
    printf '%s' "$real"
    return 0
    ;;
  esac
  for cand in "/bin/$tool" "/usr/bin/$tool"; do
    if [ -x "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

# build_toolset_bin <dir-name> <tool...> — makes $BATS_TEST_TMPDIR/<dir-name> containing a
# symlink to each named tool's real, resolved location. Echoes the dir path.
build_toolset_bin() {
  local d tool real
  d="$BATS_TEST_TMPDIR/$1"
  shift
  mkdir -p "$d"
  for tool in "$@"; do
    real="$(resolve_tool_path "$tool")" || { echo "test host is missing required tool: $tool" >&2; return 1; }
    ln -s "$real" "$d/$tool"
  done
  printf '%s' "$d"
}

# The exact POSIX toolset a from-scratch bash implementation may lean on (per lib/state.sh
# style): everything a native detector needs to walk a tree, read text, and shell out to jq —
# deliberately excluding python3 for the first list, and excluding both jq and python3 for the
# second.
POSIX_TOOLSET_WITH_JQ="bash sh jq git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm env cmp date uname test dirname basename readlink stat printf true false xargs"
POSIX_TOOLSET_NO_JQ="bash sh git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm env cmp date uname test dirname basename readlink stat printf true false xargs"

# assert_all_engines_agree <project> <controlled-PATH> [host]
#
# Runs the Python reference and the bash detector under an identical PATH, for both raw and
# --normalize output, and asserts they are byte-identical (cmp). When a pwsh binary exists on
# the real PATH it also runs the native PowerShell detector the same way and compares it to the
# same reference. A present pwsh binary with no detect-capabilities.ps1 is a genuine failure;
# only a truly missing pwsh binary is a `skip`.
assert_all_engines_agree() {
  local p="$1" cpath="$2" host="${3:-claude}"
  local py_raw="$BATS_TEST_TMPDIR/engine.py.raw.json"
  local py_norm="$BATS_TEST_TMPDIR/engine.py.norm.json"
  local sh_raw="$BATS_TEST_TMPDIR/engine.sh.raw.json"
  local sh_norm="$BATS_TEST_TMPDIR/engine.sh.norm.json"

  env PATH="$cpath" python3 "$DETECT_PY" --project "$p" --host "$host" >"$py_raw"
  env PATH="$cpath" python3 "$DETECT_PY" --project "$p" --host "$host" --normalize >"$py_norm"
  env PATH="$cpath" bash "$DETECT" --project "$p" --host "$host" >"$sh_raw"
  env PATH="$cpath" bash "$DETECT" --project "$p" --host "$host" --normalize >"$sh_norm"

  cmp "$py_raw" "$sh_raw"
  cmp "$py_norm" "$sh_norm"

  if have_pwsh; then
    [ -f "$DETECT_PS1" ] || { echo "native PowerShell detector is missing: $DETECT_PS1" >&2; return 1; }
    local ps1_raw="$BATS_TEST_TMPDIR/engine.ps1.raw.json"
    local ps1_norm="$BATS_TEST_TMPDIR/engine.ps1.norm.json"
    # $PWSH_BIN is an absolute path so `env PATH=...` (which controls what the *child* sees)
    # doesn't also have to be able to locate pwsh itself.
    env PATH="$cpath" "$PWSH_BIN" -NoProfile -NonInteractive -File "$DETECT_PS1" -Project "$p" -HostName "$host" >"$ps1_raw"
    env PATH="$cpath" "$PWSH_BIN" -NoProfile -NonInteractive -File "$DETECT_PS1" -Project "$p" -HostName "$host" -Normalize >"$ps1_norm"
    cmp "$py_raw" "$ps1_raw"
    cmp "$py_norm" "$ps1_norm"
  else
    skip "pwsh not found on PATH; skipping PowerShell parity leg"
  fi
}

@test "parity: repo-js with a verified node toolchain and an owner Gates block" {
  p="$(build_fixture_js parity-js)"
  bin="$(controlled_bin parity-js-bin)"
  fake_node "$bin"
  assert_all_engines_agree "$p" "$bin:/usr/bin:/bin"
}

@test "parity: artifact mode only probes file capabilities" {
  w="$BATS_TEST_TMPDIR/parity-artifact"
  mkdir -p "$w/.nightshift"
  printf 'artifact\n' >"$w/.nightshift/work-mode"
  printf '%s\n' "$w" >"$w/.nightshift/work-target"
  cp "$FIXTURES/artifact-notes/notes.md" "$w/notes.md"
  cp "$FIXTURES/artifact-notes/index.html" "$w/index.html"
  assert_all_engines_agree "$w" "/usr/bin:/bin"
}

@test "parity: a package.json dependency name alone is not verified tooling" {
  p="$(new_project parity-named)"
  printf '%s\n' '{"name":"x","devDependencies":{"eslint":"9.0.0"}}' >"$p/package.json"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  assert_all_engines_agree "$p" "/usr/bin:/bin"
}

@test "parity: a broken eslint is available-but-failing, not missing" {
  p="$(new_project parity-broken)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  printf '%s\n' '{"name":"x"}' >"$p/package.json"
  bin="$(controlled_bin parity-broken-bin)"
  fake_exe "$bin" eslint 'echo broken >&2' 'exit 7'
  assert_all_engines_agree "$p" "$bin:/usr/bin:/bin"
}

@test "parity: an empty repository reports consistently" {
  p="$(new_project parity-empty)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"
  assert_all_engines_agree "$p" "/usr/bin:/bin"
}

@test "parity: a monorepo with packages, Makefile targets, CI, schema, locales, and a skipped symlink" {
  p="$(new_project parity-mono)"
  printf 'repository\n' >"$p/.nightshift/work-mode"
  printf '%s\n' "$p" >"$p/.nightshift/work-target"

  printf '%s\n' '{"name":"mono-root"}' >"$p/package.json"

  mkdir -p "$p/a"
  printf '%s\n' '{"name":"pkg-a","scripts":{"test":"node --test","lint":"eslint ."}}' >"$p/a/package.json"

  mkdir -p "$p/b"
  printf '%s\n' '[project]' 'name = "pkg-b"' >"$p/b/pyproject.toml"

  # A symlinked child dir carries a signal file too, but list_packages must skip it (it is not
  # a regular directory) so it must never show up as a package or contribute scripts/stacks.
  mkdir -p "$BATS_TEST_TMPDIR/parity-mono-outside"
  printf '%s\n' '{"name":"should-not-appear"}' >"$BATS_TEST_TMPDIR/parity-mono-outside/package.json"
  ln -s "$BATS_TEST_TMPDIR/parity-mono-outside" "$p/linked"

  printf 'build:\n\ttrue\n\ntest:\n\ttrue\n' >"$p/Makefile"

  mkdir -p "$p/.github/workflows"
  printf '%s\n' 'name: ci' 'on: push' >"$p/.github/workflows/ci.yml"

  printf '%s\n' 'openapi: 3.0.0' >"$p/openapi.yaml"

  mkdir -p "$p/locales"
  printf '%s\n' '{}' >"$p/locales/en.json"

  mkdir -p "$p/reports"
  printf '%s\n' '<testsuite/>' >"$p/reports/junit.xml"

  assert_all_engines_agree "$p" "/usr/bin:/bin"
}

@test "the bash detector needs no python3 when jq is present on PATH" {
  p="$(build_fixture_js no-python)"

  # One toolset directory serves both runs, so every probed tool (including the fake node)
  # resolves to the same path. Only python3 differs: the reference run reaches it through a
  # second directory that holds nothing else.
  bin="$(build_toolset_bin no-python-bin $POSIX_TOOLSET_WITH_JQ)"
  fake_node "$bin"
  [ ! -e "$bin/python3" ]
  pybin="$(build_toolset_bin no-python-pybin python3)"

  ref="$BATS_TEST_TMPDIR/no-python-ref.json"
  env PATH="$bin:$pybin" python3 "$DETECT_PY" --project "$p" --host claude --normalize >"$ref"

  run --separate-stderr env PATH="$bin" bash "$DETECT" --project "$p" --normalize
  [ "$status" -eq 0 ]
  out="$BATS_TEST_TMPDIR/no-python-out.json"
  printf '%s\n' "$output" >"$out"
  cmp "$ref" "$out"
}

@test "detect-capabilities requires jq or python3 on PATH" {
  p="$(build_fixture_js neither)"
  bin="$(build_toolset_bin neither-bin $POSIX_TOOLSET_NO_JQ)"
  [ ! -e "$bin/jq" ]
  [ ! -e "$bin/python3" ]

  run --separate-stderr env PATH="$bin" bash "$DETECT" --project "$p" --normalize
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'jq or python3 is required'
}

@test "the same fixture normalizes identically across every host adapter and detector engine" {
  p="$(build_fixture_js cross-engine)"
  bin="$(controlled_bin cross-engine-bin)"
  fake_node "$bin"
  cpath="$bin:/usr/bin:/bin"

  ref=""
  for h in claude codex cursor; do
    py_out="$BATS_TEST_TMPDIR/cross.$h.py.json"
    env PATH="$cpath" python3 "$DETECT_PY" --project "$p" --host "$h" --normalize >"$py_out"
    if [ -z "$ref" ]; then
      ref="$py_out"
    else
      cmp "$ref" "$py_out"
    fi

    sh_out="$BATS_TEST_TMPDIR/cross.$h.sh.json"
    env PATH="$cpath" bash "$DETECT" --project "$p" --host "$h" --normalize >"$sh_out"
    cmp "$ref" "$sh_out"
  done

  if have_pwsh; then
    [ -f "$DETECT_PS1" ] || { echo "native PowerShell detector is missing: $DETECT_PS1" >&2; return 1; }
    for h in claude codex cursor; do
      ps1_out="$BATS_TEST_TMPDIR/cross.$h.ps1.json"
      env PATH="$cpath" "$PWSH_BIN" -NoProfile -NonInteractive -File "$DETECT_PS1" -Project "$p" -HostName "$h" -Normalize >"$ps1_out"
      cmp "$ref" "$ps1_out"
    done
  else
    skip "pwsh not found on PATH; skipping PowerShell leg of cross-host/cross-engine normalization"
  fi
}
