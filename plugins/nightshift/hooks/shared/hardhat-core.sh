#!/usr/bin/env bash
# Shared hardhat decisions. Host wrappers own payload parsing and deny response emission.

ns_hardhat_active() {
  [ -f "$NS/.shift-armed" ] && [ -f "$PUNCH" ] && [ ! -f "$ENDED" ] \
    && [ "$(ns_open_boxes "$PUNCH")" -gt 0 ]
}

ns_hardhat_rules_targeted() {
  printf '%s' "$1" | grep -qE '\.nightshift/rules\.json|nightshift-rules\.json'
}
