#!/usr/bin/env bats
# normalize-output turns one tool's raw output into one compact summary a model can read
# instead of the file, and that two nights can diff byte for byte. The golden fixtures are
# the contract: a change to the shape of a summary changes them, deliberately.

load helpers

ROOT="$BATS_TEST_DIRNAME/.."
PLUGIN="$ROOT/plugins/nightshift"
SH="$PLUGIN/runtime/normalize-output.sh"
PS1_TWIN="$PLUGIN/runtime/windows/normalize-output.ps1"
LOGIC="$BATS_TEST_DIRNAME/windows/normalize-output-logic.ps1"
RUN_PS1="$BATS_TEST_DIRNAME/windows/run.ps1"
FIX="$BATS_TEST_DIRNAME/fixtures/normalize"
PWSH_BIN="$(command -v pwsh 2>/dev/null || true)"

FORMATS="eslint-json tsc coverage-summary sarif npm-audit junit lcov"
CASES="sample edge broken"

# The extension a fixture case carries, so the goldens can sit beside their input.
fixture_input() {
  local fmt="$1" name="$2" f
  for f in "$FIX/$fmt/$name".*; do
    case "$f" in *.expected.*) continue ;; esac
    printf '%s' "tests/fixtures/normalize/$fmt/${f##*/}"
    return 0
  done
  return 1
}

# bash 3.2 is the floor this plugin supports, so every run goes through /bin/bash.
normalize() {
  run /bin/bash "$SH" "$@"
}

# Whichever sha256 tool this host carries; the helper picks the same one.
digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum <"$1" | cut -d' ' -f1
  else
    shasum -a 256 <"$1" | cut -d' ' -f1
  fi
}

@test "every format renders its golden markdown summary" {
  cd "$ROOT"
  for fmt in $FORMATS; do
    for name in $CASES; do
      input="$(fixture_input "$fmt" "$name")"
      normalize --format "$fmt" --input "$input"
      if [ "$name" = broken ]; then
        [ "$status" -eq 3 ] || { echo "$fmt/$name expected exit 3, got $status"; return 1; }
      else
        [ "$status" -eq 0 ] || { echo "$fmt/$name: $output"; return 1; }
      fi
      printf '%s\n' "$output" | diff - "$FIX/$fmt/$name.expected.md" \
        || { echo "$fmt/$name markdown drifted"; return 1; }
    done
  done
}

@test "every format renders its golden canonical JSON summary" {
  cd "$ROOT"
  for fmt in $FORMATS; do
    for name in $CASES; do
      input="$(fixture_input "$fmt" "$name")"
      normalize --format "$fmt" --input "$input" --json
      printf '%s\n' "$output" | diff - "$FIX/$fmt/$name.expected.json" \
        || { echo "$fmt/$name JSON drifted"; return 1; }
    done
  done
}

