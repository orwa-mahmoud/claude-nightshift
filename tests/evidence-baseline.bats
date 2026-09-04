#!/usr/bin/env bats
# Baseline records — one per originating source, written before the first fix.

# `run --separate-stderr` is a Bats >=1.5.0 feature; declaring the requirement up front stops
# Bats from emitting an advisory BW002 warning on every run.
bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
BL="$ROOT/plugins/nightshift/runtime/evidence-baseline.sh"
EV="$ROOT/plugins/nightshift/runtime/evidence.sh"

load helpers

NOW=2026-09-02T02:30:00Z

# The exact POSIX toolset a from-scratch bash implementation may lean on, with and without jq,
# mirroring the ledger's own parity toolsets so both halves probe the same real binaries.
BASELINE_TOOLSET_WITH_JQ="mktemp chmod bash sh jq git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm mv env cmp date uname test dirname basename readlink stat printf true false xargs shasum openssl"
BASELINE_TOOLSET_NO_JQ="mktemp chmod bash sh git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm mv env cmp date uname test dirname basename readlink stat printf true false xargs shasum openssl"

# ---------------------------------------------------------------------------------------------
# Fixtures. A shift control file is written by a helper, never by an inline command string, so a
# test that plants one states every line of it.

# session_host <project> <host> — the conversation record, whose fifth line names the host.
session_host() {
  printf '%s\n%s\n%s\n%s\n%s\n' the-shift "" "" "" "$2" >"$1/.nightshift/.shift-session"
}

# work_target_record <project> <path> — the work target Setup stored, absolute or relative.
work_target_record() {
  printf '%s\n' "$2" >"$1/.nightshift/work-target"
}

# finding <id> <sourceClass> <digest> — an ordinary finding, with its digest stated so the
# ledger computes nothing and the expected baseline inventory is exact.
finding() {
  jq -nc --arg id "$1" --arg class "$2" --arg digest "$3" '{
    schemaVersion:1, id:$id, domain:"lint", sourceClass:$class,
    source:"nsfakelint .", scope:"src/", severity:"medium", confidence:"high",
    impact:"developer", status:"open", ladder:"observed", locator:"src/app.js:3",
    digest:$digest, firstSeen:"2026-09-01T00:00:00Z",
    lastChecked:"2026-09-01T00:00:00Z", action:"fix", host:"claude", workTarget:"/repo"
  }'
}

# sha256_stdin — the digest of stdin, through whichever tool this host has.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# record <project> <id> — the one ledger line with that id.
record() {
  jq -c --arg id "$2" 'select(.id == $id)' "$1/.nightshift/evidence/findings.jsonl"
}

# ---------------------------------------------------------------------------------------------

@test "a baseline states the source, the environment, and the findings it starts from" {
  p="$(new_project bl-shape)"
  bash "$EV" --project "$p" init >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f1 eslint d1)" >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f2 eslint d2)" >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f9 stylelint d9)" >/dev/null

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint . -f json' --scope src/
  [ "$status" -eq 0 ]
  id="$output"
  case "$id" in baseline-eslint-*) ;; *) echo "unexpected id: $id"; return 1 ;; esac

  rec="$(record "$p" "$id")"
  printf '%s' "$rec" | jq -e '.domain == "baseline"' >/dev/null
  printf '%s' "$rec" | jq -e '.sourceClass == "eslint"' >/dev/null
  printf '%s' "$rec" | jq -e '.source == "nsfakelint . -f json"' >/dev/null
  printf '%s' "$rec" | jq -e '.severity == "info" and .confidence == "high"' >/dev/null
  printf '%s' "$rec" | jq -e '.impact == "none" and .status == "open"' >/dev/null
  printf '%s' "$rec" | jq -e '.ladder == "observed"' >/dev/null
  printf '%s' "$rec" | jq -e '.details | keys == ["command","environmentDigest","rawDigest","scope","seen","sourceClass","versions"]' >/dev/null
  printf '%s' "$rec" | jq -e '.details.command == "nsfakelint . -f json"' >/dev/null
  printf '%s' "$rec" | jq -e '.details.sourceClass == "eslint" and .details.scope == "src/"' >/dev/null
  printf '%s' "$rec" | jq -e '.details.rawDigest == ""' >/dev/null
  printf '%s' "$rec" | jq -e '.details.seen == [{"digest":"d1","id":"f1"},{"digest":"d2","id":"f2"}]' >/dev/null
}

