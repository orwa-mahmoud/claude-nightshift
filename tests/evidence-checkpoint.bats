#!/usr/bin/env bats
# Checkpoint records — the state a risky cluster starts from.

# `run --separate-stderr` is a Bats >=1.5.0 feature; declaring the requirement up front stops
# Bats from emitting an advisory BW002 warning on every run.
bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
CP="$ROOT/plugins/nightshift/runtime/evidence-checkpoint.sh"
BL="$ROOT/plugins/nightshift/runtime/evidence-baseline.sh"
EV="$ROOT/plugins/nightshift/runtime/evidence.sh"

load helpers

NOW=2026-09-02T02:30:00Z

# The same parity toolsets the ledger and the baseline writer use, so every probed tool resolves
# to the same real binary with and without jq.
CHECKPOINT_TOOLSET_WITH_JQ="mktemp chmod bash sh jq git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm mv env cmp date uname test dirname basename readlink stat printf true false xargs shasum openssl"
CHECKPOINT_TOOLSET_NO_JQ="mktemp chmod bash sh git sed grep find sort ls awk cat tr head tail wc cut mkdir cp rm mv env cmp date uname test dirname basename readlink stat printf true false xargs shasum openssl"

# ---------------------------------------------------------------------------------------------
# Fixtures. A shift control file is written by a helper, never by an inline command string.

# work_target_record <project> <path> — the work target Setup stored, absolute or relative.
work_target_record() {
  printf '%s\n' "$2" >"$1/.nightshift/work-target"
}

# finding <id> — an ordinary finding, so a checkpoint cannot lean on a non-baseline id.
finding() {
  jq -nc --arg id "$1" '{
    schemaVersion:1, id:$id, domain:"lint", sourceClass:"eslint",
    source:"nsfakelint .", scope:"src/", severity:"medium", confidence:"high",
    impact:"developer", status:"open", ladder:"observed", locator:"src/app.js:3",
    digest:"d1", firstSeen:"2026-09-01T00:00:00Z", lastChecked:"2026-09-01T00:00:00Z",
    action:"fix", host:"claude", workTarget:"/repo"
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

# baseline_for <project> — a baseline record in <project>, printing its id.
baseline_for() {
  env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$BL" --project "$1" \
    --source-class eslint --command 'nsfakelint .'
}

# ---------------------------------------------------------------------------------------------

@test "a checkpoint states the worktree, the baseline, and the surface it may touch" {
  p="$(new_project cp-shape)"
  base="$(baseline_for "$p")"
  mkdir -p "$p/src/nested"
  printf 'one\n' >"$p/src/app.js"
  printf 'two\n' >"$p/src/nested/util.js"
  ln -s app.js "$p/src/link.js"

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" --baseline "$base" \
    --touched src/nested src/app.js src/link.js src/missing.js \
    --rollback 'git reset --hard HEAD' --plan 'nsfakelint . then the item gate'
  [ "$status" -eq 0 ]
  id="$output"
  case "$id" in checkpoint-*) ;; *) echo "unexpected id: $id"; return 1 ;; esac

  rec="$(record "$p" "$id")"
  printf '%s' "$rec" | jq -e '.domain == "checkpoint"' >/dev/null
  printf '%s' "$rec" | jq -e '.sourceClass == "git"' >/dev/null
  printf '%s' "$rec" | jq -e '.source == "git status --porcelain"' >/dev/null
  printf '%s' "$rec" | jq -e '.severity == "info" and .confidence == "high"' >/dev/null
  printf '%s' "$rec" | jq -e '.impact == "none" and .status == "open"' >/dev/null
  printf '%s' "$rec" | jq -e '.ladder == "observed"' >/dev/null
  printf '%s' "$rec" | jq -e '.rollback == "git reset --hard HEAD"' >/dev/null
  printf '%s' "$rec" | jq -e '.details | keys == ["artifacts","baseline","head","plan","rollback","touched","worktreeDigest"]' >/dev/null
  printf '%s' "$rec" | jq -e --arg b "$base" '.details.baseline == $b' >/dev/null
  printf '%s' "$rec" | jq -e '.details.plan == "nsfakelint . then the item gate"' >/dev/null
  printf '%s' "$rec" | jq -e '.details.rollback == "git reset --hard HEAD"' >/dev/null

  # The touched surface is sorted and deduplicated; the inventory covers only what exists, and
  # never a symlink.
  printf '%s' "$rec" | jq -e '.details.touched == ["src/app.js","src/link.js","src/missing.js","src/nested"]' >/dev/null
  printf '%s' "$rec" | jq -e '[.details.artifacts[].path] == ["src/app.js","src/nested"]' >/dev/null
  printf '%s' "$rec" | jq -e --arg d "$(sha256_stdin <"$p/src/app.js")" \
    '.details.artifacts[0].digest == $d' >/dev/null
  printf '%s' "$rec" | jq -e '.details.artifacts[1].digest | test("^[0-9a-f]{64}$")' >/dev/null

  printf '%s' "$rec" | jq -e --arg h "$(git -C "$p" rev-parse HEAD)" '.details.head == $h' >/dev/null
  expected="$(git -C "$p" status --porcelain | LC_ALL=C sort | sha256_stdin)"
  printf '%s' "$rec" | jq -e --arg d "$expected" '.details.worktreeDigest == $d' >/dev/null
}