@test "the JSON summary is one canonical object with sorted keys" {
  cd "$ROOT"
  for fmt in $FORMATS; do
    for name in sample edge; do
      input="$(fixture_input "$fmt" "$name")"
      normalize --format "$fmt" --input "$input" --json
      [ "$status" -eq 0 ]
      [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
      printf '%s' "$output" | jq -e '
        .version == 1 and (.digest | test("^[0-9a-f]{64}$"))
        and (.headline | length) > 0 and (.items | type) == "array"
        and .shown == (.items | length) and .total >= .shown
      ' >/dev/null || { echo "$fmt/$name is not a usable finding body"; return 1; }
      printf '%s' "$output" | jq -e 'keys == (keys | sort)' >/dev/null
      printf '%s' "$output" | jq -e '.counts | keys == (keys | sort)' >/dev/null
      printf '%s' "$output" | jq -e '.items | all(keys == (keys | sort))' >/dev/null
    done
  done
}

@test "a finding body carries the fields a tool-output record needs" {
  cd "$ROOT"
  normalize --format eslint-json --input "$(fixture_input eslint-json sample)" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .format == "eslint-json" and .files == 3 and .total == 6
    and .counts.errors == 4 and .counts.warnings == 2
    and (.items[0] | .severity == "error" and .file == "src/app.js" and .line == 12)
  ' >/dev/null
}

# The summary is only worth having if the ledger can carry it. This builds the record the
# receipt template describes and appends it, so a change to either shape fails here.
@test "a tool-output summary becomes a record the evidence ledger accepts" {
  p="$(new_project normalize-ledger)"
  run /bin/bash "$PLUGIN/runtime/evidence.sh" --project "$p" init
  [ "$status" -eq 0 ]
  cd "$ROOT"
  summary="$(/bin/bash "$SH" --format eslint-json \
    --input "$(fixture_input eslint-json sample)" --json)"
  record="$(printf '%s' "$summary" | jq -c --arg target "$p" '{
    schemaVersion: 1, id: "eslint-baseline", domain: "tool-output", sourceClass: "tool",
    source: "eslint -f json .", sourceTool: "eslint", scope: ".", severity: "high",
    confidence: "high", impact: "developer", status: "open", ladder: "measured",
    locator: .input, digest: .digest, firstSeen: "2026-09-04T00:00:00Z",
    lastChecked: "2026-09-04T00:00:00Z", action: .headline, host: "claude",
    workTarget: $target, message: (.counts | tostring)
  }')"
  run /bin/bash "$PLUGIN/runtime/evidence.sh" --project "$p" append --record "$record"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  run /bin/bash "$PLUGIN/runtime/evidence.sh" --project "$p" render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '| eslint-baseline | tool-output |'
  digest="$(printf '%s' "$summary" | jq -r .digest)"
  grep -qF "$digest" "$p/.nightshift/evidence/findings.jsonl"
}

@test "rows sort by severity descending, then file, line, code and detail" {
  cd "$ROOT"
  normalize --format eslint-json --input "$(fixture_input eslint-json sample)"
  [ "$status" -eq 0 ]
  rows="$(printf '%s\n' "$output" \
    | awk -F' \\| ' '/^\| (error|warning|note|critical) / {
        sub(/^\| /, "", $1); print $1 "|" $2 "|" $3
      }')"
  [ "$(printf '%s\n' "$rows" | head -1)" = "error|src/app.js|12" ]
  [ "$(printf '%s\n' "$rows" | sed -n '3p')" = "error|src/lib/parse.js|1" ]
  [ "$(printf '%s\n' "$rows" | tail -1)" = "warning|src/lib/parse.js|90" ]
}

@test "the headline, the table and one anchored source line are the whole summary" {
  cd "$ROOT"
  normalize --format lcov --input "$(fixture_input lcov sample)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "lcov: 68.57% lines covered, 288/420 in 3 files" ]
  printf '%s\n' "$output" | grep -qx '| severity | file | line | code | detail |'
  printf '%s\n' "$output" | grep -qx 'showing 3 of 3 items'
  printf '%s\n' "$output" | tail -1 | grep -qE '^source: tests/fixtures/normalize/lcov/sample\.info sha256:[0-9a-f]{64}$'
  digest="$(printf '%s\n' "$output" | tail -1 | sed 's/.*sha256://')"
  [ "$digest" = "$(digest_of "$FIX/lcov/sample.info")" ]
}

@test "--top bounds the table and the count line still names the total" {
  cd "$ROOT"
  normalize --format eslint-json --input "$(fixture_input eslint-json sample)" --top 2
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^| error\|^| warning')" -eq 2 ]
  printf '%s\n' "$output" | grep -qx 'showing 2 of 6 items'

  normalize --format eslint-json --input "$(fixture_input eslint-json sample)" --top 0
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'showing 0 of 6 items'
  ! printf '%s\n' "$output" | grep -q '^| severity'
}

@test "pytest-junit is an alias: the same bytes as junit" {
  cd "$ROOT"
  normalize --format pytest-junit --input "$(fixture_input junit sample)"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | diff - "$FIX/junit/sample.expected.md"
  normalize --format pytest-junit --input "$(fixture_input junit sample)" --json
  printf '%s' "$output" | jq -e '.format == "junit"' >/dev/null
}