@test "the environment digest is the sorted version lines and nothing else" {
  p="$(new_project bl-env)"
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .'
  [ "$status" -eq 0 ]
  id="$output"
  rec="$(record "$p" "$id")"

  # A command whose executable is nowhere on PATH reads as unavailable, never as a version.
  printf '%s' "$rec" | jq -e '.details.versions | length == 3' >/dev/null
  printf '%s' "$rec" | jq -e '.details.versions | index("nsfakelint\tunavailable") != null' >/dev/null
  printf '%s' "$rec" | jq -e --arg os "$(uname -s)" '.details.versions | index("os\t" + $os) != null' >/dev/null
  printf '%s' "$rec" | jq -e '.details.versions == (.details.versions | sort)' >/dev/null

  expected="$(printf 'nsfakelint\tunavailable\nos\t%s\nosRelease\t%s\n' \
    "$(uname -s)" "$(uname -r)" | sha256_stdin)"
  printf '%s' "$rec" | jq -e --arg d "$expected" '.details.environmentDigest == $d' >/dev/null
}

@test "an environment assignment never becomes the probed executable" {
  p="$(new_project bl-envprefix)"
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'CI=1 NODE_ENV=test nsfakelint .'
  [ "$status" -eq 0 ]
  rec="$(record "$p" "$output")"
  printf '%s' "$rec" | jq -e '.details.versions | index("nsfakelint\tunavailable") != null' >/dev/null
  printf '%s' "$rec" | jq -e '.details.versions | length == 3' >/dev/null
}

@test "--raw stores the captured output and measures the baseline" {
  p="$(new_project bl-raw)"
  raw="$BATS_TEST_TMPDIR/eslint.out"
  printf 'src/app.js:3 no-unused-vars\nsrc/app.js:9 eqeqeq\n' >"$raw"

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint . -f json' --raw "$raw"
  [ "$status" -eq 0 ]
  id="$output"
  [ -f "$p/.nightshift/evidence/raw/$id.txt" ]
  cmp "$p/.nightshift/evidence/raw/$id.txt" "$raw"

  rec="$(record "$p" "$id")"
  printf '%s' "$rec" | jq -e '.ladder == "measured"' >/dev/null
  printf '%s' "$rec" | jq -e --arg l "evidence/raw/$id.txt" '.locator == $l' >/dev/null
  # The record's own digest and the ledger's describe the same bytes.
  printf '%s' "$rec" | jq -e '.details.rawDigest == .rawDigest' >/dev/null
  printf '%s' "$rec" | jq -e --arg d "$(sha256_stdin <"$raw")" '.details.rawDigest == $d' >/dev/null
}

@test "a baseline names the shift's host and the stored work target" {
  p="$(new_workspace bl-target)"
  session_host "$p" codex
  work_target_record "$p" repo

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class tsc --command 'nsfaketsc --noEmit'
  [ "$status" -eq 0 ]
  target="$(cd -P "$p/repo" && pwd)"
  rec="$(record "$p" "$output")"
  printf '%s' "$rec" | jq -e '.host == "codex"' >/dev/null
  printf '%s' "$rec" | jq -e --arg t "$target" '.workTarget == $t and .locator == $t' >/dev/null
}

@test "the inventory is that source class only, at its latest state, without earlier baselines" {
  p="$(new_project bl-inventory)"
  bash "$EV" --project "$p" init >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f1 eslint d1)" >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f1 eslint d1-again)" >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f9 stylelint d9)" >/dev/null

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .' --scope src/
  [ "$status" -eq 0 ]
  first="$output"
  rec="$(record "$p" "$first")"
  printf '%s' "$rec" | jq -e '.details.seen == [{"digest":"d1-again","id":"f1"}]' >/dev/null

  run env NIGHTSHIFT_EVIDENCE_NOW=2026-09-02T03:30:00Z bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .' --scope src/
  [ "$status" -eq 0 ]
  second="$output"
  [ "$second" != "$first" ]
  rec="$(record "$p" "$second")"
  printf '%s' "$rec" | jq -e '.details.seen == [{"digest":"d1-again","id":"f1"}]' >/dev/null
}

