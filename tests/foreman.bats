setup() {
  FOREMAN="$BATS_TEST_DIRNAME/../adapters/foreman.sh"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.nightshift"
  git -C "$P" init -q
  git -C "$P" config user.email dev@example.com
  git -C "$P" config user.name tester
  git -C "$P" commit -q --allow-empty -m init
  printf '## Items\n- [ ] **1.**\n- [ ] **2.**\n- [ ] **3.**\n' >"$P/.nightshift/punch-list.md"

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  # ticks the first open box each invocation (CWD is the project — foreman cd's there)
  cat >"$BIN/tick_one.sh" <<'EOF'
#!/usr/bin/env bash
awk 'BEGIN{d=0} !d && /^- \[ \]/{sub(/\[ \]/,"[x]");d=1} {print}' .nightshift/punch-list.md >.nightshift/pl.tmp
mv .nightshift/pl.tmp .nightshift/punch-list.md
EOF
  # does nothing — no progress at all
  cat >"$BIN/noop.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  # commits (HEAD moves) but never ticks — a live walkthrough's shape
  cat >"$BIN/commit_only.sh" <<'EOF'
#!/usr/bin/env bash
git commit -q --allow-empty -m work 2>/dev/null || true
EOF
  chmod +x "$BIN"/*.sh
}

@test "drives the stub agent to completion (exit 0, every box ticked)" {
  run "$FOREMAN" --agent "bash $BIN/tick_one.sh" --project "$P" --max-iterations 10
  [ "$status" -eq 0 ]
  ! grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
}

@test "stops at the iteration cap (exit 3), items still open" {
  run "$FOREMAN" --agent "bash $BIN/commit_only.sh" --project "$P" --max-iterations 3 --stall 99
  [ "$status" -eq 3 ]
  grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
}

@test "stops at its own stall guard on a no-progress agent (exit 4, writes STOP)" {
  run "$FOREMAN" --agent "bash $BIN/noop.sh" --project "$P" --max-iterations 50 --stall 3
  [ "$status" -eq 4 ]
  [ -f "$P/.nightshift/STOP" ]
}

@test "does NOT false-stall on a commits-without-ticks agent (hits cap, exit 3)" {
  run "$FOREMAN" --agent "bash $BIN/commit_only.sh" --project "$P" --max-iterations 4 --stall 2
  [ "$status" -eq 3 ]
}

@test "stops at the deadline (exit 2), leaving items open" {
  run "$FOREMAN" --agent "bash $BIN/tick_one.sh" --project "$P" --deadline 1 --max-iterations 10
  [ "$status" -eq 2 ]
  grep -qE '^- \[ \]' "$P/.nightshift/punch-list.md"
}

@test "halts on a pre-existing stop-work order (exit 5)" {
  : >"$P/.nightshift/STOP"
  run "$FOREMAN" --agent "bash $BIN/tick_one.sh" --project "$P"
  [ "$status" -eq 5 ]
}

@test "fires the morning whistle on exit when configured" {
  wl="$BATS_TEST_TMPDIR/whistle.log"
  run env NIGHTSHIFT_NOTIFY_CMD="printf '%s\\n' \"\$NIGHTSHIFT_SUMMARY\" >> $wl" \
    "$FOREMAN" --agent "bash $BIN/tick_one.sh" --project "$P"
  [ "$status" -eq 0 ]
  grep -q 'foreman done' "$wl"
}

@test "requires --agent" {
  run "$FOREMAN" --project "$P"
  [ "$status" -eq 1 ]
}

@test "a custom punch-list path with no .nightshift dir runs without error spam" {
  P2="$BATS_TEST_TMPDIR/bare"
  mkdir -p "$P2"
  git -C "$P2" init -q
  git -C "$P2" config user.email dev@example.com
  git -C "$P2" config user.name tester
  git -C "$P2" commit -q --allow-empty -m init
  pl="$BATS_TEST_TMPDIR/list.md"
  printf -- '- [ ] **1.**\n' >"$pl"
  cat >"$BIN/tick_custom.sh" <<EOF
#!/usr/bin/env bash
sed -i.bak 's/\[ \]/[x]/' "$pl"
EOF
  chmod +x "$BIN/tick_custom.sh"
  run "$FOREMAN" --agent "bash $BIN/tick_custom.sh" --project "$P2" --punch-list "$pl" --max-iterations 5
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -qi 'no such file'
}

@test "usage prints the header only, no stray code lines" {
  run "$FOREMAN" --help
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q -- '--agent'
  ! printf '%s' "$output" | grep -q 'set -u'
  ! printf '%s' "$output" | grep -q 'AGENT='
}