@test "an unreadable shape is unavailable with a reason, never zero findings" {
  cd "$ROOT"
  for fmt in $FORMATS; do
    normalize --format "$fmt" --input "$(fixture_input "$fmt" broken)"
    [ "$status" -eq 3 ] || { echo "$fmt broken exited $status"; return 1; }
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
    printf '%s\n' "$output" | grep -qE "^unavailable $fmt: .+" \
      || { echo "$fmt: $output"; return 1; }
    ! printf '%s\n' "$output" | grep -qi '0 errors'
  done
}

@test "a missing input is unavailable, and an unknown format is a usage error" {
  cd "$ROOT"
  normalize --format tsc --input "$BATS_TEST_TMPDIR/absent.txt"
  [ "$status" -eq 3 ]
  [ "$output" = "unavailable tsc: the input is not a readable file" ]

  normalize --format made-up --input "$(fixture_input tsc sample)"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'unknown format: made-up'

  normalize --format tsc
  [ "$status" -eq 1 ]
  normalize --input "$(fixture_input tsc sample)"
  [ "$status" -eq 1 ]
  normalize --format tsc --input "$(fixture_input tsc sample)" --top nine
  [ "$status" -eq 1 ]
}

@test "a JSON format needs jq; the awk formats do not" {
  cd "$ROOT"
  bin="$(build_toolset_bin normalize-no-jq bash sh awk sort sed grep cut tr cat head tail wc \
    mktemp rm mv cp printf test dirname basename env uname date find true false)"
  for tool in shasum sha256sum openssl; do
    real="$(command -v "$tool" 2>/dev/null)" && ln -sf "$real" "$bin/$tool"
  done
  [ ! -e "$bin/jq" ]
  [ ! -e "$bin/python3" ]

  for fmt in eslint-json coverage-summary sarif npm-audit; do
    run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      /bin/bash "$SH" --format "$fmt" --input "$(fixture_input "$fmt" sample)"
    [ "$status" -eq 3 ] || { echo "$fmt exited $status: $output"; return 1; }
    [ "$output" = "unavailable $fmt: jq is required to read this format and is not on PATH" ]
  done

  for fmt in tsc junit lcov; do
    run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      /bin/bash "$SH" --format "$fmt" --input "$(fixture_input "$fmt" sample)"
    [ "$status" -eq 0 ] || { echo "$fmt exited $status: $output"; return 1; }
    printf '%s\n' "$output" | diff - "$FIX/$fmt/sample.expected.md"
    run env -i PATH="$bin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      /bin/bash "$SH" --format "$fmt" --input "$(fixture_input "$fmt" sample)" --json
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | diff - "$FIX/$fmt/sample.expected.json"
  done
}

@test "carriage returns, tabs and non-ASCII bytes reduce to the same summary" {
  cd "$ROOT"
  printf 'src/a.ts(1,2): error TS1000: bad.\r\nFound 1 error.\r\n' >"$BATS_TEST_TMPDIR/crlf.txt"
  normalize --format tsc --input "$BATS_TEST_TMPDIR/crlf.txt"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '| error | src/a.ts | 1 | TS1000 | bad. |'

  printf 'src/x.ts(3,1): error TS2322: caf\xc3\xa9  keeps\tone space.\n' >"$BATS_TEST_TMPDIR/utf8.txt"
  normalize --format tsc --input "$BATS_TEST_TMPDIR/utf8.txt"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '| error | src/x.ts | 3 | TS2322 | caf keeps one space. |'
}

@test "a pipe in a detail is escaped in the table and kept in the JSON" {
  cd "$ROOT"
  normalize --format eslint-json --input "$(fixture_input eslint-json sample)"
  printf '%s\n' "$output" | grep -qF "Unexpected mix of '\\|\\|' and '&&'."
  normalize --format eslint-json --input "$(fixture_input eslint-json sample)" --json
  printf '%s' "$output" | jq -e '[.items[].message] | any(test("\\|\\|"))' >/dev/null
}

