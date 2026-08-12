HOOKS="$BATS_TEST_DIRNAME/../plugins/nightshift/hooks"

@test "both gate wrappers source one shared decision core" {
  grep -qF 'shared/gate-core.sh' "$HOOKS/clock-out-gate.sh"
  grep -qF '../shared/gate-core.sh' "$HOOKS/codex/clock-out-gate.sh"
  [ -f "$HOOKS/shared/gate-core.sh" ]
}

@test "both hardhat wrappers source one shared active-shift core" {
  grep -qF 'shared/hardhat-core.sh' "$HOOKS/hardhat.sh"
  grep -qF '../shared/hardhat-core.sh' "$HOOKS/codex/hardhat.sh"
  grep -qF 'ns_hardhat_active' "$HOOKS/hardhat.sh"
  grep -qF 'ns_hardhat_active' "$HOOKS/codex/hardhat.sh"
}

@test "host protocols remain in their wrappers" {
  ! grep -qE 'codex_emit|hookSpecificOutput' "$HOOKS/shared/gate-core.sh" "$HOOKS/shared/hardhat-core.sh"
  grep -qF 'codex_emit_block' "$HOOKS/codex/clock-out-gate.sh"
  grep -qF 'permissionDecision' "$HOOKS/hardhat.sh"
}
