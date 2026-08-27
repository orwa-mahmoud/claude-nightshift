#!/usr/bin/env bash
# Shared clock-out decisions. Host wrappers own payload parsing and response emission.

ns_gate_open_boxes() { ns_open_boxes "$PUNCH"; }
ns_gate_ticked_boxes() { ns_ticked_boxes "$PUNCH"; }

ns_gate_project_head() {
  local r
  if r="$(ns_work_target "$PROJECT_DIR")"; then
    git -C "$r" rev-parse HEAD 2>/dev/null || printf 'nohead'
  else
    printf 'nohead'
  fi
}

# Stall progress token: repository mode uses the work-target HEAD; artifact mode uses
# completion receipts so a missing git repo cannot pretend a commit landed.
ns_gate_progress_token() {
  local mode
  mode="$(ns_work_mode "$PROJECT_DIR" 2>/dev/null)" || mode=repository
  if [ "$mode" = artifact ]; then
    ns_receipts_fingerprint "$PROJECT_DIR"
  else
    ns_gate_project_head
  fi
}

ns_gate_deadline_passed() {
  local now dl target
  now="$(date +%s)"
  dl="$(tr -d '[:space:]' <"$DEADLINE" 2>/dev/null || true)"
  [ -n "$dl" ] || return 1
  if printf '%s' "$dl" | grep -qE '^[0-9]+$'; then target="$dl"
  else target="$(date -d "$dl" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S' "$dl" +%s 2>/dev/null || true)"
  fi
  [ -n "$target" ] && [ "$now" -ge "$target" ]
}
