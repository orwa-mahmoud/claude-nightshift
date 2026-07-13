load helpers

@test "flags a broken shell script" {
  f="$BATS_TEST_TMPDIR/bad.sh"
  printf '#!/usr/bin/env bash\nif [ x\n' >"$f"
  run spotcheck "$f"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'spot-check'
}

@test "is silent on a clean shell script" {
  f="$BATS_TEST_TMPDIR/ok.sh"
  printf '#!/usr/bin/env bash\necho ok\n' >"$f"
  run spotcheck "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "flags invalid JSON" {
  f="$BATS_TEST_TMPDIR/bad.json"
  printf '{ nope,, }\n' >"$f"
  run spotcheck "$f"
  [ "$status" -eq 2 ]
}

@test "passes valid JSON" {
  f="$BATS_TEST_TMPDIR/ok.json"
  printf '{"a":1}\n' >"$f"
  run spotcheck "$f"
  [ "$status" -eq 0 ]
}

@test "skips a file that does not exist" {
  run spotcheck "$BATS_TEST_TMPDIR/missing.sh"
  [ "$status" -eq 0 ]
}

@test "flags malformed YAML when yamllint is available" {
  command -v yamllint >/dev/null 2>&1 || skip "yamllint not installed"
  f="$BATS_TEST_TMPDIR/bad.yaml"
  printf 'a: [1, 2\n' >"$f"
  run spotcheck "$f"
  [ "$status" -eq 2 ]
}

@test "degrades to bash -n when shellcheck is absent" {
  f="$BATS_TEST_TMPDIR/plain.sh"
  printf '#!/usr/bin/env bash\nx=1\n' >"$f"
  bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  for b in bash jq sed grep; do ln -sf "$(command -v "$b")" "$bindir/$b"; done
  run env PATH="$bindir" bash "$HOOKS/spot-check.sh" <<<"$(jq -nc --arg f "$f" '{tool_name:"Write",tool_input:{file_path:$f}}')"
  [ "$status" -eq 0 ]
}
