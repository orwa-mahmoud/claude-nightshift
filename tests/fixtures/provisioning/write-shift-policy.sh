#!/usr/bin/env bash
# write-shift-policy.sh — write a test project's one-shift policy, with elevation allowances.
#
#   write-shift-policy.sh --project DIR [--tooling POLICY] [--shift-id HEX]
#                         [--allow CATEGORY] [--rules-allow CATEGORY]
#                         [--exact-plan CATEGORY] [--command TEXT]...
#
# Composition writes this file before the gate is armed and the writer refuses once it is; every
# test project is armed, so the fixture writes the document the resolver reads. A --command is
# taken as already normalized: single spaces, no leading or trailing space. The exact-plan digest
# is spelled out here rather than borrowed from the resolver, so a fixture cannot inherit the bug
# it is meant to catch.
set -eu

NL='
'

PROJECT=""
TOOLING="auto-add"
SHIFT_ID="9f2c40ab77e51d63"
ALLOWS=""
PLAN_CATEGORY=""
PLAN_COMMANDS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --tooling)
      TOOLING="$2"
      shift 2
      ;;
    --shift-id)
      SHIFT_ID="$2"
      shift 2
      ;;
    --allow)
      ALLOWS="$ALLOWS$2 one-shift$NL"
      shift 2
      ;;
    --rules-allow)
      ALLOWS="$ALLOWS$2 rules$NL"
      shift 2
      ;;
    --exact-plan)
      PLAN_CATEGORY="$2"
      shift 2
      ;;
    --command)
      PLAN_COMMANDS="$PLAN_COMMANDS$2$NL"
      shift 2
      ;;
    *)
      printf 'write-shift-policy: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PROJECT" ]; then
  printf 'write-shift-policy: --project is required\n' >&2
  exit 1
fi

sha256_text() { # digest of stdin, lowercase hex
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum)"
  else
    line="$(shasum -a 256)"
  fi
  printf '%s' "${line%% *}"
}

mkdir -p "$PROJECT/.nightshift"
printf 'repository\n' >"$PROJECT/.nightshift/work-mode"
printf '%s\n' "$PROJECT" >"$PROJECT/.nightshift/work-target"

# The canonical path a plan is approved against: the recorded target's repository root, physical.
TARGET="$(git -C "$PROJECT" rev-parse --show-toplevel)"
TARGET="$(cd -P "$TARGET" && pwd)"

ALLOWANCES="[]"
while IFS=' ' read -r category provenance; do
  [ -n "$category" ] || continue
  ALLOWANCES="$(printf '%s' "$ALLOWANCES" | jq -c \
    --arg c "$category" --arg p "$provenance" \
    '. + [{category: $c, scope: "category", provenance: $p}]')"
done <<EOF
$ALLOWS
EOF

if [ -n "$PLAN_CATEGORY" ]; then
  if [ -z "$PLAN_COMMANDS" ]; then
    printf 'write-shift-policy: --exact-plan needs at least one --command\n' >&2
    exit 1
  fi
  COMMANDS_JSON="$(printf '%s' "$PLAN_COMMANDS" | jq -R . | jq -sc .)"
  DIGEST="$(jq -nc --argjson commands "$COMMANDS_JSON" --arg shiftId "$SHIFT_ID" \
    --arg workTarget "$TARGET" \
    '{commands: $commands, shiftId: $shiftId, workTarget: $workTarget}' |
    jq -caS . | tr -d '\n' | sha256_text)"
  ALLOWANCES="$(printf '%s' "$ALLOWANCES" | jq -c \
    --arg c "$PLAN_CATEGORY" --argjson cmds "$COMMANDS_JSON" \
    --arg t "$TARGET" --arg d "$DIGEST" \
    '. + [{category: $c, scope: "exact-plan", provenance: "one-shift",
           plan: {commands: $cmds, workTarget: $t, digest: $d}}]')"
fi

jq -n --arg id "$SHIFT_ID" --arg tooling "$TOOLING" --argjson allowances "$ALLOWANCES" '{
  schemaVersion: 1,
  shiftId: $id,
  createdAt: "2026-01-01T00:00:00Z",
  source: "start-defaults",
  deadlineEpoch: null,
  verificationLevel: "none",
  toolingPolicy: $tooling,
  allowances: $allowances
}' >"$PROJECT/.nightshift/shift-policy.json"