@test "a directory inventory follows what is inside it" {
  p="$(new_project cp-dir)"
  base="$(baseline_for "$p")"
  mkdir -p "$p/src"
  printf 'one\n' >"$p/src/app.js"

  first="$(env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" --baseline "$base" \
    --touched src --rollback HEAD --plan 'the item gate')"
  before="$(record "$p" "$first" | jq -r '.details.artifacts[0].digest')"

  printf 'changed\n' >"$p/src/app.js"
  second="$(env NIGHTSHIFT_EVIDENCE_NOW=2026-09-02T03:30:00Z bash "$CP" --project "$p" \
    --baseline "$base" --touched src --rollback HEAD --plan 'the item gate')"
  after="$(record "$p" "$second" | jq -r '.details.artifacts[0].digest')"

  [ -n "$before" ]
  [ "$before" != "$after" ]
}

@test "a checkpoint repeats a touched path only once" {
  p="$(new_project cp-dedupe)"
  base="$(baseline_for "$p")"
  printf 'one\n' >"$p/app.js"
  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" --baseline "$base" \
    --touched app.js --touched app.js README.md --rollback HEAD --plan 'the item gate'
  [ "$status" -eq 0 ]
  rec="$(record "$p" "$output")"
  printf '%s' "$rec" | jq -e '.details.touched == ["README.md","app.js"]' >/dev/null
  printf '%s' "$rec" | jq -e '[.details.artifacts[].path] == ["app.js"]' >/dev/null
}

@test "a checkpoint refuses an id that is not a baseline in this ledger" {
  p="$(new_project cp-unknown)"
  bash "$EV" --project "$p" init >/dev/null
  bash "$EV" --project "$p" append --record "$(finding f1)" >/dev/null

  run --separate-stderr env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" \
    --baseline baseline-eslint-000000000000 --touched app.js --rollback HEAD --plan 'the gate'
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'no baseline record with id baseline-eslint-000000000000'

  run --separate-stderr env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" \
    --baseline f1 --touched app.js --rollback HEAD --plan 'the gate'
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'no baseline record with id f1'
}

@test "an unmeasured worktree never reads as a clean one" {
  p="$(new_workspace cp-nonrepo)"
  mkdir -p "$p/notes"
  work_target_record "$p" notes
  printf 'draft\n' >"$p/notes/plan.md"
  base="$(baseline_for "$p")"

  run env NIGHTSHIFT_EVIDENCE_NOW="$NOW" bash "$CP" --project "$p" --baseline "$base" \
    --touched notes/plan.md --rollback 'restore notes/plan.md from the receipts repo' \
    --plan 'read it back'
  [ "$status" -eq 0 ]
  rec="$(record "$p" "$output")"
  printf '%s' "$rec" | jq -e '.details.worktreeDigest == ""' >/dev/null
  printf '%s' "$rec" | jq -e '.details.head == ""' >/dev/null
  printf '%s' "$rec" | jq -e '.ladder == "declared"' >/dev/null
  printf '%s' "$rec" | jq -e '[.details.artifacts[].path] == ["notes/plan.md"]' >/dev/null
}