@test "the helper reads the project and writes nothing" {
  p="$(new_project normalize-readonly)"
  cp "$FIX/lcov/sample.info" "$p/lcov.info"
  git -C "$p" add -A
  git -C "$p" -c user.name=t -c user.email=t@example.com commit -q -m fixture
  before="$(git -C "$p" status --porcelain)"
  run /bin/bash "$SH" --format lcov --input "$p/lcov.info"
  [ "$status" -eq 0 ]
  [ "$(git -C "$p" status --porcelain)" = "$before" ]
  [ ! -e "$p/.nightshift/evidence" ]
}

@test "the same input always yields the same bytes" {
  cd "$ROOT"
  first="$(/bin/bash "$SH" --format sarif --input "$(fixture_input sarif sample)" --json)"
  second="$(/bin/bash "$SH" --format sarif --input "$(fixture_input sarif sample)" --json)"
  [ "$first" = "$second" ]
}

@test "the summary carries no carriage return and ends with one newline" {
  cd "$ROOT"
  /bin/bash "$SH" --format junit --input "$(fixture_input junit sample)" >"$BATS_TEST_TMPDIR/out.md"
  ! LC_ALL=C grep -q "$(printf '\r')" "$BATS_TEST_TMPDIR/out.md"
  [ "$(tail -c 1 "$BATS_TEST_TMPDIR/out.md" | od -An -c | tr -d ' ')" = '\n' ]
}

@test "the native Windows twin ships and is registered in the Windows suite" {
  [ -f "$PS1_TWIN" ]
  [ -f "$LOGIC" ]
  grep -qF 'normalize-output-logic.ps1' "$RUN_PS1"
  grep -qF 'normalize-output.ps1' "$PS1_TWIN"
}

# The parity proof: bash and PowerShell over the same fixture, diffed byte for byte. Two
# engines that agree here also agree with each other's ledger, which is the whole point of a
# summary a night can compare against another night.
@test "both engines print the same bytes for every fixture" {
  if ! have_pwsh; then
    skip 'pwsh not installed'
  fi
  cd "$ROOT"
  for fmt in $FORMATS; do
    for name in $CASES; do
      input="$(fixture_input "$fmt" "$name")"
      for mode in md json; do
        shflag=""
        psflag=""
        if [ "$mode" = json ]; then
          shflag=--json
          psflag=-Json
        fi
        # An unreadable fixture exits 3 on purpose; the line it prints is what we compare.
        /bin/bash "$SH" --format "$fmt" --input "$input" $shflag \
          >"$BATS_TEST_TMPDIR/sh.out" || true
        "$PWSH_BIN" -NoProfile -NonInteractive -File "$PS1_TWIN" \
          -Format "$fmt" -InputPath "$input" $psflag >"$BATS_TEST_TMPDIR/ps.out" || true
        cmp "$BATS_TEST_TMPDIR/sh.out" "$BATS_TEST_TMPDIR/ps.out" \
          || { echo "$fmt/$name $mode differs between engines"; return 1; }
      done
    done
  done
}

@test "the Windows logic suite passes when pwsh is present" {
  if ! have_pwsh; then
    skip 'pwsh not installed'
  fi
  run "$PWSH_BIN" -NoProfile -NonInteractive -File "$LOGIC"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "the composition and quality skills name the helper as optional" {
  QUALITY="$PLUGIN/skills/quality/SKILL.md"
  grep -qF 'runtime/normalize-output.sh' "$QUALITY"
  grep -qF 'If present,' "$QUALITY"
  grep -qF 'Both helpers below are optional' "$QUALITY"
  for shift in clear-quality-debt coverage-hunt vulnerability-sweep flaky-test-repair \
    api-contract-drift seo-audit; do
    grep -qF 'normalize-output.sh' "$PLUGIN/skills/nightshift/references/shifts/$shift.md" \
      || { echo "$shift does not name the helper"; return 1; }
  done
  grep -qF 'tool-output' "$PLUGIN/skills/nightshift/references/receipt-templates.md"
  grep -qF 'runtime/normalize-output.sh' "$ROOT/docs/evidence-capabilities.md"
}