@test "the same source at the same moment is the same baseline id" {
  p="$(new_project bl-id)"
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .' --scope src/
  [ "$status" -eq 0 ]
  first="$output"
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .' --scope src/
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint . --fix' --scope src/
  [ "$status" -eq 0 ]
  [ "$output" != "$first" ]
}

@test "a baseline refuses incomplete arguments, a missing raw file, and no workspace" {
  p="$(new_project bl-usage)"
  run bash "$BL" --project "$p" --source-class eslint
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qF 'usage: evidence-baseline.sh --project DIR'
  run bash "$BL" --source-class eslint --command 'nsfakelint .'
  [ "$status" -eq 1 ]
  run bash "$BL" --project "$p" --command 'nsfakelint .'
  [ "$status" -eq 1 ]
  run bash "$BL" --project "$p" --source-class eslint --command ''
  [ "$status" -eq 1 ]

  run bash "$BL" --project "$p" --source-class eslint --command 'nsfakelint .' \
    --raw "$BATS_TEST_TMPDIR/never-written.out"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qF 'no raw output at'

  bare="$BATS_TEST_TMPDIR/bl-bare"
  mkdir -p "$bare"
  run bash "$BL" --project "$bare" --source-class eslint --command 'nsfakelint .'
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -qF 'no .nightshift/ at'
}

@test "a malformed ledger stops the baseline instead of silently starting a new one" {
  p="$(new_project bl-malformed)"
  bash "$EV" --project "$p" init >/dev/null
  printf 'not json\n' >"$p/.nightshift/evidence/findings.jsonl"
  run --separate-stderr env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .'
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'cannot read the ledger at'
  if printf '%s\n' "$stderr" | grep -qF 'Traceback'; then
    return 1
  fi
}

@test "jq and python3 write the same baseline bytes" {
  export NIGHTSHIFT_EVIDENCE_NOW="$NOW"
  p="$(new_project bl-parity)"
  withjq="$(build_toolset_bin bl-with-jq $BASELINE_TOOLSET_WITH_JQ)"
  nojq="$(build_toolset_bin bl-no-jq $BASELINE_TOOLSET_NO_JQ)"
  pybin="$(build_toolset_bin bl-python $BASELINE_TOOLSET_NO_JQ python3)"
  [ ! -e "$withjq/python3" ]
  [ ! -e "$nojq/jq" ]

  run env PATH="$withjq" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint . -f json' --scope src/
  [ "$status" -eq 0 ]
  run env PATH="$pybin" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint . -f json' --scope src/
  [ "$status" -eq 0 ]

  ledger="$p/.nightshift/evidence/findings.jsonl"
  [ "$(wc -l <"$ledger" | tr -d ' ')" = 2 ]
  [ "$(sed -n 1p "$ledger")" = "$(sed -n 2p "$ledger")" ]
}

@test "a baseline needs jq or python3 to read JSON" {
  p="$(new_project bl-neither)"
  bin="$(build_toolset_bin bl-neither-bin $BASELINE_TOOLSET_NO_JQ)"
  [ ! -e "$bin/jq" ]
  [ ! -e "$bin/python3" ]
  run --separate-stderr env PATH="$bin" bash "$BL" --project "$p" \
    --source-class eslint --command 'nsfakelint .'
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'JSON parser unavailable'
}

# The skills tell the model to write the baseline itself, from the templates. The helper still
# ships for a caller that wants a machine-written ledger row; the shift does not require it.
@test "the shift skills say when a baseline is written" {
  for f in "$ROOT/plugins/nightshift/skills/start/SKILL.md" \
    "$ROOT/plugins/nightshift/skills/nightshift/SKILL.md"; do
    tr '\n' ' ' <"$f" | grep -qF 'once per source class' \
      || { echo "no baseline trigger: $f"; return 1; }
    grep -qF 'references/receipt-templates.md' "$f" \
      || { echo "no receipt templates: $f"; return 1; }
  done
}