@test "a checkpoint refuses incomplete arguments and an unusable touched path" {
  p="$(new_project cp-usage)"
  base="$(baseline_for "$p")"

  run bash "$CP" --project "$p" --baseline "$base" --touched app.js --rollback HEAD
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qF 'usage: evidence-checkpoint.sh --project DIR'
  run bash "$CP" --project "$p" --baseline "$base" --touched app.js --plan 'the gate'
  [ "$status" -eq 1 ]
  run bash "$CP" --project "$p" --baseline "$base" --rollback HEAD --plan 'the gate'
  [ "$status" -eq 1 ]
  run bash "$CP" --project "$p" --touched app.js --rollback HEAD --plan 'the gate'
  [ "$status" -eq 1 ]

  run bash "$CP" --project "$p" --baseline "$base" --touched '' --rollback HEAD --plan 'the gate'
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qF 'a touched path must not be empty'

  run bash "$CP" --project "$p" --baseline "$base" --touched 'src/a
b.js' --rollback HEAD --plan 'the gate'
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qF 'a touched path must not contain a newline or a tab'

  bare="$BATS_TEST_TMPDIR/cp-bare"
  mkdir -p "$bare"
  run bash "$CP" --project "$bare" --baseline "$base" --touched app.js \
    --rollback HEAD --plan 'the gate'
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -qF 'no .nightshift/ at'
}

@test "jq and python3 write the same checkpoint bytes" {
  export NIGHTSHIFT_EVIDENCE_NOW="$NOW"
  p="$(new_project cp-parity)"
  base="$(baseline_for "$p")"
  printf 'one\n' >"$p/app.js"

  withjq="$(build_toolset_bin cp-with-jq $CHECKPOINT_TOOLSET_WITH_JQ)"
  pybin="$(build_toolset_bin cp-python $CHECKPOINT_TOOLSET_NO_JQ python3)"
  [ ! -e "$withjq/python3" ]
  [ ! -e "$pybin/jq" ]

  run env PATH="$withjq" bash "$CP" --project "$p" --baseline "$base" \
    --touched app.js --rollback HEAD --plan 'the item gate'
  [ "$status" -eq 0 ]
  run env PATH="$pybin" bash "$CP" --project "$p" --baseline "$base" \
    --touched app.js --rollback HEAD --plan 'the item gate'
  [ "$status" -eq 0 ]

  ledger="$p/.nightshift/evidence/findings.jsonl"
  [ "$(wc -l <"$ledger" | tr -d ' ')" = 3 ]
  [ "$(sed -n 2p "$ledger")" = "$(sed -n 3p "$ledger")" ]
}

@test "a checkpoint needs jq or python3 to read JSON" {
  p="$(new_project cp-neither)"
  bin="$(build_toolset_bin cp-neither-bin $CHECKPOINT_TOOLSET_NO_JQ)"
  [ ! -e "$bin/jq" ]
  [ ! -e "$bin/python3" ]
  run --separate-stderr env PATH="$bin" bash "$CP" --project "$p" \
    --baseline baseline-eslint-000000000000 --touched app.js --rollback HEAD --plan 'the gate'
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'JSON parser unavailable'
}

# Same shape as the baseline: the model writes the checkpoint receipt from the templates.
@test "the shift skills say when a checkpoint is written" {
  for f in "$ROOT/plugins/nightshift/skills/start/SKILL.md" \
    "$ROOT/plugins/nightshift/skills/nightshift/SKILL.md"; do
    tr '\n' ' ' <"$f" | grep -qiF 'before a risky cluster' \
      || { echo "no checkpoint trigger: $f"; return 1; }
    tr '\n' ' ' <"$f" | grep -qF 'the rollback ref' \
      || { echo "no rollback ref: $f"; return 1; }
    grep -qF 'references/receipt-templates.md' "$f" \
      || { echo "no receipt templates: $f"; return 1; }
  done
}
